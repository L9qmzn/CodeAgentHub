import 'dart:convert';

import '../models/project.dart';
import '../models/session.dart';
import '../models/message.dart';
import '../models/session_settings.dart';
import '../models/codex_user_settings.dart';
import '../services/codex_api_service.dart';
import 'codex_repository.dart';

// Helper class to track message building state
class _CodexMessageBuildState {
  final contentBlockTypes = <int, String>{};
  final textBlocksBuilder = <int, StringBuffer>{};
  final toolUseBlocks = <int, Map<String, dynamic>>{};
  final finalizedBlocks = <int>{}; // Track which blocks are finalized
  bool finalized = false;
}

class ApiCodexRepository implements CodexRepository {
  final CodexApiService _apiService;

  ApiCodexRepository(this._apiService);

  @override
  Future<Session> getSession(String id) async {
    final data = await _apiService.getSession(id);
    return Session(
      id: data['session_id'],
      projectId: data['cwd'], // Use cwd as projectId
      title: data['title'],
      name: data['title'],
      cwd: data['cwd'],
      createdAt: DateTime.parse(data['created_at']),
      updatedAt: DateTime.parse(data['updated_at']),
      messageCount: (data['messages'] as List).length,
    );
  }

  @override
  Future<List<Message>> getSessionMessages(String sessionId) async {
    print('DEBUG ApiCodexRepository: getSessionMessages for session=$sessionId');
    final data = await _apiService.getSession(sessionId);
    final messages = data['messages'] as List;
    print('DEBUG ApiCodexRepository: Raw messages count=${messages.length}');

    final result = <Message>[];

    for (var m in messages) {
      // Codex format: {type: "response_item", payload: {type: "message", role: "user", content: [...]}}
      final messageType = m['type'];

      // Only process response_item types
      if (messageType != 'response_item') continue;

      // Get the payload
      final payload = m['payload'];
      if (payload == null || payload is! Map) continue;

      // Check if payload is a message
      final payloadType = payload['type'];
      if (payloadType != 'message') continue;

      // Get role from payload
      final roleStr = payload['role']?.toString();
      if (roleStr == null) continue;
      if (roleStr != 'user' && roleStr != 'assistant') continue;

      // Get timestamp from top level
      final timestampStr = m['timestamp'];
      if (timestampStr == null) continue;

      DateTime timestamp;
      try {
        timestamp = DateTime.parse(timestampStr);
      } catch (e) {
        continue; // Skip invalid timestamps
      }

      // Parse content blocks from payload
      final contentBlocks = _parseContentBlocks(payload['content']);
      if (contentBlocks.isEmpty) continue;

      // Determine role
      MessageRole messageRole = roleStr == 'user' ? MessageRole.user : MessageRole.assistant;

      // Use timestamp as message ID
      final messageId = '${sessionId}_${timestamp.millisecondsSinceEpoch}';

      result.add(Message.fromBlocks(
        id: messageId,
        role: messageRole,
        blocks: contentBlocks,
        timestamp: timestamp,
      ));
    }

    print('DEBUG ApiCodexRepository: Parsed ${result.length} valid messages');
    return result;
  }

  List<ContentBlock> _parseContentBlocks(dynamic content) {
    final blocks = <ContentBlock>[];

    if (content == null) {
      return blocks;
    }

    if (content is String) {
      if (content.isNotEmpty) {
        blocks.add(ContentBlock(type: ContentBlockType.text, text: content));
      }
    } else if (content is List) {
      for (var item in content) {
        if (item is Map<String, dynamic>) {
          final itemType = item['type'];

          if ((itemType == 'text' || itemType == 'input_text' || itemType == 'output_text') && item['text'] != null) {
            final text = item['text'].toString();
            if (text.isNotEmpty) {
              blocks.add(ContentBlock(
                type: ContentBlockType.text,
                text: text,
              ));
            }
          } else if (itemType == 'thinking' && item['thinking'] != null) {
            blocks.add(ContentBlock(
              type: ContentBlockType.thinking,
              thinking: item['thinking'].toString(),
              signature: item['signature']?.toString(),
            ));
          } else if (itemType == 'tool_use') {
            blocks.add(ContentBlock(
              type: ContentBlockType.toolUse,
              id: item['id']?.toString(),
              name: item['name']?.toString(),
              input: item['input'] as Map<String, dynamic>?,
            ));
          } else if (itemType == 'tool_result') {
            blocks.add(ContentBlock(
              type: ContentBlockType.toolResult,
              toolUseId: item['tool_use_id']?.toString(),
              content: item['content'],
              isError: item['is_error'] as bool?,
            ));
          }
        } else if (item is String && item.isNotEmpty) {
          blocks.add(ContentBlock(type: ContentBlockType.text, text: item));
        }
      }
    }

    return blocks;
  }

