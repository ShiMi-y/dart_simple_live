import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/requests/http_client.dart';
import 'package:simple_live_app/services/bilibili_account_service.dart';
import 'package:simple_live_app/services/local_storage_service.dart';

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

/// 后台自动挂亲密度（哔哩哔哩）
///
/// 定时检查配置的直播间是否开播；开播后按哔哩哔哩网页心跳接口发送心跳，
/// 维持在线时长以获取粉丝牌亲密度。需要已登录哔哩哔哩账号。
class IntimacyService extends GetxService {
  static IntimacyService get instance => Get.find<IntimacyService>();

  static const String _roomsKey = "IntimacyRooms";
  static const String _enabledKey = "IntimacyEnabled";
  static const String _ua =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";

  final RxBool enabled = false.obs;
  final RxList<IntimacyRoom> rooms = <IntimacyRoom>[].obs;
  final RxList<IntimacyLog> logs = <IntimacyLog>[].obs;

  Timer? _timer;
  bool _ticking = false;

  Future<void> init() async {
    try {
      enabled.value =
          LocalStorageService.instance.getValue(_enabledKey, false) == true;
      var saved =
          LocalStorageService.instance.getValue(_roomsKey, "").toString();
      for (var id in saved.split(",")) {
        var roomId = id.trim();
        if (roomId.isEmpty) {
          continue;
        }
        if (rooms.any((e) => e.roomId == roomId)) {
          continue;
        }
        rooms.add(IntimacyRoom(roomId));
      }
      if (enabled.value) {
        start();
      }
      Log.d("亲密度挂机初始化: 启用=${enabled.value} 房间=${rooms.length}");
    } catch (e) {
      Log.logPrint("亲密度挂机初始化失败: $e");
    }
  }

  Future<void> _persist() async {
    try {
      await LocalStorageService.instance
          .setValue(_roomsKey, rooms.map((e) => e.roomId).join(","));
      await LocalStorageService.instance.setValue(_enabledKey, enabled.value);
    } catch (e) {
      Log.logPrint("保存亲密度配置失败: $e");
    }
  }

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

  Future<bool> addRoom(String input) async {
    var id = parseRoomId(input);
    if (id == null) {
      _addLog("-", "房间号格式不正确");
      return false;
    }
    if (rooms.any((e) => e.roomId == id)) {
      return false;
    }
    rooms.add(IntimacyRoom(id));
    await _persist();
    // 立刻检查一次
    _checkRoom(rooms.last);
    return true;
  }

  Future<void> removeRoom(String roomId) async {
    rooms.removeWhere((e) => e.roomId == roomId);
    await _persist();
  }

  Future<void> setEnabled(bool value) async {
    enabled.value = value;
    await _persist();
    if (value) {
      start();
    } else {
      stop();
    }
  }

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _tick());
    _tick();
    _addLog("-", "已启动挂机（每 60 秒检查一次）");
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _addLog("-", "已停止挂机");
  }

  Future<void> _tick() async {
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
        await Future.delayed(const Duration(milliseconds: 800));
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
      if (info is! Map || info["code"] != 0) {
        room.lastResult.value = "获取房间信息失败";
        return;
      }
      var data = info["data"] as Map;
      var title = data["title"]?.toString() ?? "";
      if (title.isNotEmpty) {
        room.title.value = title;
      }
      var live = data["live_status"] == 1;
      room.live.value = live;
      if (!live) {
        room.lastResult.value = "未开播";
        return;
      }
      await _sendHeartbeat(room);
    } catch (e) {
      room.lastResult.value = "检查失败: $e";
      Log.logPrint("亲密度检查房间 ${room.roomId} 失败: $e");
    }
  }

  String _cookieValue(String cookie, String key) {
    for (var part in cookie.split(";")) {
      var kv = part.trim();
      if (kv.startsWith("$key=")) {
        return kv.substring(key.length + 1);
      }
    }
    return "";
  }

  Map? _asMap(dynamic res) {
    if (res is Map) {
      return res;
    }
    if (res is String) {
      try {
        var decoded = jsonDecode(res);
        return decoded is Map ? decoded : null;
      } catch (_) {}
    }
    return null;
  }

  String _short(dynamic res) {
    var text = res?.toString() ?? "";
    text = text.replaceAll("\n", " ").replaceAll("\r", " ").trim();
    return text.length > 180 ? "${text.substring(0, 180)}..." : text;
  }

  Future<void> _sendHeartbeat(IntimacyRoom room) async {
    var cookie = BiliBiliAccountService.instance.cookie;
    if (cookie.isEmpty) {
      room.lastResult.value = "未登录";
      return;
    }
    var csrf = _cookieValue(cookie, "bili_jct");
    var uid = BiliBiliAccountService.instance.uid.toString();
    var header = {
      "Cookie": cookie,
      "User-Agent": _ua,
      "Referer": "https://live.bilibili.com/${room.roomId}",
      "Origin": "https://live.bilibili.com",
      "Content-Type": "application/x-www-form-urlencoded",
    };
    // 哔哩哔哩的网页心跳要求表单编码（JSON 会被忽略并返回非 JSON）
    var form = {
      "room_id": room.roomId,
      "uid": uid,
      "csrf": csrf,
      "csrf_token": csrf,
      "platform": "web",
      "visit_id": "",
    };
    var query = {"room_id": room.roomId, "csrf": csrf};

    var endpoints = const [
      "https://api.live.bilibili.com/x/report/click/web/heartbeat",
      "https://api.live.bilibili.com/x/report/click/heartbeat",
    ];
    var tried = <String>[];
    for (var url in endpoints) {
      try {
        var res = await HttpClient.instance.postJson(
          url,
          queryParameters: query,
          data: form,
          header: header,
          formUrlEncoded: true,
        );
        var map = _asMap(res);
        var code = map?["code"];
        var msg = (map?["message"] ?? map?["msg"] ?? "").toString();
        tried.add("$url => code=$code $msg | ${_short(res)}");
        if (code == 0) {
          var now = DateTime.now();
          var hhmm =
              "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
          room.lastBeat.value = hhmm;
          var data = map?["data"];
          var interval = data is Map ? (data["heartbeat_interval"] ?? "") : "";
          room.lastResult.value =
              "心跳成功${interval == "" ? "" : "（间隔${interval}s）"}";
          _addLog(room.roomId, "心跳成功");
          return;
        }
      } catch (e) {
        tried.add("$url => 异常 $e");
      }
    }
    room.lastResult.value = "心跳失败（详见日志）";
    _addLog(room.roomId, "心跳失败: ${tried.join(" | ")}");
  }

  void _addLog(String room, String text) {
    logs.insert(0, IntimacyLog(DateTime.now(), room, text));
    if (logs.length > 80) {
      logs.removeRange(80, logs.length);
    }
    Log.d("亲密度挂机: [$room] $text");
  }

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }
}
