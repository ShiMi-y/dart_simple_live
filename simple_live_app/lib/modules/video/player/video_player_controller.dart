import 'dart:async';
import 'dart:io';

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:simple_live_app/models/bilibili_video.dart';
import 'package:simple_live_app/services/bilibili_video_service.dart';
import 'package:window_manager/window_manager.dart';

/// 视频播放页参数
class VideoPlayerArguments {
  final String bvid;
  final String title;
  final BiliVideoPage page;
  final List<BiliVideoPage> pages;

  VideoPlayerArguments({
    required this.bvid,
    required this.title,
    required this.page,
    required this.pages,
  });
}

/// 哔哩哔哩视频播放（含弹幕）
class VideoPlayerController extends BaseController {
  late final VideoPlayerArguments args;
  late final Player player;
  late final VideoController videoController;

  final List<StreamSubscription> _subscriptions = [];

  var playing = false.obs;
  var buffering = true.obs;
  var position = Duration.zero.obs;
  var duration = Duration.zero.obs;
  var showDanmaku = true.obs;
  var danmakuCount = 0.obs;
  var danmakuLoading = false.obs;
  var qualityDesc = "自动".obs;
  var qualitys = <int, String>{}.obs;
  var fullscreen = false.obs;
  var showControls = true.obs;

  /// 视频播放器独立音量（0-100，与直播间音量互不影响）
  var volume = 100.0.obs;
  double _lastVolume = 100.0;

  /// 是否已登录哔哩哔哩（登录后可获取更高清晰度）
  bool get isLogin => BiliBiliVideoService.instance.isLogin;

  /// 弹幕控制器（由 DanmakuScreen 创建后回填）
  DanmakuController? danmakuController;

  List<BiliDanmaku> _danmakus = [];
  int _danmakuIndex = 0;
  Duration _lastPosition = Duration.zero;

  /// 弹幕样式沿用应用设置
  DanmakuOption get danmakuOption => DanmakuOption(
        fontSize: AppSettingsController.instance.danmuSize.value,
        area: AppSettingsController.instance.danmuArea.value,
        duration: AppSettingsController.instance.danmuSpeed.value.toInt(),
        opacity: AppSettingsController.instance.danmuOpacity.value,
        fontWeight: AppSettingsController.instance.danmuFontWeight.value,
      );

  @override
  void onInit() {
    super.onInit();
    args = Get.arguments as VideoPlayerArguments;
    player = Player(
      configuration: PlayerConfiguration(
        title: "Simple Live 视频",
        logLevel: AppSettingsController.instance.logEnable.value
            ? MPVLogLevel.info
            : MPVLogLevel.error,
      ),
    );
    videoController = VideoController(player);
    // 恢复上次的视频音量
    if (AppSettingsController.useSystemVolume) {
      // 移动端：音量交给系统媒体音量，mpv 固定 100 避免二次衰减
      player.setVolume(100);
      _refreshSystemVolume();
    } else {
      volume.value = AppSettingsController.instance.videoVolume.value;
      _lastVolume = volume.value <= 0 ? 100 : volume.value;
      player.setVolume(volume.value);
    }
    initDanmakuController = (e) {
      danmakuController = e;
    };
    _bindStreams();
    load();
  }

  /// 由页面传给 DanmakuScreen
  void Function(DanmakuController)? initDanmakuController;

  void _bindStreams() {
    _subscriptions.add(
      player.stream.playing.listen((e) => playing.value = e),
    );
    _subscriptions.add(
      player.stream.buffering.listen((e) => buffering.value = e),
    );
    _subscriptions.add(
      player.stream.duration.listen((e) => duration.value = e),
    );
    _subscriptions.add(
      player.stream.position.listen(_onPosition),
    );
    _subscriptions.add(
      player.stream.error.listen((e) {
        Log.logPrint("播放器错误: $e");
      }),
    );
  }

  /// 加载播放地址与弹幕
  Future<void> load() async {
    pageLoadding.value = true;
    pageError.value = false;
    try {
      var playUrl = await BiliBiliVideoService.instance.getPlayUrl(
        bvid: args.bvid,
        cid: args.page.cid,
      );
      qualityDesc.value = playUrl.qualityDesc;
      qualitys.assignAll(playUrl.acceptQuality);
      await player.open(
        Media(playUrl.url, httpHeaders: mediaHeaders),
        play: true,
      );
      await _loadDanmaku();
    } catch (e) {
      handleError(e, showPageError: true);
    } finally {
      pageLoadding.value = false;
    }
  }

  Future<void> _loadDanmaku() async {
    danmakuLoading.value = true;
    try {
      _danmakus = await BiliBiliVideoService.instance.getDanmaku(args.page.cid);
      _danmakuIndex = 0;
      danmakuCount.value = _danmakus.length;
    } catch (e) {
      Log.logPrint("加载弹幕失败: $e");
      _danmakus = [];
      danmakuCount.value = 0;
    } finally {
      danmakuLoading.value = false;
    }
  }

  void _onPosition(Duration pos) {
    position.value = pos;
    // 拖动/跳转后需要重新定位弹幕索引
    if ((pos - _lastPosition).inMilliseconds.abs() > 2000) {
      _danmakuIndex = _findIndex(pos);
    }
    _lastPosition = pos;
    _emitDanmaku(pos);
  }