  @override
  Future<Message> sendMessage({
    required String sessionId,
    required String content,
    SessionSettings? settings,
    CodexUserSettings? codexSettings,
  }) async {
    final buffer = StringBuffer();
    String? finalResult;

    await for (var event in _apiService.chat(
      sessionId: sessionId,
      message: content,
      settings: settings,
      approvalPolicy: codexSettings?.approvalPolicy,
      sandboxMode: codexSettings?.sandboxMode,
      model: codexSettings?.model,
      modelReasoningEffort: codexSettings?.modelReasoningEffort,
      networkAccessEnabled: codexSettings?.networkAccessEnabled,
      webSearchEnabled: codexSettings?.webSearchEnabled,
      skipGitRepoCheck: codexSettings?.skipGitRepoCheck,
    )) {
      final eventType = event['event_type'];

      if (eventType == 'token') {
        final text = event['text'];
        if (text != null && text.isNotEmpty) {
          buffer.write(text);
        }
      } else if (eventType == 'message') {
        final payload = event['payload'];
        if (payload != null) {
          final payloadType = payload['type'];

          if (payloadType == 'result') {
            finalResult = payload['result'] as String?;
          } else if (payloadType == 'assistant') {
            final messageContent = payload['content'];
            if (messageContent != null) {
              final extracted = _extractTextContent(messageContent);
              if (extracted.isNotEmpty) {
                buffer.write(extracted);
              }
            }
          }
        }
      } else if (eventType == 'done') {
        if (finalResult != null && finalResult.isNotEmpty) {
          return Message.assistant(finalResult);
        } else if (buffer.isNotEmpty) {
          return Message.assistant(buffer.toString());
        }
      } else if (eventType == 'error') {
        throw Exception('Codex chat error: ${event['message']}');
      }
    }

    if (finalResult != null && finalResult.isNotEmpty) {
      return Message.assistant(finalResult);
    } else if (buffer.isNotEmpty) {
      return Message.assistant(buffer.toString());
    }
    return Message.assistant('');
  }

  @override
  Future<void> clearSessionMessages(String sessionId) async {
    // API doesn't support clearing messages, this is a no-op
  }

