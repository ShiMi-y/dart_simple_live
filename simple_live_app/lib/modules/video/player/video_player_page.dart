import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:simple_live_app/modules/video/player/video_player_controller.dart';

class VideoPlayerPage extends GetView<VideoPlayerController> {
  const VideoPlayerPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Scaffold(
        backgroundColor: Colors.black,
        appBar: controller.fullscreen.value
            ? null
            : AppBar(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                title: Text(
                  _title(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15),
                ),
              ),
        body: _buildBody(context),
      ),
    );
  }

  String _title() {
    var page = controller.args.page;
    var pages = controller.args.pages;
    if (pages.length > 1) {
      return "${controller.args.title} - P${page.page} ${page.part}";
    }
    return controller.args.title;
  }

  Widget _buildBody(BuildContext context) {
    if (controller.pageError.value) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white54, size: 48),
            const SizedBox(height: 12),
            Text(
              controller.errorMsg.value,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: controller.load,
              child: const Text("重试"),
            ),
          ],
        ),
      );
    }
    return Center(
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Video(
              controller: controller.videoController,
              fit: BoxFit.contain,
              controls: NoVideoControls,
            ),
            // 弹幕层
            Obx(
              () => Offstage(
                offstage: !controller.showDanmaku.value,
                child: DanmakuScreen(
                  createdController: (c) {
                    controller.initDanmakuController?.call(c);
                  },
                  option: controller.danmakuOption,
                ),
              ),
            ),
            // 点击切换控制栏
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: controller.toggleControls,
                child: const SizedBox.expand(),
              ),
            ),
            // 加载中
            Obx(
              () => (controller.pageLoadding.value || controller.buffering.value)
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : const SizedBox.shrink(),
            ),
            // 控制栏
            Obx(
              () => AnimatedOpacity(
                opacity: controller.showControls.value ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !controller.showControls.value,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: _buildControls(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 20, 8, 4),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black87],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: controller.togglePlay,
                icon: Icon(
                  controller.playing.value ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
              ),
              Text(
                _formatTime(controller.position.value),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              Expanded(
                child: Obx(
                  () {
                    var total = controller.duration.value.inMilliseconds;
                    var current = controller.position.value.inMilliseconds;
                    if (current > total) {
                      current = total;
                    }
                    return SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 12,
                        ),
                      ),
                      child: Slider(
                        min: 0,
                        max: total <= 0 ? 1 : total.toDouble(),
                        value: current.toDouble(),
                        onChanged: (v) => controller.seekTo(v / 1000),
                      ),
                    );
                  },
                ),
              ),
              Text(
                _formatTime(controller.duration.value),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: "弹幕开关",
                onPressed: controller.toggleDanmaku,
                icon: Icon(
                  controller.showDanmaku.value
                      ? Icons.subtitles
                      : Icons.subtitles_off,
                  color: controller.showDanmaku.value
                      ? Colors.white
                      : Colors.white38,
                ),
              ),
              if (controller.qualitys.isNotEmpty)
                PopupMenuButton<int>(
                  tooltip: "清晰度",
                  onSelected: controller.changeQuality,
                  itemBuilder: (_) => controller.qualitys.entries
                      .map(
                        (e) => PopupMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      controller.qualityDesc.value,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              IconButton(
                tooltip: "全屏",
                onPressed: controller.toggleFullscreen,
                icon: Icon(
                  controller.fullscreen.value
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          Row(
            children: [
              const SizedBox(width: 8),
              const Icon(Icons.comment, color: Colors.white38, size: 13),
              const SizedBox(width: 4),
              Text(
                "${controller.danmakuCount.value} 条弹幕",
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const Spacer(),
              if (controller.args.pages.length > 1)
                PopupMenuButton<int>(
                  tooltip: "分P",
                  onSelected: (index) {
                    var page = controller.args.pages[index];
                    var args = VideoPlayerArguments(
                      bvid: controller.args.bvid,
                      title: controller.args.title,
                      page: page,
                      pages: controller.args.pages,
                    );
                    Get.offNamed(Get.currentRoute, arguments: args);
                  },
                  itemBuilder: (_) => controller.args.pages
                      .asMap()
                      .entries
                      .map(
                        (e) => PopupMenuItem(
                          value: e.key,
                          child: Text(
                            "P${e.value.page} ${e.value.part}",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      "P${controller.args.page.page}",
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ),
              const SizedBox(width: 8),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(Duration duration) {
    var hours = duration.inHours;
    var minutes = duration.inMinutes.remainder(60);
    var seconds = duration.inSeconds.remainder(60);
    String two(int v) => v.toString().padLeft(2, "0");
    return hours > 0
        ? "${two(hours)}:${two(minutes)}:${two(seconds)}"
        : "${two(minutes)}:${two(seconds)}";
  }
}
