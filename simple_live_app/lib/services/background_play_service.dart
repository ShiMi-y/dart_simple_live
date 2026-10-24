import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:simple_live_app/app/log.dart';

/// 后台播放前台服务（仅 Android）
///
/// Android 12+ 中，没有前台服务的应用切到后台会被系统冻结，播放随之停止。
/// 播放开始/结束时通过该通道启动/停止 `mediaPlayback` 类型的前台服务。
class BackgroundPlayService {
  static const MethodChannel _channel =
      MethodChannel("simple_live/background_play");

  static bool _running = false;
  static bool _permissionAsked = false;

  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// 请求后台播放需要的系统权限（通知 + 忽略电池优化），每次运行只询问一次
  static Future<void> ensurePermissions({bool force = false}) async {
    if (!supported) {
      return;
    }
    if (_permissionAsked && !force) {
      return;
    }
    _permissionAsked = true;
    try {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
      if (await Permission.ignoreBatteryOptimizations.isDenied) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (e) {
      Log.logPrint("请求后台播放权限失败: $e");
    }
  }

  /// 打开系统应用设置（自启动 / 后台运行管理，vivo·iQOO 需手动允许）
  static Future<void> openSystemSettings() async {
    try {
      await openAppSettings();
    } catch (e) {
      Log.logPrint("打开系统设置失败: $e");
    }
  }

  /// 当前权限状态描述（用于设置页展示）
  static Future<String> permissionSummary() async {
    if (!supported) {
      return "仅 Android 需要";
    }
    try {
      var notification = await Permission.notification.status;
      var battery = await Permission.ignoreBatteryOptimizations.status;
      var n = notification.isGranted ? "已允许" : "未允许";
      var b = battery.isGranted ? "已允许" : "未允许";
      return "通知：$n ｜ 忽略电池优化：$b";
    } catch (e) {
      return "读取失败";
    }
  }

  /// 开始播放时调用（幂等）
  static Future<void> start() async {
    if (!supported || _running) {
      return;
    }
    try {
      await ensurePermissions();
      await _channel.invokeMethod("start");
      _running = true;
    } catch (e) {
      Log.logPrint("启动后台播放服务失败: $e");
    }
  }

  /// 暂停/停止播放时调用（幂等）
  static Future<void> stop() async {
    if (!supported || !_running) {
      return;
    }
    try {
      await _channel.invokeMethod("stop");
    } catch (e) {
      Log.logPrint("停止后台播放服务失败: $e");
    } finally {
      _running = false;
    }
  }
}
