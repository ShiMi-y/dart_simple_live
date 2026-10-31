import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// 醒目留言（SC）本地缓存
///
/// 语义：**留在直播间期间不计时**，只有退出直播间后才开始计算缓存有效期（5小时）。
///
/// 存储：`<应用数据目录>/shared/sc_cache.json`（**多开实例共享同一份**）。
/// 早期版本存在各实例自己的 Hive box 里，初始化时会自动迁移。
class SuperChatCacheService extends GetxService {
  static SuperChatCacheService get instance =>
      Get.find<SuperChatCacheService>();

  /// 退出直播间后的缓存有效期：5 小时
  static const Duration ttl = Duration(hours: 5);

  /// 每个房间最多缓存的条数
  static const int maxPerRoom = 500;

  /// 旧版本（实例私有）box 名，仅用于迁移
  static const String _legacyBoxName = "SuperChatCache";
  static const String _fileName = "sc_cache.json";

  File? _file;

  /// 房间key -> {"leftAt": int?, "items": [...]}
  Map<String, dynamic> _data = {};

  Future<SuperChatCacheService> init() async {
    try {
      var dir = await getApplicationSupportDirectory();
      var sharedDir = Directory("${dir.path}${Platform.pathSeparator}shared");
      if (!await sharedDir.exists()) {
        await sharedDir.create(recursive: true);
      }
      _file = File("${sharedDir.path}${Platform.pathSeparator}$_fileName");
      await _reload();
      await _migrateFromLegacyBox();
      await prune();
      Log.d("SC缓存初始化: ${_data.length}个房间 (${_file!.path})");
    } catch (e) {
      Log.logPrint("SC缓存初始化失败: $e");
    }
    return this;
  }

  String _roomKey(String siteId, String roomId) => "${siteId}_$roomId";

