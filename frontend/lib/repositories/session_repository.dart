import '../models/session.dart';
import '../models/message.dart';
import '../models/session_settings.dart';
import '../models/user_settings.dart';

// 用于流式消息更新的事件
class MessageStreamEvent {
  final Message? partialMessage; // 正在构建中的消息
  final Message? finalMessage; // 最终完成的消息
  final MessageStats? stats; // 统计信息（从 ResultMessage 提取）
  final String? error;
  final bool isDone;
  final String? sessionId; // 新创建的session ID（用于新对话）
  final String? runId; // 运行ID（用于停止任务）

  MessageStreamEvent({
    this.partialMessage,
    this.finalMessage,
    this.stats,
    this.error,
    this.isDone = false,
    this.sessionId,
    this.runId,
  });
}

abstract class SessionRepository {
  Future<Session> getSession(String id);
  Future<List<Message>> getSessionMessages(String sessionId);

  Future<Message> sendMessage({
    required String sessionId,
    required String content,
    SessionSettings? settings,
  });

  // 流式发送消息，实时返回内容块
  Stream<MessageStreamEvent> sendMessageStream({
    String? sessionId, // 可选，如果为null则创建新session
    String? content,  // 改为可选（纯文本）
    List<ContentBlock>? contentBlocks,  // 新增：支持content blocks（包含图片）
    String? cwd, // 工作目录，创建新session时必需
    SessionSettings? settings,
  });

  Future<void> clearSessionMessages(String sessionId);

  // 获取用户全局设置
  Future<ClaudeUserSettings> getUserSettings(String userId);

  // 更新用户全局设置
  Future<void> updateUserSettings(String userId, ClaudeUserSettings settings);
}
