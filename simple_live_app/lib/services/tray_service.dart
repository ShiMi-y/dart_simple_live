import 'dart:io';

import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:simple_live_app/app/log.dart';
// tray_manager 0.7 起主 API 迁移到 nativeapi，这里沿用兼容层（用法稳定、行为一致）
// ignore_for_file: deprecated_member_use
import 'package:tray_manager/legacy.dart';
import 'package:window_manager/window_manager.dart';

/// 系统托盘（最小化到托盘后继续在后台运行，接收开播提醒）
class TrayService extends GetxService {
  static TrayService get instance => Get.find<TrayService>();

  bool _inited = false;

  bool get available => _inited;

  Future<TrayService> init() async {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      return this;
    }
    try {
      // tray_manager 需要图标文件路径，先把打包的 ico 释放到临时目录
      var iconData = await rootBundle.load("assets/icons/app_icon.ico");
      var dir = await getTemporaryDirectory();
      var iconFile = File(p.join(dir.path, "simple_live_tray.ico"));
      await iconFile.writeAsBytes(
        iconData.buffer.asUint8List(),
        flush: true,
      );
      await trayManager.setIcon(iconFile.path);
      await trayManager.setToolTip("Simple Live");
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: "show", label: "显示主窗口"),
            MenuItem.separator(),
            MenuItem(key: "exit", label: "退出"),
          ],
        ),
      );
      trayManager.addListener(_TrayListener());
      _inited = true;
      Log.d("系统托盘初始化完成");
    } catch (e) {
      Log.logPrint("系统托盘初始化失败: $e");
    }
    return this;
  }

  /// 隐藏到托盘
  Future<void> hideToTray() async {
    try {
      await windowManager.hide();
    } catch (e) {
      Log.logPrint("隐藏到托盘失败: $e");
    }
  }

  /// 从托盘恢复窗口
  Future<void> showWindow() async {
    try {
      await windowManager.show();
      await windowManager.focus();
      // 部分情况下需要先 unminimize 才能真正显示
      if (await windowManager.isMinimized()) {
        await windowManager.restore();
      }
    } catch (e) {
      Log.logPrint("显示主窗口失败: $e");
    }
  }

  /// 退出应用
  Future<void> exitApp() async {
    try {
      await trayManager.destroy();
    } catch (e) {
      Log.logPrint("销毁托盘失败: $e");
    }
    exit(0);
  }
}

class _TrayListener extends TrayListener {
  @override
  void onTrayIconMouseDown() {
    TrayService.instance.showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == "show") {
      TrayService.instance.showWindow();
    } else if (menuItem.key == "exit") {
      TrayService.instance.exitApp();
    }
  }
}