  /// 找到第一个时间大于 [pos] 的弹幕下标
  int _findIndex(Duration pos) {
    var seconds = pos.inMilliseconds / 1000.0;
    var index = 0;
    while (index < _danmakus.length && _danmakus[index].time <= seconds) {
      index++;
    }
    return index;
  }

  /// 按播放进度推送弹幕
  void _emitDanmaku(Duration pos) {
    if (_danmakus.isEmpty ||
        !showDanmaku.value ||
        !playing.value ||
        danmakuController == null) {
      return;
    }
    var seconds = pos.inMilliseconds / 1000.0;
    var count = 0;
    while (_danmakuIndex < _danmakus.length &&
        _danmakus[_danmakuIndex].time <= seconds) {
      _addDanmaku(_danmakus[_danmakuIndex]);
      _danmakuIndex++;
      // 单次推送过多会卡顿（例如刚跳转后）
      if (++count >= 20) {
        break;
      }
    }
  }

  void _addDanmaku(BiliDanmaku danmaku) {
    var color = Color(0xFF000000 | (danmaku.color & 0xFFFFFF));
    var type = switch (danmaku.mode) {
      5 => DanmakuItemType.top,
      4 => DanmakuItemType.bottom,
      _ => DanmakuItemType.scroll,
    };
    danmakuController?.addDanmaku(
      DanmakuContentItem(danmaku.text, color: color, type: type),
    );
  }

  /// 跳转到指定进度（秒）
  void seekTo(double seconds) {
    var target = Duration(milliseconds: (seconds * 1000).round());
    danmakuController?.clear();
    _danmakuIndex = _findIndex(target);
    _lastPosition = target;
    position.value = target;
    player.seek(target);
  }

  void togglePlay() {
    player.playOrPause();
  }

  /// 调整视频音量（0-100），会记忆到设置
  /// 移动端：以系统媒体音量为准
  Future<void> _refreshSystemVolume() async {
    try {
      var v = await VolumeController.instance.getVolume();
      volume.value = (v * 100).clamp(0.0, 100.0);
      _lastVolume = volume.value <= 0 ? 100 : volume.value;
    } catch (_) {}
  }

  void setVolume(double value) {
    var v = value.clamp(0.0, 100.0);
    volume.value = v;
    if (v > 0) {
      _lastVolume = v;
    }
    if (AppSettingsController.useSystemVolume) {
      VolumeController.instance.setVolume(v / 100);
      player.setVolume(100);
      return;
    }
    player.setVolume(v);
    AppSettingsController.instance.setVideoVolume(v);
  }

  /// 静音 / 取消静音
  void toggleMute() {
    if (volume.value > 0) {
      _lastVolume = volume.value;
      volume.value = 0;
      player.setVolume(0);
      if (!AppSettingsController.useSystemVolume) {
        AppSettingsController.instance.setVideoVolume(0);
      }
    } else {
      var v = _lastVolume <= 0 ? 100.0 : _lastVolume;
      if (AppSettingsController.useSystemVolume) {
        volume.value = v;
        player.setVolume(100);
      } else {
        setVolume(v);
      }
    }
  }

  void toggleDanmaku() {
    showDanmaku.value = !showDanmaku.value;
    if (!showDanmaku.value) {
      danmakuController?.clear();
    } else {
      _danmakuIndex = _findIndex(position.value);
    }
  }

  void toggleControls() {
    showControls.value = !showControls.value;
  }

  /// 切换清晰度（保持当前进度）
  Future<void> changeQuality(int qn) async {
    var current = position.value;
    var wasPlaying = playing.value;
    pageLoadding.value = true;
    try {
      var playUrl = await BiliBiliVideoService.instance.getPlayUrl(
        bvid: args.bvid,
        cid: args.page.cid,
        qn: qn,
      );
      qualityDesc.value = playUrl.qualityDesc;
      qualitys.assignAll(playUrl.acceptQuality);
      danmakuController?.clear();
      _danmakuIndex = _findIndex(current);
      _lastPosition = current;
      await player.open(
        Media(playUrl.url, httpHeaders: mediaHeaders),
        play: wasPlaying,
      );
      await player.seek(current);
    } catch (e) {
      handleError(e);
    } finally {
      pageLoadding.value = false;
    }
  }

  /// 哔哩哔哩CDN会校验 Referer，缺失将返回403
  Map<String, String> get mediaHeaders => {
        "Referer": "https://www.bilibili.com",
        "User-Agent":
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
      };

  /// 桌面端全屏切换
  Future<void> toggleFullscreen() async {
    if (Platform.isAndroid || Platform.isIOS) {
      fullscreen.value = !fullscreen.value;
      return;
    }
    fullscreen.value = !fullscreen.value;
    await windowManager.setFullScreen(fullscreen.value);
  }

  @override
  void onClose() {
    for (var subscription in _subscriptions) {
      subscription.cancel();
    }
    danmakuController?.clear();
    player.dispose();
    if (fullscreen.value && !Platform.isAndroid && !Platform.isIOS) {
      windowManager.setFullScreen(false);
    }
    super.onClose();
  }
}
