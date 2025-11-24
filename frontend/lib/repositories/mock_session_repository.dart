import '../models/session.dart';
import '../models/message.dart';
import '../models/session_settings.dart';
import '../models/user_settings.dart';
import 'session_repository.dart';

class MockSessionRepository implements SessionRepository {
  final Map<String, List<Message>> _messageStore = {};

  @override
  Future<Session> getSession(String id) async {
    return Session(
      id: id,
      projectId: 'test-project-1',
      title: 'Test Session',
      name: 'Test Session',
      cwd: '/test/path',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      messageCount: 0,
    );
  }

  @override
  Future<List<Message>> getSessionMessages(String sessionId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _messageStore[sessionId] ?? [];
  }

  @override
  Future<Message> sendMessage({
    required String sessionId,
    required String content,
    SessionSettings? settings,
  }) async {
    await Future.delayed(const Duration(seconds: 1));
    final response = Message.assistant('This is a mock response to: $content');

    _messageStore.putIfAbsent(sessionId, () => []);
    _messageStore[sessionId]!.add(response);

    return response;
  }

  @override
  Future<void> clearSessionMessages(String sessionId) async {
    _messageStore[sessionId]?.clear();
  }

  @override
  Stream<MessageStreamEvent> sendMessageStream({
    String? sessionId,
    String? content,
    List<ContentBlock>? contentBlocks,
    String? cwd,
    SessionSettings? settings,
  }) async* {
    await Future.delayed(const Duration(milliseconds: 500));

    // 从 content 或 contentBlocks 提取文本
    String messageText = content ?? '';
    if (messageText.isEmpty && contentBlocks != null && contentBlocks.isNotEmpty) {
      messageText = contentBlocks
          .where((block) => block.type == ContentBlockType.text)
          .map((block) => block.text ?? '')
          .join(' ');
    }

    final response = Message.assistant('This is a mock response to: $messageText');
    final actualSessionId = sessionId ?? 'mock_session_${DateTime.now().millisecondsSinceEpoch}';
    _messageStore.putIfAbsent(actualSessionId, () => []);
    _messageStore[actualSessionId]!.add(response);

    yield MessageStreamEvent(
      finalMessage: response,
      isDone: true,
    );
  }

  @override
  Future<ClaudeUserSettings> getUserSettings(String userId) async {
    return ClaudeUserSettings.defaults(userId);
  }

  @override
  Future<void> updateUserSettings(String userId, ClaudeUserSettings settings) async {
    // Mock implementation - do nothing
  }
}
