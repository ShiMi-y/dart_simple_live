import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:volume_controller/volume_controller.dart';

/// 音频诊断：收集「无声」类问题需要的全部现场信息，可一键导出/分享
///
/// 采集内容：
/// - 设备信息（型号 / Android 版本 / ABI）与 App 版本
/// - 播放相关设置（自定义驱动、音频/视频驱动、硬解、兼容模式、音量）
/// - 系统媒体音量
/// - mpv 实际属性（ao、audio-out-params、audio-device-list、volume、mute、codec）
/// - 内存事件时间线（驱动链、AudioParams、切换驱动、10 秒无音频告警）
/// - 最近日志文件尾部（含 mpv 的 PlayerLog）
class AudioDiagService extends GetxService {
  static AudioDiagService get instance => Get.find<AudioDiagService>();

  static const int _maxEvents = 300;

  final List<String> _events = [];

  /// 记录一条诊断事件（带时间戳，内存中保留最近 300 条）
  void addEvent(String message) {
    try {
      var now = DateTime.now();
      var ts = "${now.hour.toString().padLeft(2, '0')}:"
          "${now.minute.toString().padLeft(2, '0')}:"
          "${now.second.toString().padLeft(2, '0')}";
      _events.add("[$ts] $message");
      if (_events.length > _maxEvents) {
        _events.removeRange(0, _events.length - _maxEvents);
      }
      Log.d("音频诊断: $message");
    } catch (_) {}
  }

  /// 采集播放器当前状态
  Future<void> capturePlayer(Player player, {String room = ""}) async {
    try {
      var native = player.platform;
      if (native is! NativePlayer) {
        addEvent("capturePlayer: platform 不是 NativePlayer(${native.runtimeType})");
        return;
      }
      Future<String> prop(String name) async {
        try {
          return await native.getProperty(name, waitForInitialization: false);
        } catch (e) {
          return "<读取失败:$e>";
        }
      }

      if (room.isNotEmpty) {
        addEvent("房间: $room");
      }
      addEvent("mpv ao = ${await prop('ao')}");
      addEvent("mpv audio-out-params = ${await prop('audio-out-params')}");
      addEvent("mpv audio-codec-name = ${await prop('audio-codec-name')}");
      addEvent("mpv volume = ${await prop('volume')} / mute = ${await prop('mute')}");
      addEvent("mpv audio-device-list = ${await prop('audio-device-list')}");
      var audioParams = player.state.audioParams;
      addEvent(
        "PlayerState.audioParams = ${audioParams.sampleRate}Hz/"
        "${audioParams.channelCount}ch/${audioParams.format}",
      );
    } catch (e) {
      addEvent("capturePlayer 失败: $e");
    }
  }

  Future<String> _deviceInfo() async {
    var buffer = StringBuffer();
    try {
      buffer.writeln("Platform: ${Platform.operatingSystem} ${Platform.version}");
      if (!kIsWeb && Platform.isAndroid) {
        var info = await DeviceInfoPlugin().androidInfo;
        buffer.writeln("Device: ${info.manufacturer} ${info.model}");
        buffer.writeln(
          "Android: ${info.version.release} (SDK ${info.version.sdkInt})",
        );
        buffer.writeln("ABI: ${info.supportedAbis.join(",")}");
        buffer.writeln("Fingerprint: ${info.fingerprint}");
      }
    } catch (e) {
      buffer.writeln("设备信息读取失败: $e");
    }
    return buffer.toString();
  }

  String _settingsSnapshot() {
    var s = AppSettingsController.instance;
    return '''
customPlayerOutput = ${s.customPlayerOutput.value}
audioOutputDriver = ${s.audioOutputDriver.value}
videoOutputDriver = ${s.videoOutputDriver.value}
videoHardwareDecoder = ${s.videoHardwareDecoder.value}
hardwareDecode = ${s.hardwareDecode.value}
playerCompatMode = ${s.playerCompatMode.value}
playerVolume = ${s.playerVolume.value}
videoVolume = ${s.videoVolume.value}
qualityLevel = ${s.qualityLevel.value}
logEnable = ${s.logEnable.value}
''';
  }

  Future<String> _systemVolume() async {
    try {
      var v = await VolumeController.instance.getVolume();
      return (v * 100).toStringAsFixed(0);
    } catch (e) {
      return "读取失败:$e";
    }
  }

  /// 取最近日志文件尾部
  Future<String> _logTail({int maxLines = 250}) async {
    try {
      var support = await getApplicationSupportDirectory();
      var dir = Directory(p.join(support.path, "log"));
      if (!await dir.exists()) {
        return "<无日志目录>";
      }
      var files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith(".log"))
          .toList()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      if (files.isEmpty) {
        return "<无日志文件>";
      }
      var lines = await files.first.readAsLines();
      var tail = lines.length > maxLines
          ? lines.sublist(lines.length - maxLines)
          : lines;
      return "文件: ${p.basename(files.first.path)} (共${lines.length}行)\n"
          "${tail.join("\n")}";
    } catch (e) {
      return "<读取日志失败:$e>";
    }
  }

  /// 生成完整诊断报告
  Future<String> buildReport() async {
    var buffer = StringBuffer();
    buffer.writeln("========== Simple Live 音频诊断报告 ==========");
    buffer.writeln("生成时间: ${DateTime.now()}");
    buffer.writeln(await _deviceInfo());
    buffer.writeln("---------- 播放设置 ----------");
    buffer.writeln(_settingsSnapshot());
    buffer.writeln("---------- 系统音量 ----------");
    buffer.writeln("系统媒体音量: ${await _systemVolume()} / 100");
    buffer.writeln("---------- 事件时间线 ----------");
    if (_events.isEmpty) {
      buffer.writeln("<无事件：本次运行还未进入过直播间>");
    } else {
      buffer.writeln(_events.join("\n"));
    }
    buffer.writeln("---------- 日志尾部 ----------");
    buffer.writeln(await _logTail());
    buffer.writeln("========== 报告结束 ==========");
    return buffer.toString();
  }

  /// 导出到文件并调起系统分享
  Future<void> shareReport() async {
    try {
      var report = await buildReport();
      var support = await getApplicationSupportDirectory();
      var dir = Directory(p.join(support.path, "diag"));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      var ts = DateTime.now()
          .toIso8601String()
          .replaceAll(":", "-")
          .replaceAll(".", "-");
      var file = File(p.join(dir.path, "audio_diag_$ts.txt"));
      await file.writeAsString(report, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: "text/plain")],
          subject: "Simple Live 音频诊断",
        ),
      );
    } catch (e) {
      Log.logPrint("导出音频诊断失败: $e");
    }
  }
}