  Future<void> _reload() async {
    try {
      var f = _file;
      if (f == null || !await f.exists()) {
        _data = {};
        return;
      }
      var text = await f.readAsString();
      if (text.trim().isEmpty) {
        _data = {};
        return;
      }
      var decoded = jsonDecode(text);
      _data = decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (e) {
      Log.logPrint("读取SC缓存文件失败: $e");
      _data = {};
    }
  }

  Future<void> _persist() async {
    try {
      var f = _file;
      if (f == null) {
        return;
      }
      var tmp = File("${f.path}.tmp");
      await tmp.writeAsString(jsonEncode(_data), flush: true);
      await tmp.rename(f.path);
    } catch (e) {
      Log.logPrint("写入SC缓存文件失败: $e");
    }
  }

  /// 把旧版本（实例私有 Hive）的数据合并进共享文件
  Future<void> _migrateFromLegacyBox() async {
    try {
      if (!Hive.isBoxOpen(_legacyBoxName)) {
        return;
      }
      var box = Hive.box(_legacyBoxName);
      if (box.isEmpty) {
        return;
      }
      var merged = 0;
      for (var key in box.keys) {
        var raw = box.get(key);
        if (raw is! Map) {
          continue;
        }
        var k = key.toString();
        if (_data.containsKey(k)) {
          continue; // 已存在的不覆盖
        }
        _data[k] = Map<String, dynamic>.from(raw);
        merged++;
      }
      if (merged > 0) {
        await _persist();
        Log.d("SC缓存迁移: 从旧box合并 $merged 个房间");
      }
    } catch (e) {
      Log.logPrint("SC缓存迁移失败: $e");
    }
  }

  Map? _readRoom(String siteId, String roomId) {
    var raw = _data[_roomKey(siteId, roomId)];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  /// 读取某个房间的缓存SC
  List<LiveSuperChatMessage> load(String siteId, String roomId) {
    var result = <LiveSuperChatMessage>[];
    try {
      // 读之前先同步文件（其它实例可能刚写过）
      _reloadSync();
      var room = _readRoom(siteId, roomId);
      var roomKey = _roomKey(siteId, roomId);
      if (room == null) {
        Log.d("SC缓存读取: $roomKey 无记录");
        return result;
      }
      var items = room["items"];
      if (items is! List || items.isEmpty) {
        Log.d("SC缓存读取: $roomKey 记录为空");
        return result;
      }
      Log.d("SC缓存读取: $roomKey 共${items.length}条 leftAt=${room["leftAt"]}");
      var leftAt = room["leftAt"];
      var now = DateTime.now();
      if (leftAt is int) {
        var leftTime = DateTime.fromMillisecondsSinceEpoch(leftAt * 1000);
        if (now.difference(leftTime) > ttl) {
          _data.remove(roomKey);
          _persist();
          return result;
        }
      } else {
        room["leftAt"] = now.millisecondsSinceEpoch ~/ 1000;
        _data[roomKey] = room;
        _persist();
      }
      for (var item in items) {
        if (item is! Map) {
          continue;
        }
        var sc = decode(item["sc"]);
        if (sc != null) {
          result.add(sc);
        }
      }
    } catch (e) {
      Log.logPrint("读取SC缓存失败: $e");
    }
    return result;
  }

  /// 同步读取（load 是同步 API，避免大改调用方）
  void _reloadSync() {
    try {
      var f = _file;
      if (f == null || !f.existsSync()) {
        return;
      }
      var text = f.readAsStringSync();
      if (text.trim().isEmpty) {
        return;
      }
      var decoded = jsonDecode(text);
      if (decoded is Map) {
        _data = Map<String, dynamic>.from(decoded);
      }
    } catch (e) {
      Log.logPrint("同步读取SC缓存失败: $e");
    }
  }

  /// 保存一条SC（房间内调用，不计时）
  Future<void> save(
      String siteId, String roomId, LiveSuperChatMessage sc) async {
    try {
      await _reload();
      var key = _roomKey(siteId, roomId);
      var room = _readRoom(siteId, roomId) ?? {"leftAt": null, "items": []};
      var items = <Map>[];
      var rawItems = room["items"];
      if (rawItems is List) {
        items = rawItems.whereType<Map>().toList();
      }
      items.add({
        "at": DateTime.now().millisecondsSinceEpoch ~/ 1000,
        "sc": encode(sc),
      });
      if (items.length > maxPerRoom) {
        items = items.sublist(items.length - maxPerRoom);
      }
      room["items"] = items;
      room["leftAt"] = null;
      _data[key] = room;
      await _persist();
      Log.d("SC缓存写入: $key 共${items.length}条");
    } catch (e) {
      Log.logPrint("保存SC缓存失败: $e");
    }
  }

  /// 从缓存中移除某条SC（用于「SC栏点击隐藏」）
  Future<void> remove(
      String siteId, String roomId, LiveSuperChatMessage target) async {
    try {
      await _reload();
      var key = _roomKey(siteId, roomId);
      var room = _readRoom(siteId, roomId);
      if (room == null) {
        return;
      }
      var items = <Map>[];
      var rawItems = room["items"];
      if (rawItems is List) {
        items = rawItems.whereType<Map>().toList();
      }
      var targetKey = signature(target);
      items.removeWhere((item) => signatureOfEncoded(item["sc"]) == targetKey);
      if (items.isEmpty) {
        _data.remove(key);
      } else {
        room["items"] = items;
        _data[key] = room;
      }
      await _persist();
    } catch (e) {
      Log.logPrint("移除SC缓存失败: $e");
    }
  }

  /// 退出直播间：开始计算 5 小时有效期
  Future<void> markLeft(String siteId, String roomId) async {
    try {
      await _reload();
      var key = _roomKey(siteId, roomId);
      var room = _readRoom(siteId, roomId);
      if (room == null) {
        return;
      }
      var items = room["items"];
      if (items is! List || items.isEmpty) {
        _data.remove(key);
        await _persist();
        return;
      }
      room["leftAt"] = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      _data[key] = room;
      await _persist();
    } catch (e) {
      Log.logPrint("记录SC缓存退出时间失败: $e");
    }
  }

  /// 清理退出超过有效期的缓存
  Future<void> prune() async {
    try {
      var now = DateTime.now();
      var changed = false;
      for (var key in _data.keys.toList()) {
        var raw = _data[key];
        if (raw is! Map) {
          continue;
        }
        var leftAt = raw["leftAt"];
        if (leftAt is! int) {
          continue;
        }
        var leftTime = DateTime.fromMillisecondsSinceEpoch(leftAt * 1000);
        if (now.difference(leftTime) > ttl) {
          _data.remove(key);
          changed = true;
        }
      }
      if (changed) {
        await _persist();
      }
    } catch (e) {
      Log.logPrint("清理SC缓存失败: $e");
    }
  }

  /// SC去重标识
  String signature(LiveSuperChatMessage sc) =>
      "${sc.userName}|${sc.message}|${sc.price}|${sc.startTime.millisecondsSinceEpoch}";

  String signatureOfEncoded(dynamic encoded) {
    var sc = decode(encoded);
    if (sc == null) {
      return "";
    }
    return signature(sc);
  }

  /// 序列化（LiveSuperChatMessage 的 toString 本身就是 JSON）
  dynamic encode(LiveSuperChatMessage sc) {
    try {
      return jsonDecode(sc.toString());
    } catch (e) {
      return null;
    }
  }

  /// 反序列化
  LiveSuperChatMessage? decode(dynamic json) {
    try {
      var map = json is String ? jsonDecode(json) : json;
      if (map is! Map) {
        return null;
      }
      return LiveSuperChatMessage(
        userName: map["userName"]?.toString() ?? "",
        face: map["face"]?.toString() ?? "",
        message: map["message"]?.toString() ?? "",
        price: map["price"] is int ? map["price"] as int : 0,
        startTime: DateTime.tryParse(map["startTime"]?.toString() ?? "") ??
            DateTime.now(),
        endTime: DateTime.tryParse(map["endTime"]?.toString() ?? "") ??
            DateTime.now(),
        backgroundColor: map["backgroundColor"]?.toString() ?? "",
        backgroundBottomColor:
            map["backgroundBottomColor"]?.toString() ?? "",
        isCustom: map["isCustom"] == true,
      );
    } catch (e) {
      return null;
    }
  }
}
