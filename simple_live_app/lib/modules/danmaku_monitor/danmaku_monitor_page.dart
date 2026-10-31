import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/modules/danmaku_monitor/danmaku_monitor_controller.dart';

/// 多房间弹幕监控
class DanmakuMonitorPage extends GetView<DanmakuMonitorController> {
  const DanmakuMonitorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("弹幕监控"),
        actions: [
          Obx(
            () => IconButton(
              tooltip: controller.autoScroll.value ? "自动滚动：开" : "自动滚动：关",
              onPressed: () =>
                  controller.autoScroll.value = !controller.autoScroll.value,
              icon: Icon(
                controller.autoScroll.value
                    ? Icons.vertical_align_bottom
                    : Icons.pause_circle_outline,
                color: controller.autoScroll.value
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
            ),
          ),
          IconButton(
            tooltip: "添加房间",
            onPressed: () => showAddRoomDialog(context),
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: "清空消息",
            onPressed: controller.clearMessages,
            icon: const Icon(Icons.cleaning_services_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildRoomBar(context),
          AppStyle.divider,
          Expanded(child: _buildMessageList(context)),
        ],
      ),
    );
  }

  /// 顶部房间条
  Widget _buildRoomBar(BuildContext context) {
    return Obx(() {
      if (controller.rooms.isEmpty) {
        return Padding(
          padding: AppStyle.edgeInsetsA12,
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: Theme.of(context).colorScheme.outline,
              ),
              AppStyle.hGap8,
              Expanded(
                child: Text(
                  "点击右上角 + 添加哔哩哔哩直播间，可同时监控多个房间的弹幕",
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
            ],
          ),
        );
      }
      return SizedBox(
        height: 52,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: AppStyle.edgeInsetsH12,
          itemCount: controller.rooms.length,
          separatorBuilder: (_, i) => AppStyle.hGap8,
          itemBuilder: (_, i) {
            var room = controller.rooms[i];
            return Center(
              child: Obx(
                () => InputChip(
                  avatar: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: room.connected.value
                          ? const Color(0xFF00B578)
                          : Colors.grey,
                    ),
                  ),
                  label: Text(
                    "${room.userName} · ${room.messageCount.value}",
                    style: const TextStyle(fontSize: 12),
                  ),
                  labelStyle: TextStyle(color: room.color),
                  onDeleted: () => controller.removeRoom(room),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            );
          },
        ),
      );
    });
  }

  /// 弹幕列表
  Widget _buildMessageList(BuildContext context) {
    return Obx(() {
      if (controller.messages.isEmpty) {
        return Center(
          child: Text(
            "暂无弹幕\n添加房间后会自动接收并汇总显示",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.outline,
              height: 1.6,
            ),
          ),
        );
      }
      return ListView.builder(
        controller: controller.scrollController,
        padding: AppStyle.edgeInsetsA12,
        itemCount: controller.messages.length,
        itemBuilder: (_, i) {
          var msg = controller.messages[i];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 3,
                  height: 16,
                  margin: const EdgeInsets.only(top: 3, right: 8),
                  decoration: BoxDecoration(
                    color: msg.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: DefaultTextStyle.of(context).style.copyWith(
                            fontSize: 13,
                            height: 1.4,
                          ),
                      children: [
                        TextSpan(
                          text: "[${msg.roomTitle}] ",
                          style: TextStyle(
                            color: msg.color.withValues(alpha: 0.9),
                            fontSize: 12,
                          ),
                        ),
                        TextSpan(
                          text: "${msg.userName}: ",
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        TextSpan(text: msg.text),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    });
  }

  /// 添加房间对话框
  Future<void> showAddRoomDialog(BuildContext context) async {
    var textController = TextEditingController();
    var result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("添加监控房间"),
          content: TextField(
            controller: textController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: "房间号或直播间链接",
              hintText: "如 1727071052 或 https://live.bilibili.com/1727071052",
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("取消"),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(textController.text),
              child: const Text("添加"),
            ),
          ],
        );
      },
    );
    if (result != null && result.trim().isNotEmpty) {
      await controller.addRoom(result);
    }
  }
}
