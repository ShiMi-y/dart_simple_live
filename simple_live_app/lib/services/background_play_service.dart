import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:simple_live_app/app/log.dart';

/// 后台播放前台服务（仅 Android）
///
/// Android 12+ 中，没有前台服务的应用切到后台会被系统冻结，播放随之停止。
/// 播放开始/结束时通过该通道启动/停止 `mediaPlayback` 类型的前台服务。
class BackgroundPlayService {
  static const MethodChannel _channel =
      MethodChannel("simple_live/background_play");

  static bool _running = false;

  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// 开始播放时调用（幂等）
  static Future<void> start() async {
    if (!supported || _running) {
      return;
    }
    try {
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
