import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/services/bilibili_account_service.dart';
import 'package:simple_live_app/services/intimacy_service.dart';

/// 后台自动挂亲密度
class IntimacyPage extends StatelessWidget {
  const IntimacyPage({super.key});

  IntimacyService get controller => IntimacyService.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("自动挂亲密度"),
        actions: [
          Obx(
            () => Row(
              children: [
                Text(
                  controller.enabled.value ? "已启用" : "已停用",
                  style: Get.textTheme.bodySmall,
                ),
                Switch(
                  value: controller.enabled.value,
                  onChanged: (v) => controller.setEnabled(v),
                ),
                AppStyle.hGap12,
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: "添加直播间",
        onPressed: () => _showAddDialog(context),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          _buildTips(context),
          AppStyle.divider,
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _buildRooms(context)),
                Container(width: 1, color: Theme.of(context).dividerColor),
                Expanded(flex: 2, child: _buildLogs(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTips(BuildContext context) {
    return Obx(
      () => Container(
        width: double.infinity,
        padding: AppStyle.edgeInsetsA12,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "开播后自动挂亲密度（哔哩哔哩）",
              style: Get.textTheme.titleSmall,
            ),
            AppStyle.vGap4,
            Text(
              "每 60 秒检查一次房间状态；开播后自动发送网页心跳以累计粉丝牌亲密度，"
              "窗口最小化也会继续运行。需要先在「账号管理」登录哔哩哔哩。",
              style: Get.textTheme.bodySmall,
            ),
            if (!BiliBiliAccountService.instance.logined.value) ...[
              AppStyle.vGap4,
              Text(
                "⚠ 当前未登录哔哩哔哩，无法挂亲密度",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRooms(BuildContext context) {
    return Obx(() {
      if (controller.rooms.isEmpty) {
        return Center(
          child: Text(
            "还没有配置直播间\n点击右下角 + 添加（房间号或直播间链接）",
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        );
      }
      return ListView.separated(
        padding: AppStyle.edgeInsetsA12,
        itemCount: controller.rooms.length,
        separatorBuilder: (_, i) => AppStyle.divider,
        itemBuilder: (_, i) {
          var room = controller.rooms[i];
          return Obx(
            () => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                room.live.value ? Icons.live_tv : Icons.tv_off_outlined,
                color: room.live.value ? const Color(0xFF00B578) : null,
              ),
              title: Text(
                room.title.value.isEmpty ? "房间 ${room.roomId}" : room.title.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                "ID ${room.roomId} · ${room.live.value ? "直播中" : "未开播"}"
                "${room.lastBeat.value.isEmpty ? "" : " · 上次心跳 ${room.lastBeat.value}"}"
                "${room.lastResult.value.isEmpty ? "" : " · ${room.lastResult.value}"}",
                style: const TextStyle(fontSize: 12),
              ),
              trailing: IconButton(
                tooltip: "移除",
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => controller.removeRoom(room.roomId),
              ),
            ),
          );
        },
      );
    });
  }

  Widget _buildLogs(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: AppStyle.edgeInsetsA12,
          child: Row(
            children: [
              Text("运行日志", style: Get.textTheme.titleSmall),
              const Spacer(),
              Text(
                "最多 80 条",
                style: Get.textTheme.bodySmall?.copyWith(fontSize: 11),
              ),
            ],
          ),
        ),
        Expanded(
          child: Obx(() {
            if (controller.logs.isEmpty) {
              return Center(
                child: Text(
                  "暂无日志",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                    fontSize: 12,
                  ),
                ),
              );
            }
            return ListView.builder(
              padding: AppStyle.edgeInsetsH12,
              itemCount: controller.logs.length,
              itemBuilder: (_, i) {
                var log = controller.logs[i];
                var t = log.time;
                var stamp =
                    "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}";
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    "$stamp [${log.room}] ${log.text}",
                    style: const TextStyle(fontSize: 11, height: 1.4),
                  ),
                );
              },
            );
          }),
        ),
      ],
    );
  }

  Future<void> _showAddDialog(BuildContext context) async {
    var textController = TextEditingController();
    var result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("添加挂机直播间"),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: "房间号或直播间链接",
            hintText: "如 1727071052",
          ),
          onSubmitted: (v) => Navigator.of(context).pop(v),
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
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      var ok = await controller.addRoom(result);
      if (!ok) {
        Get.snackbar("提示", "房间号格式不正确或已存在");
      }
    }
  }
}