  @override
  Stream<CodexMessageStreamEvent> sendMessageStream({
    String? sessionId,
    required String content,
    String? cwd,
    SessionSettings? settings,
    CodexUserSettings? codexSettings,
  }) async* {
    final messageStates = <String, _CodexMessageBuildState>{};
    String? currentMessageId;
    String? createdSessionId;
    bool sessionIdEmitted = false;

    // 为当前这轮对话生成一个固定的消息 ID
    final fixedMessageId = 'codex_${DateTime.now().millisecondsSinceEpoch}';
    final textBuffer = StringBuffer(); // 累积文本内容

    try {
      await for (var event in _apiService.chat(
        sessionId: sessionId,
        message: content,
        cwd: cwd,
        settings: settings,
        approvalPolicy: codexSettings?.approvalPolicy,
        sandboxMode: codexSettings?.sandboxMode,
        model: codexSettings?.model,
        modelReasoningEffort: codexSettings?.modelReasoningEffort,
        networkAccessEnabled: codexSettings?.networkAccessEnabled,
        webSearchEnabled: codexSettings?.webSearchEnabled,
        skipGitRepoCheck: codexSettings?.skipGitRepoCheck,
      )) {
        final eventType = event['event_type'];
        print('DEBUG Codex sendMessageStream: eventType=$eventType, event=${event.toString().substring(0, event.toString().length > 200 ? 200 : event.toString().length)}');

        // Capture session_id
        if (!sessionIdEmitted && event['session_id'] != null) {
          createdSessionId = event['session_id'] as String?;
          if (createdSessionId != null && createdSessionId.isNotEmpty) {
            yield CodexMessageStreamEvent(sessionId: createdSessionId);
            sessionIdEmitted = true;
          }
        }

        // Handle Codex-specific token events
        if (eventType == 'token') {
          final text = event['text'] as String?;
          if (text != null && text.isNotEmpty) {
            textBuffer.write(text); // 累积文本
            // 使用固定的消息 ID 和累积的文本创建消息
            yield CodexMessageStreamEvent(
              partialMessage: Message.fromBlocks(
                id: fixedMessageId,
                role: MessageRole.assistant,
                blocks: [
                  ContentBlock(type: ContentBlockType.text, text: textBuffer.toString()),
                ],
              ),
            );
          }
          continue;
        }

        // Handle Codex-specific item.completed events
        if (eventType == 'message') {
          final payload = event['payload'];
          if (payload != null && payload['type'] == 'item.completed') {
            final item = payload['item'];
            if (item != null && item['type'] == 'agent_message') {
              final text = item['text'] as String?;
              if (text != null && text.isNotEmpty) {
                // 使用固定的消息 ID 创建最终消息
                yield CodexMessageStreamEvent(
                  finalMessage: Message.fromBlocks(
                    id: fixedMessageId,
                    role: MessageRole.assistant,
                    blocks: [
                      ContentBlock(type: ContentBlockType.text, text: text),
                    ],
                  ),
                );
              }
            }
            continue;
          }
        }

        // Handle done event
        if (eventType == 'done') {
          continue;
        }

        // Check if this is a message event with stream_event payload (Claude Code format)
        bool isStreamEvent = false;
        Map<String, dynamic>? streamEvent;

        if (eventType == 'message') {
          final payload = event['payload'];
          if (payload != null && payload['type'] == 'stream_event') {
            isStreamEvent = true;
            streamEvent = payload['event'] as Map<String, dynamic>?;
          }
        }

        if (isStreamEvent && streamEvent != null) {
          final streamEventType = streamEvent['type'];

          if (streamEventType == 'message_start') {
            final message = streamEvent['message'];
            if (message != null) {
              final messageId = message['id'] as String?;
              if (messageId != null) {
                currentMessageId = messageId;
                if (!messageStates.containsKey(messageId)) {
                  messageStates[messageId] = _CodexMessageBuildState();
                }
              }
            }
            continue;
          }

          final state = currentMessageId != null ? messageStates[currentMessageId!] : null;
          if (state == null) continue;

          if (streamEventType == 'content_block_start') {
            final index = streamEvent['index'] as int?;
            final contentBlock = streamEvent['content_block'];

            if (index != null && contentBlock != null) {
              final blockType = contentBlock['type'] as String?;
              state.contentBlockTypes[index] = blockType ?? 'text';

              if (blockType == 'text') {
                state.textBlocksBuilder[index] = StringBuffer();
                final text = contentBlock['text'] as String?;
                if (text != null) {
                  state.textBlocksBuilder[index]!.write(text);
                }
              } else if (blockType == 'tool_use') {
                state.toolUseBlocks[index] = {
                  'id': contentBlock['id'],
                  'name': contentBlock['name'],
                  'input': {},
                };
              }
            }
          } else if (streamEventType == 'content_block_delta') {
            final index = streamEvent['index'] as int? ?? 0;
            final delta = streamEvent['delta'];

            if (delta != null) {
              final deltaType = delta['type'] as String?;

              if (deltaType == 'text_delta') {
                final text = delta['text'] as String?;
                if (text != null) {
                  if (!state.textBlocksBuilder.containsKey(index)) {
                    state.textBlocksBuilder[index] = StringBuffer();
                    state.contentBlockTypes[index] = 'text';
                  }
                  state.textBlocksBuilder[index]!.write(text);
                }
              } else if (deltaType == 'input_json_delta') {
                final jsonDelta = delta['partial_json'] as String?;
                if (jsonDelta != null && state.toolUseBlocks.containsKey(index)) {
                  state.toolUseBlocks[index]!['input_json'] =
                      (state.toolUseBlocks[index]!['input_json'] ?? '') + jsonDelta;
                }
              }
            }

            final blocks = _buildContentBlocks(
              state.contentBlockTypes,
              state.textBlocksBuilder,
              state.toolUseBlocks,
              state.finalizedBlocks,
            );

            if (blocks.isNotEmpty) {
              yield CodexMessageStreamEvent(
                partialMessage: Message.fromBlocks(
                  id: currentMessageId!,
                  role: MessageRole.assistant,
                  blocks: List.from(blocks),
                ),
              );
            }
          } else if (streamEventType == 'content_block_stop') {
            final index = streamEvent['index'] as int?;
            if (index != null) {
              state.finalizedBlocks.add(index);

              if (state.toolUseBlocks.containsKey(index)) {
                final inputJson = state.toolUseBlocks[index]!['input_json'] as String?;
                if (inputJson != null && inputJson.isNotEmpty) {
                  try {
                    final decoded = json.decode(inputJson);
                    if (decoded is Map<String, dynamic>) {
                      state.toolUseBlocks[index]!['input'] = decoded;
                    }
                  } catch (e) {
                    // Keep empty input if JSON parsing fails
                  }
                }
              }

              final blocks = _buildContentBlocks(
                state.contentBlockTypes,
                state.textBlocksBuilder,
                state.toolUseBlocks,
                state.finalizedBlocks,
              );

              if (blocks.isNotEmpty && currentMessageId != null) {
                yield CodexMessageStreamEvent(
                  partialMessage: Message.fromBlocks(
                    id: currentMessageId!,
                    role: MessageRole.assistant,
                    blocks: List.from(blocks),
                  ),
                );
              }
            }
          } else if (streamEventType == 'message_stop') {
            if (currentMessageId != null && state != null) {
              final blocks = _buildContentBlocks(
                state.contentBlockTypes,
                state.textBlocksBuilder,
                state.toolUseBlocks,
                state.finalizedBlocks,
              );

              if (blocks.isNotEmpty) {
                yield CodexMessageStreamEvent(
                  finalMessage: Message.fromBlocks(
                    id: currentMessageId!,
                    role: MessageRole.assistant,
                    blocks: blocks,
                  ),
                );
                state.finalized = true;
              }
            }
          }
        } else if (eventType == 'message') {
          final payload = event['payload'];

          if (payload != null && payload['type'] == 'stream_event') {
            continue;
          }

          if (payload != null && payload['type'] == 'result') {
            final stats = MessageStats.fromResultPayload(payload);
            yield CodexMessageStreamEvent(stats: stats);
          }
        } else if (eventType == 'done') {
          yield CodexMessageStreamEvent(isDone: true);
          return;
        } else if (eventType == 'error') {
          yield CodexMessageStreamEvent(
            error: event['message']?.toString() ?? 'Unknown error',
            isDone: true,
          );
          return;
        }
      }

      yield CodexMessageStreamEvent(isDone: true);
    } catch (e) {
      yield CodexMessageStreamEvent(
        error: e.toString(),
        isDone: true,
      );
    }
  }

