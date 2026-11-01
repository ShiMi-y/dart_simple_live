import 'dart:async';
import 'package:simple_live_app/app/instance.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';

import 'package:get/get.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/requests/http_client.dart';
import 'package:simple_live_app/services/background_play_service.dart';
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
class Endpoints {
  static const String web =
      "https://api.live.bilibili.com/x/report/click/web/heartbeat";
  static const String legacy =
      "https://api.live.bilibili.com/x/report/click/heartbeat";
}

class IntimacyService extends GetxService {
  static IntimacyService get instance => Get.find<IntimacyService>();

  static const String _roomsKey = "IntimacyRooms";
  static const String _enabledKey = "IntimacyEnabled";
  static const String _ua =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";

  final RxBool enabled = false.obs;

  /// 连续失败达到上限后暂停（需手动重试或重启应用）
  final RxBool suspended = false.obs;
  int _consecutiveFailures = 0;
  static const int maxConsecutiveFailures = 5;
  final RxList<IntimacyRoom> rooms = <IntimacyRoom>[].obs;
  final RxList<IntimacyLog> logs = <IntimacyLog>[].obs;

  Timer? _timer;
  bool _ticking = false;

  File? _sharedFile;
  Timer? _syncTimer;

  /// 只有主实例（实例1）真正执行挂机
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

      // 旧版本配置（实例私有）迁移到共享文件
      await _migrateLegacyConfig();

