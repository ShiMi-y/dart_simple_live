import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/models/bilibili_video.dart';
import 'package:simple_live_app/modules/video/player/video_player_controller.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/services/bilibili_video_service.dart';

class VideoController extends BaseController {
  final TextEditingController inputController = TextEditingController();

  /// 解析到的视频信息
  var info = Rxn<BiliVideoInfo>();

  /// 正在解析
  var parsing = false.obs;

  void parse([String? text]) async {
    var input = (text ?? inputController.text).trim();
    if (input.isEmpty) {
      SmartDialog.showToast("请输入 AV/BV 号");
      return;
    }
    parsing.value = true;
    pageError.value = false;
    loadding = true;
    try {
      var result = await BiliBiliVideoService.instance.getVideoInfo(input);
      info.value = result;
    } catch (e) {
      info.value = null;
      handleError(e, showPageError: true);
    } finally {
      parsing.value = false;
      loadding = false;
    }
  }

  void playPage(BiliVideoPage page) {
    var video = info.value;
    if (video == null) {
      return;
    }
    Get.toNamed(
      RoutePath.kVideoPlayer,
      arguments: VideoPlayerArguments(
        bvid: video.bvid,
        title: video.title,
        page: page,
        pages: video.pages,
      ),
    );
  }

  @override
  void onClose() {
    inputController.dispose();
    super.onClose();
  }
}