  List<ContentBlock> _buildContentBlocks(
    Map<int, String> types,
    Map<int, StringBuffer> textBlocks,
    Map<int, Map<String, dynamic>> toolBlocks,
    Set<int> finalizedBlocks,
  ) {
    final blocks = <ContentBlock>[];

    final allIndices = <int>{};
    allIndices.addAll(types.keys);
    final sortedIndices = allIndices.toList()..sort();

    for (final index in sortedIndices) {
      final blockType = types[index];

      if (blockType == 'text' && textBlocks.containsKey(index)) {
        final text = textBlocks[index]!.toString();
        if (text.isNotEmpty) {
          blocks.add(ContentBlock(
            type: ContentBlockType.text,
            text: text,
          ));
        }
      } else if (blockType == 'tool_use' && toolBlocks.containsKey(index)) {
        if (finalizedBlocks.contains(index)) {
          final toolBlock = toolBlocks[index]!;
          blocks.add(ContentBlock(
            type: ContentBlockType.toolUse,
            id: toolBlock['id'] as String?,
            name: toolBlock['name'] as String?,
            input: toolBlock['input'] as Map<String, dynamic>?,
          ));
        }
      }
    }

    return blocks;
  }

  String _extractTextContent(dynamic content) {
    if (content is String) {
      return content;
    }

    if (content is List) {
      final buffer = StringBuffer();
      for (var item in content) {
        if (item is Map) {
          if (item['type'] == 'text') {
            buffer.write(item['text']);
          }
        }
      }
      return buffer.toString();
    }

    return '';
  }

