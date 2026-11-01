import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:simple_live_app/app/instance.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/requests/http_client.dart';
import 'package:simple_live_app/services/background_play_service.dart';
import 'package:simple_live_app/services/bilibili_account_service.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// 单个挂机房间
class IntimacyRoom {
  final String roomId;

  final RxString title = "".obs;
  final RxBool live = false.obs;
  final RxString lastBeat = "".obs;
  final RxString lastResult = "".obs;

  IntimacyRoom(this.roomId);
}

/// 一条运行日志
class IntimacyLog {
  final DateTime time;
  final String room;
  final String text;

  IntimacyLog(this.time, this.room, this.text);
}

/// 自动挂亲密度（哔哩哔哩）
///
/// 机制：对已开播的房间**保持直播间 WebSocket 连接**（内部自带心跳），
/// 使服务端认为用户持续在观看，从而累计粉丝牌亲密度。
/// 说明：HTTP 心跳接口（x/report/click/heartbeat）在部分网络下会被 CDN 以
/// 404 WebProxyNeedLess 拦截，故不作为主路径，仅在连接失败时尝试一次。
class IntimacyService extends GetxService {
  static IntimacyService get instance => Get.find<IntimacyService>();

  static const String _roomsKey = "IntimacyRooms";
  static const String _enabledKey = "IntimacyEnabled";
  static const String _ua =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";

  final RxBool enabled = false.obs;
  final RxBool suspended = false.obs;
  final RxList<IntimacyRoom> rooms = <IntimacyRoom>[].obs;
  final RxList<IntimacyLog> logs = <IntimacyLog>[].obs;

  int _consecutiveFailures = 0;
  static const int maxConsecutiveFailures = 5;

  Timer? _timer;
  Timer? _syncTimer;
  bool _ticking = false;

  File? _sharedFile;

  /// 已建立的直播间连接（房间号 -> danmaku）
  final Map<String, LiveDanmaku> _connections = {};

  bool get isOwner => isPrimaryInstance;

  Future<void> init() async {
    try {
      var dir = await getApplicationSupportDirectory();
      var sharedDir = Directory("${dir.path}${Platform.pathSeparator}shared");
      if (!await sharedDir.exists()) {
        await sharedDir.create(recursive: true);
      }
      _sharedFile =
          File("${sharedDir.path}${Platform.pathSeparator}intimacy.json");
      await _reloadFromShared();
      await _migrateLegacyConfig();

      _syncTimer?.cancel();
      _syncTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        _reloadFromShared();
      });

