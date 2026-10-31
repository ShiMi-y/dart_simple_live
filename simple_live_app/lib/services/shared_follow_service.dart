import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_app/services/db_service.dart';

/// 多开时的「共享关注数据」
///
/// 多个实例各自持有自己的 Hive（受文件锁限制无法共用同一批 hive 文件），
/// 因此在应用支持目录下用一份 JSON 作为唯一数据源：
/// - `…/shared/follow_sync.json`（所有实例共用同一路径）
/// - 任一实例增删关注/标签（监听 Hive box 写入）→ 原子写入该文件并更新时间戳
/// - 每个实例每 2 秒检查一次文件，发现更新则同步到本地 Hive 并刷新关注列表
///
/// 冲突策略：按 updatedAt 取最新（后写覆盖先写），足够本地多开场景使用。
class SharedFollowService extends GetxService {
  static SharedFollowService get instance =>
      Get.find<SharedFollowService>();

  static const Duration pollInterval = Duration(seconds: 2);

  File? _file;
  Timer? _timer;
  Timer? _publishDebounce;
  int _lastUpdatedAt = 0;

  /// SC关注UID 的独立版本号（避免其他实例用空列表把已有UID覆盖掉）
  int _scUidsUpdatedAt = 0;
  String _lastPublishedScUids = "";
  bool _applying = false;
  bool _publishing = false;
  final List<StreamSubscription> _subscriptions = [];

  Future<SharedFollowService> init() async {
    if (Platform.isAndroid || Platform.isIOS) {
      return this;
    }
    try {
      var base = await getApplicationSupportDirectory();
      var dir = Directory(p.join(base.path, "shared"));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _file = File(p.join(dir.path, "follow_sync.json"));

      // 启动时先把共享数据同步到本地，保证多开实例看到同一份关注列表
      await _applyFromFileIfNewer(force: true);
      if (!await _file!.exists()) {
        await publish();
      }

      // 监听本地写入（关注/标签增删改）后发布
      _subscriptions.add(
        DBService.instance.followBox.watch().listen((_) => _schedulePublish()),
      );
      _subscriptions.add(
        DBService.instance.tagBox.watch().listen((_) => _schedulePublish()),
      );
      // SC关注UID 变化也发布
      _subscriptions.add(
        LocalStorageService.instance.scUidBox
            .watch()
            .listen((_) => _schedulePublish()),
      );

      // 轮询其他实例的修改
      _timer = Timer.periodic(pollInterval, (_) => _applyFromFileIfNewer());
      Log.d("共享关注数据初始化完成: ${_file!.path}");
    } catch (e) {
      Log.logPrint("共享关注数据初始化失败: $e");
    }
    return this;
  }

  /// 本地写入后延迟发布，避免批量操作触发多次写文件
  void _schedulePublish() {
    if (_applying) {
      return;
    }
    _publishDebounce?.cancel();
    _publishDebounce = Timer(const Duration(milliseconds: 400), publish);
  }

  /// 把本地关注/标签写入共享文件
  Future<void> publish() async {
    if (_file == null || _applying || _publishing) {
      return;
    }
    try {
      _publishing = true;
      var follows =
          DBService.instance.getFollowList().map((e) => e.toJson()).toList();
      var tags = DBService.instance
          .getFollowTagList()
          .map((e) => e.toJson())
          .toList();
      // 多开共享：SC关注UID（哔哩哔哩）
      var scUids = LocalStorageService.instance.scUidBox.keys
          .map((e) => e.toString())
          .toList();
      var updatedAt = DateTime.now().millisecondsSinceEpoch;
      if (updatedAt <= _lastUpdatedAt) {
        updatedAt = _lastUpdatedAt + 1;
      }
      // SC UID 使用独立版本号：只有内容真的变化时才递增，避免空列表覆盖他人配置
      var scUidsSignature = scUids.join(",");
      if (scUidsSignature != _lastPublishedScUids) {
        _scUidsUpdatedAt = _scUidsUpdatedAt + 1;
        _lastPublishedScUids = scUidsSignature;
      }
      var payload = jsonEncode({
        "version": 1,
        "updatedAt": updatedAt,
        "follows": follows,
        "tags": tags,
        "scUids": scUids,
        "scUidsUpdatedAt": _scUidsUpdatedAt,
      });
      var tmp = File("${_file!.path}.tmp");
      await tmp.writeAsString(payload, flush: true);
      await tmp.rename(_file!.path);
      _lastUpdatedAt = updatedAt;
      Log.d(
        "已发布共享关注数据: ${follows.length}个主播 / ${tags.length}个标签 / ${scUids.length}个SC-UID",
      );
    } catch (e) {
      Log.logPrint("写入共享关注数据失败: $e");
    } finally {
      _publishing = false;
    }
  }

