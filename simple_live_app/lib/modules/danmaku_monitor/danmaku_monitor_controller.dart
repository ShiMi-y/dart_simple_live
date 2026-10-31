import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// 被监控的房间
class MonitorRoom {
  final String roomId;
  final String title;
  final String userName;
  final String face;

  /// 连接状态
  final RxBool connected = false.obs;

  /// 收到消息数
  final RxInt messageCount = 0.obs;

  /// 房间主题色（用于列表左侧色条）
  final Color color;

  LiveDanmaku? danmaku;

  MonitorRoom({
    required this.roomId,
    required this.title,
    required this.userName,
    required this.face,
    required this.color,
  });
}

/// 会话内的弹幕条目
class MonitorMessage {
  final String roomTitle;
  final Color color;
  final String userName;
  final String text;
  final DateTime time;

  MonitorMessage({
    required this.roomTitle,
    required this.color,
    required this.userName,
    required this.text,
    required this.time,
  });
}

/// 多房间弹幕监控（哔哩哔哩）
class DanmakuMonitorController extends BaseController {
  static const String _roomIdsKey = "DanmakuMonitorRooms";
  static const int _maxMessages = 800;

  final RxList<MonitorRoom> rooms = <MonitorRoom>[].obs;
  final RxList<MonitorMessage> messages = <MonitorMessage>[].obs;
  final RxBool autoScroll = true.obs;
  final ScrollController scrollController = ScrollController();

  /// 房间配色（循环使用）
  static const List<Color> _palette = [
    Color(0xFF4C8DFF),
    Color(0xFF00B578),
    Color(0xFFFF8A3D),
    Color(0xFFB36BFF),
    Color(0xFFFF5D7D),
    Color(0xFF00B8D9),
  ];

  @override
  void onInit() {
    super.onInit();
    restoreRooms();
  }

  /// 恢复上次监控的房间
  Future<void> restoreRooms() async {
    try {
      var saved = LocalStorageService.instance
          .getValue(_roomIdsKey, "")
          .toString();
      if (saved.isEmpty) {
        return;
      }
      for (var id in saved.split(",")) {
        var roomId = id.trim();
        if (roomId.isEmpty) {
          continue;
        }
        await addRoom(roomId, persist: false);
      }
    } catch (e) {
      Log.logPrint("恢复弹幕监控房间失败: $e");
    }
  }

  Future<void> _persistRooms() async {
    try {
      await LocalStorageService.instance.setValue(
        _roomIdsKey,
        rooms.map((e) => e.roomId).join(","),
      );
    } catch (e) {
      Log.logPrint("保存弹幕监控房间失败: $e");
    }
  }

  /// 从输入中解析房间号（支持纯数字、直播间链接）
  String? parseRoomId(String input) {
    var text = input.trim();
    if (text.isEmpty) {
      return null;
    }
    var linkMatch = RegExp(r"live\.bilibili\.com/(\d+)").firstMatch(text);
    if (linkMatch != null) {
      return linkMatch.group(1);
    }
    if (RegExp(r"^\d+$").hasMatch(text)) {
      return text;
    }
    return null;
  }

  /// 添加房间并开始接收弹幕
  Future<bool> addRoom(String input, {bool persist = true}) async {
    var roomId = parseRoomId(input);
    if (roomId == null) {
      SmartDialog.showToast("请输入正确的哔哩哔哩房间号或直播间链接");
      return false;
    }
    if (rooms.any((e) => e.roomId == roomId)) {
      SmartDialog.showToast("该房间已在监控列表中");
      return false;
    }
    try {
      var site = Sites.allSites["bilibili"];
      if (site == null) {
        SmartDialog.showToast("未找到哔哩哔哩站点");
        return false;
      }
      pageLoadding.value = true;
      var detail = await site.liveSite.getRoomDetail(roomId: roomId);
      var room = MonitorRoom(
        roomId: roomId,
        title: detail.title.isEmpty ? "房间$roomId" : detail.title,
        userName: detail.userName,
        face: detail.userAvatar,
        color: _palette[rooms.length % _palette.length],
      );
      var danmaku = site.liveSite.getDanmaku();
      danmaku.onMessage = (msg) => _onMessage(room, msg);
      danmaku.onReady = () => room.connected.value = true;
      danmaku.onClose = (msg) => room.connected.value = false;
      room.danmaku = danmaku;
      await danmaku.start(detail.danmakuData);
      rooms.add(room);
      if (persist) {
        await _persistRooms();
      }
      return true;
    } catch (e) {
      Log.logPrint("添加监控房间失败: $e");
      SmartDialog.showToast("添加失败：$e");
      return false;
    } finally {
      pageLoadding.value = false;
    }
  }

  void _onMessage(MonitorRoom room, LiveMessage msg) {
    if (msg.type != LiveMessageType.chat) {
      return;
    }
    room.messageCount.value++;
    var text = msg.message.trim();
    if (text.isEmpty) {
      return;
    }
    messages.add(
      MonitorMessage(
        roomTitle: room.title,
        color: room.color,
        userName: msg.userName,
        text: text,
        time: DateTime.now(),
      ),
    );
    if (messages.length > _maxMessages) {
      messages.removeRange(0, messages.length - _maxMessages);
    }
    if (autoScroll.value) {
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) {
        return;
      }
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
    });
  }

  /// 移除房间
  Future<void> removeRoom(MonitorRoom room) async {
    try {
      await room.danmaku?.stop();
    } catch (e) {
      Log.logPrint("停止监控房间失败: $e");
    }
    rooms.remove(room);
    await _persistRooms();
  }

  void clearMessages() {
    messages.clear();
  }

  @override
  void onClose() {
    for (var room in rooms) {
      try {
        room.danmaku?.stop();
      } catch (_) {}
    }
    scrollController.dispose();
    super.onClose();
  }
}