      if (enabled.value && isOwner) {
        start();
      }
      Log.d(
        "亲密度挂机初始化: 实例=$instanceIndex 执行=$isOwner 启用=${enabled.value} 房间=${rooms.length}",
      );
    } catch (e) {
      Log.logPrint("亲密度挂机初始化失败: $e");
    }
  }

  // ---------------- 配置（跨实例共享） ----------------

  Future<void> _reloadFromShared() async {
    try {
      var f = _sharedFile;
      if (f == null || !await f.exists()) {
        return;
      }
      var text = await f.readAsString();
      if (text.trim().isEmpty) {
        return;
      }
      var data = jsonDecode(text);
      if (data is! Map) {
        return;
      }
      enabled.value = data["enabled"] == true;
      var rawRooms = data["rooms"];
      if (rawRooms is List) {
        var ids = rawRooms
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
        for (var id in ids) {
          if (!rooms.any((e) => e.roomId == id)) {
            rooms.add(IntimacyRoom(id));
          }
        }
        var removed = rooms.where((e) => !ids.contains(e.roomId)).toList();
        for (var r in removed) {
          _closeConnection(r.roomId);
          rooms.remove(r);
        }
      }
      if (isOwner && enabled.value && _timer == null && rooms.isNotEmpty) {
        _startTimerOnly();
      } else if ((!isOwner || !enabled.value) && _timer != null) {
        _stopTimerOnly();
      }
    } catch (e) {
      Log.logPrint("读取亲密度共享配置失败: $e");
    }
  }

  Future<void> _saveShared() async {
    try {
      var f = _sharedFile;
      if (f == null) {
        return;
      }
      var payload = jsonEncode({
        "enabled": enabled.value,
        "rooms": rooms.map((e) => e.roomId).toList(),
        "updatedBy": instanceIndex,
        "updatedAt": DateTime.now().millisecondsSinceEpoch,
      });
      var tmp = File("${f.path}.tmp");
      await tmp.writeAsString(payload, flush: true);
      await tmp.rename(f.path);
      Log.d("亲密度配置已保存: 实例=$instanceIndex 房间=${rooms.length} 启用=${enabled.value}");
    } catch (e) {
      Log.logPrint("保存亲密度配置失败: $e");
    }
  }

  Future<void> _migrateLegacyConfig() async {
    try {
      var f = _sharedFile;
      if (f == null || await f.exists()) {
        return;
      }
      var saved = LocalStorageService.instance.getValue(_roomsKey, "").toString();
      var legacyEnabled =
          LocalStorageService.instance.getValue(_enabledKey, false) == true;
      if (saved.isEmpty && !legacyEnabled) {
        return;
      }
      enabled.value = legacyEnabled;
      for (var id in saved.split(",")) {
        var rid = id.trim();
        if (rid.isNotEmpty && !rooms.any((e) => e.roomId == rid)) {
          rooms.add(IntimacyRoom(rid));
        }
      }
      await _saveShared();
      Log.d("亲密度配置已迁移到共享文件");
    } catch (e) {
      Log.logPrint("迁移亲密度配置失败: $e");
    }
  }

  // ---------------- 房间管理 ----------------

  String? parseRoomId(String input) {
    var text = input.trim();
    if (text.isEmpty) {
      return null;
    }
    var m = RegExp(r"live\.bilibili\.com/(\d+)").firstMatch(text);
    if (m != null) {
      return m.group(1);
    }
    return RegExp(r"^\d+$").hasMatch(text) ? text : null;
  }

  Future<bool> addRoomById(String roomId, {String? title}) async {
    var id = roomId.trim();
    if (id.isEmpty) {
      return false;
    }
    if (rooms.any((e) => e.roomId == id)) {
      return false;
    }
    var room = IntimacyRoom(id);
    if (title != null && title.isNotEmpty) {
      room.title.value = title;
    }
    rooms.add(room);
    await _saveShared();
    _checkRoom(room);
    return true;
  }

  Future<bool> addRoom(String input) async {
    var id = parseRoomId(input);
    if (id == null) {
      _addLog("-", "房间号格式不正确");
      return false;
    }
    return addRoomById(id);
  }

  Future<void> removeRoom(String roomId) async {
    _closeConnection(roomId);
    rooms.removeWhere((e) => e.roomId == roomId);
    await _saveShared();
  }

  Future<void> setEnabled(bool value) async {
    enabled.value = value;
    await _saveShared();
    if (value) {
      start();
    } else {
      stop();
    }
  }

  // ---------------- 运行 ----------------

  void start() {
    if (!isOwner) {
      _addLog("-", "当前不是实例1，挂机由实例1执行（本实例仅同步配置）");
      return;
    }
    if (rooms.isEmpty) {
      _addLog("-", "没有配置直播间，未启动挂机");
      return;
    }
    try {
      BackgroundPlayService.start();
    } catch (_) {}
    _startTimerOnly();
    _addLog("-", "已启动挂机（每 60 秒检查一次，实例$instanceIndex）");
  }

  void _startTimerOnly() {
    if (_timer != null) {
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _tick());
    _tick();
  }

  void _stopTimerOnly() {
    _timer?.cancel();
    _timer = null;
    try {
      BackgroundPlayService.stop();
    } catch (_) {}
  }

  void stop() {
    for (var rid in _connections.keys.toList()) {
      _closeConnection(rid);
    }
    _stopTimerOnly();
    _addLog("-", "已停止挂机");
  }

  Future<void> retry() async {
    _consecutiveFailures = 0;
    suspended.value = false;
    _addLog("-", "手动重试挂机");
    if (!isOwner) {
      _addLog("-", "当前不是实例1，挂机由实例1执行");
      return;
    }
    await _reloadFromShared();
    if (rooms.isEmpty) {
      _addLog("-", "没有配置直播间");
      return;
    }
    _startTimerOnly();
  }

  Future<void> _tick() async {
    if (!isOwner || suspended.value) {
      return;
    }
    if (_ticking || rooms.isEmpty) {
      return;
    }
    _ticking = true;
    try {
      if (!BiliBiliAccountService.instance.logined.value) {
        _addLog("-", "未登录哔哩哔哩，跳过一次检查");
        return;
      }
      for (var room in rooms) {
        await _checkRoom(room);
        await Future.delayed(const Duration(milliseconds: 600));
      }
    } catch (e) {
      Log.logPrint("亲密度检查失败: $e");
    } finally {
      _ticking = false;
    }
  }

  Future<void> _checkRoom(IntimacyRoom room) async {
    try {
      var info = await HttpClient.instance.getJson(
        "https://api.live.bilibili.com/room/v1/Room/get_info",
        queryParameters: {"room_id": room.roomId},
        header: {"User-Agent": _ua, "Referer": "https://live.bilibili.com/"},
      );
      var map = info is Map ? info : null;
      if (map == null || map["code"] != 0) {
        _fail(room, "获取房间信息失败");
        return;
      }
      var data = map["data"] as Map;
      var title = data["title"]?.toString() ?? "";
      if (title.isNotEmpty) {
        room.title.value = title;
      }
      var live = data["live_status"] == 1;
      room.live.value = live;
      if (!live) {
        _closeConnection(room.roomId);
        room.lastResult.value = "未开播";
        _consecutiveFailures = 0;
        return;
      }
      await _ensureConnection(room);
    } catch (e) {
      _fail(room, "检查失败: $e");
    }
  }

  /// 保持直播间连接（内部自带心跳），使服务端认为持续在看
  Future<void> _ensureConnection(IntimacyRoom room) async {
    if (_connections.containsKey(room.roomId)) {
      room.lastResult.value = "已在线（保持连接中）";
      room.lastBeat.value = _hhmm(DateTime.now());
      _consecutiveFailures = 0;
      suspended.value = false;
      return;
    }
    try {
      var site = Sites.allSites["bilibili"];
      if (site == null) {
        _fail(room, "未找到哔哩哔哩站点");
        return;
      }
      var detail = await site.liveSite.getRoomDetail(roomId: room.roomId);
      if (room.title.value.isEmpty) {
        room.title.value = detail.title;
      }
      var danmaku = site.liveSite.getDanmaku();
      danmaku.onReady = () {
        room.lastBeat.value = _hhmm(DateTime.now());
        room.lastResult.value = "已进入直播间（在线）";
        _consecutiveFailures = 0;
        suspended.value = false;
        _addLog(room.roomId, "已进入直播间，保持在线");
      };
      danmaku.onClose = (msg) {
        _connections.remove(room.roomId);
        room.lastResult.value = "连接断开";
        _addLog(room.roomId, "直播间连接断开: $msg");
      };
      await danmaku.start(detail.danmakuData);
      _connections[room.roomId] = danmaku;
      room.lastBeat.value = _hhmm(DateTime.now());
      room.lastResult.value = "连接中…";
      _addLog(room.roomId, "开始保持直播间连接");
    } catch (e) {
      _fail(room, "进入直播间失败: $e");
    }
  }

  void _closeConnection(String roomId) {
    try {
      _connections.remove(roomId)?.stop();
    } catch (e) {
      Log.logPrint("关闭直播间连接失败: $e");
    }
  }

  void _fail(IntimacyRoom room, String message) {
    room.lastResult.value = message;
    _consecutiveFailures++;
    _addLog(room.roomId, "$message（连续$_consecutiveFailures次）");
    if (_consecutiveFailures >= maxConsecutiveFailures) {
      suspended.value = true;
      _stopTimerOnly();
      _addLog(
        "-",
        "连续失败$maxConsecutiveFailures次，已暂停挂机；请检查登录态后点「重试」，或重启应用",
      );
    }
  }

  String _hhmm(DateTime t) =>
      "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";

  void _addLog(String room, String text) {
    logs.insert(0, IntimacyLog(DateTime.now(), room, text));
    if (logs.length > 80) {
      logs.removeRange(80, logs.length);
    }
    Log.d("亲密度挂机: [$room] $text");
  }

  @override
  void onClose() {
    for (var rid in _connections.keys.toList()) {
      _closeConnection(rid);
    }
    _syncTimer?.cancel();
    _timer?.cancel();
    super.onClose();
  }
}
