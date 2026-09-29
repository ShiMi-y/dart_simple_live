import 'dart:async';

import 'package:flutter/material.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/widgets/net_image.dart';
import 'package:simple_live_core/simple_live_core.dart';

class SuperChatCard extends StatefulWidget {
  final LiveSuperChatMessage message;
  final Function()? onExpire;
  final int? customCountdown;

  /// 常驻模式：倒计时结束后不触发onExpire，卡片保留
  final bool persist;
  const SuperChatCard(
    this.message, {
    required this.onExpire,
    this.customCountdown,
    this.persist = false,
    Key? key,
  }) : super(key: key);

  @override
  State<SuperChatCard> createState() => _SuperChatCardState();
}

class _SuperChatCardState extends State<SuperChatCard> {
  Timer? timer;

  int countdown = 0;

  @override
  void initState() {
    var currentTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    var endTime = widget.message.endTime.millisecondsSinceEpoch ~/ 1000;

    countdown = endTime - currentTime;

    // 本地生成的SC没有倒计时，无需定时器
    if (!widget.message.isCustom) {
      timer = Timer.periodic(const Duration(seconds: 1), timerCallback);
    }

    super.initState();
  }

  void timerCallback(e) {
    if (countdown <= 0) {
      if (!widget.persist) {
        widget.onExpire?.call();
      }
      timer?.cancel();
      return;
    }

    setState(() {
      countdown -= 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final displayCountdown = widget.customCountdown ?? countdown;
    final countdownText =
        widget.persist && displayCountdown <= 0 ? "已结束" : "$displayCountdown";
    return ClipRRect(
      borderRadius: AppStyle.radius8,
      child: Container(
        decoration: BoxDecoration(
          color: Utils.convertHexColor(widget.message.backgroundColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: AppStyle.edgeInsetsA8,
              child: Row(
                children: [
                  NetImage(
                    widget.message.face,
                    width: 48,
                    height: 48,
                    borderRadius: 36,
                  ),
                  AppStyle.hGap12,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.message.userName,
                          style: const TextStyle(
                            color: AppColors.black333,
                          ),
                        ),
                        Text(
                          widget.message.isCustom
                              ? "SC关注"
                              : "￥${widget.message.price}",
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!widget.message.isCustom)
                    Text(
                      countdownText,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color:
                    Utils.convertHexColor(widget.message.backgroundBottomColor),
              ),
              padding: AppStyle.edgeInsetsA8,
              child: Text(
                widget.message.message,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }
}
