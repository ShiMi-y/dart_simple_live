import 'package:simple_live_core/simple_live_core.dart';

/// 同时监控的其它直播间弹幕（带房间标记）
class MonitorLiveMessage extends LiveMessage {
  /// 来源房间标题（用于聊天区前缀）
  final String roomTag;

  MonitorLiveMessage({
    required this.roomTag,
    required super.type,
    required super.userName,
    required super.message,
    super.data,
    required super.color,
    super.userId,
  });
}