      // 所有实例都轮询共享配置：实例1负责执行，其它实例仅显示最新状态
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
        var ids = rawRooms.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
        // 同步本地房间对象（保留已有状态，新增的补上）
        for (var id in ids) {
          if (!rooms.any((e) => e.roomId == id)) {
            rooms.add(IntimacyRoom(id));
          }
        }
        rooms.removeWhere((e) => !ids.contains(e.roomId));
      }
      // 状态同步：主实例按配置起停，其它实例不执行
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
      var enabledLegacy =
          LocalStorageService.instance.getValue(_enabledKey, false) == true;
      if (saved.isEmpty && !enabledLegacy) {
        return;
      }
      enabled.value = enabledLegacy;
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

  /// 直接按房间号添加（用于「添加本直播间」，无需输入）
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
    if (rooms.any((e) => e.roomId == id)) {
      return false;
    }
    rooms.add(IntimacyRoom(id));
    await _saveShared();
    // 立刻检查一次
    _checkRoom(rooms.last);
    return true;
  }

  Future<void> removeRoom(String roomId) async {
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

  /// 手动重试（清除失败计数并立即执行一次）
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
    _stopTimerOnly();
    _addLog("-", "已停止挂机");
  }

  Future<void> _tick() async {
    if (!isOwner) {
      return;
    }
    if (suspended.value) {
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

  /// 心跳接口对 Cookie 敏感：带 bili_jct 会命中 B 站 CDN 保护（404 WebProxyNeedLess），
  /// 因此请求头里剔除 bili_jct，csrf 仍作为参数传递。
  String _filterCookie(String cookie) {
    var parts = <String>[];
    for (var part in cookie.split(";")) {
      var kv = part.trim();
      if (kv.isEmpty) {
        continue;
      }
      var idx = kv.indexOf("=");
      if (idx <= 0) {
        continue;
      }
      var key = kv.substring(0, idx).trim();
      if (key == "bili_jct") {
        continue;
      }
      parts.add(kv);
    }
    return parts.join("; ");
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

  /// 校验登录态（顺带记录原因，便于日志定位）
  Future<bool> _checkLogin() async {
    try {
      var cookie = BiliBiliAccountService.instance.cookie;
      if (cookie.isEmpty) {
        return false;
      }
      var res = await HttpClient.instance.getJson(
        "https://api.bilibili.com/x/web-interface/nav",
        header: {"Cookie": cookie, "User-Agent": _ua},
      );
      var map = _asMap(res);
      var data = map?["data"];
      if (map?["code"] == 0 && data is Map && data["isLogin"] == true) {
        return true;
      }
      _addLog("-", "登录态无效（nav code=${map?["code"]}），请重新登录哔哩哔哩");
      return false;
    } catch (e) {
      _addLog("-", "登录态校验失败: $e");
      return false;
    }
  }

  Future<void> _sendHeartbeat(IntimacyRoom room) async {
    var cookie = BiliBiliAccountService.instance.cookie;
    if (cookie.isEmpty) {
      room.lastResult.value = "未登录";
      return;
    }
    if (!await _checkLogin()) {
      room.lastResult.value = "登录失效";
      return;
    }
    var csrf = _cookieValue(cookie, "bili_jct");
    var uid = BiliBiliAccountService.instance.uid.toString();
    var form = {
      "room_id": room.roomId,
      "uid": uid,
      "csrf": csrf,
      "csrf_token": csrf,
      "platform": "web",
      "visit_id": "",
    };
    var query = {"room_id": room.roomId, "csrf": csrf};

    // 三种组合依次尝试：csrf 校验需要 cookie 里的 bili_jct，
    // 但部分 CDN 节点对带 bili_jct 的请求会返回 404 WebProxyNeedLess
    var attempts = <Map<String, dynamic>>[
      {"name": "完整Cookie+csrf", "url": Endpoints.web, "cookie": cookie, "csrf": true},
      {
        "name": "无bili_jct+csrf",
        "url": Endpoints.web,
        "cookie": _filterCookie(cookie),
        "csrf": true
      },
      {
        "name": "无bili_jct+无csrf",
        "url": Endpoints.web,
        "cookie": _filterCookie(cookie),
        "csrf": false
      },
      {
        "name": "旧接口+csrf",
        "url": Endpoints.legacy,
        "cookie": cookie,
        "csrf": true
      },
    ];

    var tried = <String>[];
    for (var attempt in attempts) {
      var useCsrf = attempt["csrf"] == true;
      try {
        var res = await HttpClient.instance.postJson(
          attempt["url"] as String,
          queryParameters: useCsrf ? query : {"room_id": room.roomId},
          data: useCsrf
              ? form
              : {
                  "room_id": room.roomId,
                  "uid": uid,
                  "platform": "web",
                  "visit_id": "",
                },
          header: {
            "Cookie": attempt["cookie"] as String,
            "User-Agent": _ua,
            "Referer": "https://live.bilibili.com/${room.roomId}",
            "Origin": "https://live.bilibili.com",
          },
          formUrlEncoded: true,
        );
        var map = _asMap(res);
        var code = map?["code"];
        if (code == 0) {
          var now = DateTime.now();
          var hhmm =
              "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
          room.lastBeat.value = hhmm;
          var data = map?["data"];
          var interval = data is Map ? (data["heartbeat_interval"] ?? "") : "";
          room.lastResult.value =
              "心跳成功${interval == "" ? "" : "（间隔${interval}s）"}";
          _consecutiveFailures = 0;
          suspended.value = false;
          _addLog(room.roomId, "心跳成功（${attempt["name"]}）");
          return;
        }
        tried.add("${attempt["name"]} => code=$code");
      } catch (e) {
        tried.add("${attempt["name"]} => 异常 $e");
      }
    }
    room.lastResult.value = "心跳失败（详见日志）";
    _consecutiveFailures++;
    _addLog(
      room.roomId,
      "心跳失败(连续$_consecutiveFailures次): ${tried.join(" | ")}",
    );
    if (_consecutiveFailures >= maxConsecutiveFailures) {
      suspended.value = true;
      _stopTimerOnly();
      _addLog(
        "-",
        "连续失败$maxConsecutiveFailures次，已暂停挂机；请检查登录态后点「重试」，或重启应用",
      );
    }
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
    _syncTimer?.cancel();
    _timer?.cancel();
    super.onClose();
  }
}
