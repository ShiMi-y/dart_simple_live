import 'dart:convert';

import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// 醒目留言（SC）本地缓存
///
/// 语义：**留在直播间期间不计时**，只有退出直播间后才开始计算缓存有效期（5小时）。
/// - 进入房间：加载该房间的缓存 SC（需要重新展示）
/// - 房间内：新 SC 持续写入缓存，不做过期
/// - 退出房间：记录退出时间（开始 5 小时倒计时）
/// - 再次进入：若距上次退出不足 5 小时，重新展示这些 SC；超过则丢弃
class SuperChatCacheService extends GetxService {
  static SuperChatCacheService get instance =>
      Get.find<SuperChatCacheService>();

  /// 退出直播间后的缓存有效期：5 小时
  static const Duration ttl = Duration(hours: 5);

  /// 每个房间最多缓存的条数（防止异常情况下无限增长，正常使用几乎不会触发）
  static const int maxPerRoom = 500;

  static const String _boxName = "SuperChatCache";

  Box? _box;

  Future<SuperChatCacheService> init() async {
    try {
      _box = await Hive.openBox(_boxName);
      await prune();
    } catch (e) {
      Log.logPrint("SC缓存初始化失败: $e");
    }
    return this;
  }

  String _roomKey(String siteId, String roomId) => "${siteId}_$roomId";

  Map? _readRoom(String siteId, String roomId) {
    try {
      var raw = _box?.get(_roomKey(siteId, roomId));
      if (raw is Map) {
        return Map.from(raw);
      }
    } catch (e) {
      Log.logPrint("读取SC缓存失败: $e");
    }
    return null;
  }

  /// 读取某个房间的缓存SC
  ///
  /// [leftAt] 为空表示还没退出过房间（不计时），此时直接返回并开始计时。
  /// 退出超过 [ttl] 的缓存会被丢弃。
  List<LiveSuperChatMessage> load(String siteId, String roomId) {
    var result = <LiveSuperChatMessage>[];
    try {
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
          // 退出太久了，丢弃
          _box?.delete(_roomKey(siteId, roomId));
          return result;
        }
      } else {
        // 没记录退出时间（例如进程被强制结束）：从现在开始计时
        room["leftAt"] = now.millisecondsSinceEpoch ~/ 1000;
        _box?.put(_roomKey(siteId, roomId), room);
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

  /// 保存一条SC（房间内调用，不计时）
  Future<void> save(
      String siteId, String roomId, LiveSuperChatMessage sc) async {
    try {
      if (_box == null) {
        Log.logPrint("SC缓存不可用（box 未打开），跳过写入");
        return;
      }
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
      // 还在房间里：不计时
      room["leftAt"] = null;
      await _box!.put(key, room);
      Log.d("SC缓存写入: $key 共${items.length}条");
    } catch (e) {
      Log.logPrint("保存SC缓存失败: $e");
    }
  }

  /// 从缓存中移除某条SC（用于「SC栏点击隐藏」）
  Future<void> remove(
      String siteId, String roomId, LiveSuperChatMessage target) async {
    try {
      if (_box == null) {
        return;
      }
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
        await _box!.delete(key);
      } else {
        room["items"] = items;
        await _box!.put(key, room);
      }
    } catch (e) {
      Log.logPrint("移除SC缓存失败: $e");
    }
  }

  /// 退出直播间：开始计算 5 小时有效期
  Future<void> markLeft(String siteId, String roomId) async {
    try {
      if (_box == null) {
        return;
      }
      var key = _roomKey(siteId, roomId);
      var room = _readRoom(siteId, roomId);
      if (room == null) {
        return;
      }
      var items = room["items"];
      if (items is! List || items.isEmpty) {
        await _box!.delete(key);
        return;
      }
      room["leftAt"] = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await _box!.put(key, room);
    } catch (e) {
      Log.logPrint("记录SC缓存退出时间失败: $e");
    }
  }

  /// 清理退出超过有效期的缓存
  Future<void> prune() async {
    try {
      if (_box == null) {
        return;
      }
      var now = DateTime.now();
      var expiredKeys = <dynamic>[];
      for (var key in _box!.keys) {
        var raw = _box!.get(key);
        if (raw is! Map) {
          continue;
        }
        var leftAt = raw["leftAt"];
        if (leftAt is! int) {
          continue; // 还在房间里（或未记录），不清理
        }
        var leftTime = DateTime.fromMillisecondsSinceEpoch(leftAt * 1000);
        if (now.difference(leftTime) > ttl) {
          expiredKeys.add(key);
        }
      }
      for (var key in expiredKeys) {
        await _box!.delete(key);
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
