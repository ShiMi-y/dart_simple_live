import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/models/bilibili_video.dart';
import 'package:simple_live_app/modules/video/video_controller.dart';
import 'package:simple_live_app/widgets/net_image.dart';

class VideoPage extends GetView<VideoController> {
  const VideoPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("视频播放（AV/BV）")),
      body: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: [
          _buildInput(context),
          AppStyle.vGap12,
          Obx(
            () {
              if (controller.pageLoadding.value) {
                return const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (controller.pageError.value) {
                return Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.grey),
                        AppStyle.vGap12,
                        Text(
                          controller.errorMsg.value,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                );
              }
              var info = controller.info.value;
              if (info == null) {
                return const SizedBox.shrink();
              }
              return _buildResult(context, info);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInput(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).cardColor,
      child: Padding(
        padding: AppStyle.edgeInsetsA12,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller.inputController,
              textInputAction: TextInputAction.go,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: "输入 BV 号 / AV 号 / 视频链接",
                helperText: "例如：BV1xx411c7mD、av170001，或视频页面链接",
                contentPadding: AppStyle.edgeInsetsA12,
                prefixIcon: Icon(Remix.play_circle_line),
              ),
              onSubmitted: (text) => controller.parse(text),
            ),
            AppStyle.vGap12,
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => controller.parse(),
                icon: const Icon(Remix.search_line),
                label: const Text("解析并播放"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(BuildContext context, BiliVideoInfo info) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          elevation: 0,
          color: Theme.of(context).cardColor,
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: AppStyle.edgeInsetsA12,
                    child: NetImage(
                      info.cover,
                      width: 140,
                      height: 88,
                      borderRadius: 8,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: AppStyle.edgeInsetsA12.copyWith(left: 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            info.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Get.textTheme.titleSmall,
                          ),
                          AppStyle.vGap4,
                          Text(
                            "${info.ownerName} · ${_formatDuration(info.duration)}",
                            style: Get.textTheme.bodySmall
                                ?.copyWith(color: Colors.grey),
                          ),
                          AppStyle.vGap4,
                          Text(
                            "${info.bvid} · av${info.aid}",
                            style: Get.textTheme.bodySmall
                                ?.copyWith(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (info.desc.toString().trim().isNotEmpty)
                Padding(
                  padding: AppStyle.edgeInsetsA12.copyWith(top: 0),
                  child: Text(
                    info.desc,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Get.textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                ),
            ],
          ),
        ),
        AppStyle.vGap12,
        if (info.pages.length > 1)
          Padding(
            padding: AppStyle.edgeInsetsH4,
            child: Text(
              "分P（共${info.pages.length}P，点击播放）",
              style: Get.textTheme.titleSmall,
            ),
          ),
        AppStyle.vGap8,
        Card(
          elevation: 0,
          color: Theme.of(context).cardColor,
          child: Column(
            children: [
              for (var page in info.pages)
                ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: Colors.grey.withAlpha(40),
                    child: Text(
                      "${page.page}",
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  title: Text(
                    page.part,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(_formatDuration(page.duration)),
                  trailing: const Icon(Remix.play_circle_line),
                  onTap: () => controller.playPage(page),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDuration(int seconds) {
    var duration = Duration(seconds: seconds);
    var hours = duration.inHours;
    var minutes = duration.inMinutes.remainder(60);
    var secs = duration.inSeconds.remainder(60);
    String two(int v) => v.toString().padLeft(2, "0");
    return hours > 0
        ? "${two(hours)}:${two(minutes)}:${two(secs)}"
        : "${two(minutes)}:${two(secs)}";
  }
}
