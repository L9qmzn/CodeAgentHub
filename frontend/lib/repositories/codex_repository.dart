import '../models/project.dart';
import '../models/session.dart';
import '../models/message.dart';
import '../models/session_settings.dart';
import '../models/codex_user_settings.dart';

// 用于流式消息更新的事件（与SessionRepository相同）
class CodexMessageStreamEvent {
  final Message? partialMessage; // 正在构建中的消息
  final Message? finalMessage; // 最终完成的消息
  final MessageStats? stats; // 统计信息（从 ResultMessage 提取）
  final String? error;
  final bool isDone;
  final String? sessionId; // 新创建的session ID（用于新对话）

  CodexMessageStreamEvent({
    this.partialMessage,
    this.finalMessage,
    this.stats,
    this.error,
    this.isDone = false,
    this.sessionId,
  });
}

abstract class CodexRepository {
  // 项目管理（按cwd分组）
  Future<List<Project>> getProjects();
  Future<Project> getProject(String id);
  Future<List<Session>> getProjectSessions(String projectId);

  // Session 管理
  Future<Session> getSession(String id);
  Future<List<Message>> getSessionMessages(String sessionId);

  Future<Message> sendMessage({
    required String sessionId,
    required String content,
    SessionSettings? settings,
    CodexUserSettings? codexSettings,
  });

  // 流式发送消息，实时返回内容块
  Stream<CodexMessageStreamEvent> sendMessageStream({
    String? sessionId, // 可选，如果为null则创建新session
    required String content,
    String? cwd, // 工作目录，创建新session时必需
    SessionSettings? settings,
    CodexUserSettings? codexSettings, // Codex特定设置
  });

  Future<void> clearSessionMessages(String sessionId);

  // Codex特定：获取用户全局设置
  Future<CodexUserSettings> getUserSettings(String userId);

  // Codex特定：更新用户全局设置
  Future<void> updateUserSettings(String userId, CodexUserSettings settings);

  // For creating new sessions - access to API service
  dynamic get apiService;
}