  @override
  Future<CodexUserSettings> getUserSettings(String userId) async {
    try {
      final data = await _apiService.getUserSettings(userId);
      return CodexUserSettings.fromJson({
        'user_id': userId,
        ...data,
      });
    } catch (e) {
      // Return defaults if settings don't exist
      return CodexUserSettings.defaults(userId);
    }
  }

  @override
  Future<void> updateUserSettings(String userId, CodexUserSettings settings) async {
    await _apiService.updateUserSettings(userId, settings.toJson());
  }

  @override
  CodexApiService get apiService => _apiService;

  // 项目管理：从 sessions 按 cwd 分组创建虚拟项目
  @override
  Future<List<Project>> getProjects() async {
    final sessions = await _apiService.getSessions();

    // Group sessions by cwd to create projects
    final Map<String, List<Map<String, dynamic>>> projectMap = {};
    for (var session in sessions) {
      final cwd = session['cwd'] as String;
      projectMap.putIfAbsent(cwd, () => []).add(session);
    }

    // Convert to Project list
    final projects = <Project>[];
    projectMap.forEach((cwd, sessions) {
      // Use the directory name as project name
      final name = cwd.split(RegExp(r'[/\\]')).last;

      // Find the earliest created_at and latest updated_at
      DateTime? earliest;
      DateTime? latest;

      for (var session in sessions) {
        final createdAt = DateTime.parse(session['created_at']);
        final updatedAt = DateTime.parse(session['updated_at']);

        if (earliest == null || createdAt.isBefore(earliest)) {
          earliest = createdAt;
        }
        if (latest == null || updatedAt.isAfter(latest)) {
          latest = updatedAt;
        }
      }

      projects.add(Project(
        id: cwd, // Use cwd as unique ID
        name: name,
        path: cwd,
        createdAt: earliest ?? DateTime.now(),
        lastActiveAt: latest,
        sessionCount: sessions.length,
      ));
    });

    // Sort by lastActiveAt descending
    projects.sort((a, b) {
      if (a.lastActiveAt == null && b.lastActiveAt == null) return 0;
      if (a.lastActiveAt == null) return 1;
      if (b.lastActiveAt == null) return -1;
      return b.lastActiveAt!.compareTo(a.lastActiveAt!);
    });

    return projects;
  }

  @override
  Future<Project> getProject(String id) async {
    final projects = await getProjects();
    return projects.firstWhere(
      (p) => p.id == id,
      orElse: () => throw Exception('Project not found'),
    );
  }

  @override
  Future<List<Session>> getProjectSessions(String projectId) async {
    final allSessions = await _apiService.getSessions();

    // Filter sessions by cwd (projectId is the cwd)
    final projectSessions = allSessions
        .where((s) => s['cwd'] == projectId)
        .map((s) => Session(
              id: s['session_id'],
              projectId: projectId,
              title: s['title'],
              name: s['title'], // Use title as name
              cwd: s['cwd'],
              createdAt: DateTime.parse(s['created_at']),
              updatedAt: DateTime.parse(s['updated_at']),
              messageCount: s['message_count'] ?? 0,
            ))
        .toList();

    // Sort by updatedAt descending
    projectSessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return projectSessions;
  }
}