  /// 读取共享文件，若有更新则应用到本地
  Future<void> _applyFromFileIfNewer({bool force = false}) async {
    if (_file == null || _applying || _publishing) {
      return;
    }
    try {
      if (!await _file!.exists()) {
        return;
      }
      var content = await _file!.readAsString();
      if (content.trim().isEmpty) {
        return;
      }
      var data = jsonDecode(content);
      if (data is! Map) {
        return;
      }
      var updatedAt = data["updatedAt"] is int ? data["updatedAt"] as int : 0;
      if (data["scUidsUpdatedAt"] is int) {
        _scUidsUpdatedAt = data["scUidsUpdatedAt"] as int;
      }
      if (!force && updatedAt <= _lastUpdatedAt) {
        return;
      }
      _lastUpdatedAt = updatedAt;
      _applying = true;
      await _apply(data);
      // 通知关注列表刷新
      EventBus.instance.emit(Constant.kUpdateFollow, null);
    } catch (e) {
      Log.logPrint("同步共享关注数据失败: $e");
    } finally {
      _applying = false;
    }
  }

  Future<void> _apply(Map data) async {
    var follows = <FollowUser>[];
    var rawFollows = data["follows"];
    if (rawFollows is List) {
      for (var item in rawFollows) {
        if (item is Map) {
          try {
            follows.add(FollowUser.fromJson(Map<String, dynamic>.from(item)));
          } catch (e) {
            Log.logPrint("解析共享关注项失败: $e");
          }
        }
      }
    }
    var tags = <FollowUserTag>[];
    var rawTags = data["tags"];
    if (rawTags is List) {
      for (var item in rawTags) {
        if (item is Map) {
          try {
            tags.add(
              FollowUserTag.fromJson(Map<String, dynamic>.from(item)),
            );
          } catch (e) {
            Log.logPrint("解析共享标签项失败: $e");
          }
        }
      }
    }
    var db = DBService.instance;
    await db.followBox.clear();
    for (var follow in follows) {
      await db.followBox.put(follow.id, follow);
    }
    await db.tagBox.clear();
    for (var tag in tags) {
      await db.tagBox.put(tag.id, tag);
    }
    // 共享 SC关注UID
    var rawScUids = data["scUids"];
    var scUids = <String>[];
    if (rawScUids is List) {
      for (var item in rawScUids) {
        var uid = item.toString().trim();
        if (uid.isNotEmpty) {
          scUids.add(uid);
        }
      }
    }
    var remoteScUidsVersion = data["scUidsUpdatedAt"] is int
        ? data["scUidsUpdatedAt"] as int
        : 0;
    if (rawScUids is List && remoteScUidsVersion > _scUidsUpdatedAt) {
      _scUidsUpdatedAt = remoteScUidsVersion;
      _lastPublishedScUids = scUids.join(",");
      await AppSettingsController.instance.replaceScUidList(scUids.toSet());
    }
    Log.d(
      "已同步共享关注数据: ${follows.length}个主播 / ${tags.length}个标签 / ${scUids.length}个SC-UID",
    );
  }

  @override
  void onClose() {
    _timer?.cancel();
    _publishDebounce?.cancel();
    for (var subscription in _subscriptions) {
      subscription.cancel();
    }
    super.onClose();
  }
}
