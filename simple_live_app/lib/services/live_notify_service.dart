import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:window_manager/window_manager.dart';

/// 关注主播开播提醒（桌面端系统通知）
///
/// 数据存 Hive box `LiveNotify`：`siteId_roomId` -> 是否开启提醒。
/// 由 [FollowService] 每次刷新关注状态时驱动：
/// 只有识别到「未开播 → 直播中」的跳变才通知，首次拿到状态（启动）不通知。
class LiveNotifyService extends GetxService {
  static LiveNotifyService get instance => Get.find<LiveNotifyService>();

  static const String _boxName = "LiveNotify";

  Box? _box;

  /// 系统通知是否可用（仅桌面端且初始化成功）
  bool _ready = false;

  bool get supportSystemNotify => _ready;

  /// 已开启提醒的主播（id = siteId_roomId），用于界面响应式刷新
  var enabledIds = <String>[].obs;

  /// 上一轮的直播状态，用于识别跳变
  final Map<String, bool> _lastStatus = {};

  Future<LiveNotifyService> init() async {
    try {
      _box = await Hive.openBox(_boxName);
      enabledIds.assignAll(
        _box!.keys
            .where((e) => _box!.get(e) == true)
            .map((e) => e.toString())
            .toList(),
      );
    } catch (e) {
      Log.logPrint("开播提醒数据初始化失败: $e");
    }
    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      try {
        await localNotifier.setup(appName: "Simple Live");
        _ready = true;
      } catch (e) {
        Log.logPrint("系统通知初始化失败: $e");
      }
    }
    return this;
  }

  bool isEnabled(String id) => enabledIds.contains(id);

  /// 整体替换（用于 WebDAV/同步恢复）
  Future<void> replaceAll(Iterable<String> ids) async {
    try {
      await _box?.clear();
      var list = ids.toList();
      for (var id in list) {
        await _box?.put(id, true);
      }
      enabledIds.assignAll(list);
    } catch (e) {
      Log.logPrint("恢复开播提醒设置失败: $e");
    }
  }

  Future<void> setEnabled(String id, bool value) async {
    try {
      if (value) {
        if (!enabledIds.contains(id)) {
          enabledIds.add(id);
        }
        await _box?.put(id, true);
      } else {
        enabledIds.remove(id);
        await _box?.delete(id);
      }
    } catch (e) {
      Log.logPrint("保存开播提醒设置失败: $e");
    }
  }

  /// 关注状态刷新时调用（由 FollowService 驱动）
  void onLiveStatusUpdated(FollowUser user, bool isLiving) {
    var prev = _lastStatus[user.id];
    _lastStatus[user.id] = isLiving;
    // 首次拿到状态不通知，避免启动瞬间把「已开播」当成刚开播
    if (prev == null) {
      return;
    }
    if (prev || !isLiving) {
      return;
    }
    if (!AppSettingsController.instance.liveNotifyEnable.value) {
      return;
    }
    if (!isEnabled(user.id)) {
      return;
    }
    notifyLive(user);
  }

  /// 发送开播通知
  Future<void> notifyLive(FollowUser user) async {
    if (!_ready) {
      Log.d("系统通知不可用，跳过开播提醒: ${user.userName}");
      return;
    }
    try {
      var notification = LocalNotification(
        identifier: "live_${user.id}",
        title: "${user.userName} 开播了",
        body: "点击打开直播间",
      );
      notification.onClick = () {
        _openRoom(user);
      };
      await localNotifier.notify(notification);
      Log.d("已发送开播提醒: ${user.userName}");
    } catch (e) {
      Log.logPrint("发送开播提醒失败: $e");
    }
  }

  /// 点击通知：显示窗口并打开对应直播间
  Future<void> _openRoom(FollowUser user) async {
    try {
      if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
        await windowManager.show();
        await windowManager.focus();
      }
      var site = Sites.allSites[user.siteId];
      if (site == null) {
        return;
      }
      AppNavigator.toLiveRoomDetail(site: site, roomId: user.roomId);
    } catch (e) {
      Log.logPrint("打开开播直播间失败: $e");
    }
  }
}
