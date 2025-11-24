import 'dart:convert';

import '../models/session.dart';
import '../models/message.dart';
import '../models/session_settings.dart';
import '../models/user_settings.dart';
import '../services/api_service.dart';
import 'session_repository.dart';

// Message streaming state machine
enum _StreamingMode {
  idle,              // 等待消息
  tokenMode,         // 仅token流式（普通对话）
  streamEventMode,   // stream_event模式（工具调用等复杂消息）
  finalized,         // 消息已完成
}

// Helper class to track message building state
class _MessageBuildState {
  _StreamingMode mode = _StreamingMode.idle;
  final contentBlockTypes = <int, String>{};
  final textBlocksBuilder = <int, StringBuffer>{};
  final toolUseBlocks = <int, Map<String, dynamic>>{};
  final finalizedBlocks = <int>{}; // Track which blocks are finalized
  bool finalized = false;
}

class ApiSessionRepository implements SessionRepository {
  final ApiService _apiService;

  ApiSessionRepository(this._apiService);

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
    final data = await _apiService.getSession(sessionId);
    final messages = data['messages'] as List;

    final result = <Message>[];

    for (var m in messages) {
      // Skip queue-operation and other non-message types
      final messageType = m['type'];
      if (messageType == null || messageType == 'queue-operation') continue;

      // Only process user and assistant types
      if (messageType != 'user' && messageType != 'assistant') continue;

      // Get the nested message object
      final message = m['message'];
      if (message == null) continue;

      // Verify role matches type
      final roleStr = message['role']?.toString();
      if (roleStr == null || roleStr != messageType) continue;

      // Get timestamp from top level
      final timestampStr = m['timestamp'];
      if (timestampStr == null) continue;

      DateTime timestamp;
      try {
        timestamp = DateTime.parse(timestampStr);
      } catch (e) {
        continue; // Skip invalid timestamps
      }

      // Parse content blocks
      final contentBlocks = _parseContentBlocks(message['content']);
      if (contentBlocks.isEmpty) continue;

      // Determine role
      // Tool results are marked as 'user' by backend, but should be displayed as assistant messages
      MessageRole messageRole;
      if (roleStr == 'user') {
        final hasOnlyToolResults = contentBlocks.every((block) => block.type == ContentBlockType.toolResult);
        messageRole = hasOnlyToolResults ? MessageRole.assistant : MessageRole.user;
      } else {
        messageRole = MessageRole.assistant;
      }

      // Use uuid as message ID if available
      final messageId = m['uuid']?.toString() ?? '${sessionId}_${timestamp.millisecondsSinceEpoch}';

      result.add(Message.fromBlocks(
        id: messageId,
        role: messageRole,
        blocks: contentBlocks,
        timestamp: timestamp,
      ));
    }

    return result;
  }

  List<ContentBlock> _parseContentBlocks(dynamic content) {
    final blocks = <ContentBlock>[];

    if (content == null) {
      return blocks;
    }

    if (content is String) {
      // 字符串内容：直接作为 text block
      if (content.isNotEmpty) {
        blocks.add(ContentBlock(type: ContentBlockType.text, text: content));
      }
    } else if (content is List) {
      for (var item in content) {
        if (item is Map<String, dynamic>) {
          final itemType = item['type'];

          // 只处理已知的内容块类型，忽略其他类型
          if (itemType == 'text' && item['text'] != null) {
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
          } else if (itemType == 'image') {
            // 解析图片块
            final source = item['source'];
            if (source is Map<String, dynamic>) {
              final sourceType = source['type'] as String?;
              final mediaType = source['media_type'] as String?;
              final data = source['data'] as String?;

              if (sourceType == 'base64' && data != null && data.isNotEmpty) {
                blocks.add(ContentBlock(
                  type: ContentBlockType.image,
                  imageSource: sourceType,
                  imageMediaType: mediaType ?? 'image/jpeg',
                  imageData: data,
                ));
              }
            }
          }
          // 如果是未知类型，忽略它（不再添加 fallback）
        } else if (item is String && item.isNotEmpty) {
          // 列表中的字符串项
          blocks.add(ContentBlock(type: ContentBlockType.text, text: item));
        }
      }
    }
    // 其他类型的 content 直接忽略（不再转换为字符串）

    return blocks;
  }

  @override
  Future<Message> sendMessage({
    required String sessionId,
    required String content,
    SessionSettings? settings,
  }) async {
    final buffer = StringBuffer();
    String? finalResult;

    await for (var event in _apiService.chat(
      sessionId: sessionId,
      message: content,
      settings: settings,
    )) {
      final eventType = event['event_type'];

      if (eventType == 'token') {
        // Token event: {"session_id": "...", "text": "..."}
        final text = event['text'];
        if (text != null && text.isNotEmpty) {
          buffer.write(text);
        }
      } else if (eventType == 'message') {
        // Message event: {"session_id": "...", "payload": {...}}
        final payload = event['payload'];
        if (payload != null) {
          final payloadType = payload['type'];

          if (payloadType == 'result') {
            // ResultMessage: extract result field
            finalResult = payload['result'] as String?;
          } else if (payloadType == 'assistant') {
            // AssistantMessage: extract content blocks
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
        // Done event: return accumulated message
        if (finalResult != null && finalResult.isNotEmpty) {
          return Message.assistant(finalResult);
        } else if (buffer.isNotEmpty) {
          return Message.assistant(buffer.toString());
        }
      } else if (eventType == 'error') {
        throw Exception('Chat error: ${event['message']}');
      }
    }

    // Fallback if no content received
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
    // In real implementation, this might call a DELETE endpoint
  }

  @override
  Stream<MessageStreamEvent> sendMessageStream({
    String? sessionId, // 可选，如果为null则创建新session
    String? content,
    List<ContentBlock>? contentBlocks,
    String? cwd, // 工作目录，创建新session时必需
    SessionSettings? settings,
  }) async* {
    // 构建消息内容 - 匹配后端期望的格式
    final dynamic messageContent;

    if (contentBlocks != null && contentBlocks.isNotEmpty) {
      // 构建符合后端格式的content数组
      // 后端期望格式：直接是数组 [{ type: "text", text: "..." }, { type: "image", source: {...} }]
      messageContent = contentBlocks.map((block) {
        if (block.type == ContentBlockType.image) {
          return {
            'type': 'image',
            'source': {
              'type': 'base64',
              'media_type': block.imageMediaType ?? 'image/jpeg',
              'data': block.imageData,
            }
          };
        } else if (block.type == ContentBlockType.text) {
          return {
            'type': 'text',
            'text': block.text ?? '',
          };
        }
        return null;
      }).where((item) => item != null).toList();

      print('DEBUG: Sending message with ${contentBlocks.length} content blocks');
    } else if (content != null && content.isNotEmpty) {
      // 纯文本消息（向后兼容）
      messageContent = content;
      print('DEBUG: Sending text message');
    } else {
      throw ArgumentError('Either content or contentBlocks must be provided');
    }

    // Track multiple messages by their message IDs (for multi-turn)
    final messageStates = <String, _MessageBuildState>{}; // message.id -> build state
    String? currentMessageId;
    String? createdSessionId; // 捕获新创建的session ID
    bool sessionIdEmitted = false; // 标记是否已发送session ID

    // Token accumulation for word-level streaming
    final tokenBuffer = StringBuffer();
    int tokenCount = 0;

    try {
      await for (var event in _apiService.chat(
        sessionId: sessionId,
        message: messageContent,
        cwd: cwd,
        settings: settings,
      )) {
        final eventType = event['event_type'];
        print('DEBUG SSE: Received event type: $eventType');

        // 处理 'run' 事件，捕获 run_id 用于停止任务
        if (eventType == 'run') {
          final runId = event['run_id'] as String?;
          if (runId != null && runId.isNotEmpty) {
            yield MessageStreamEvent(runId: runId);
            print('DEBUG SSE: Captured run_id: $runId');
          }
          continue;
        }

        // 捕获session_id（通常在第一个事件中）
        if (!sessionIdEmitted && event['session_id'] != null) {
          createdSessionId = event['session_id'] as String?;
          if (createdSessionId != null && createdSessionId.isNotEmpty) {
            // 立即发送session ID给前端
            yield MessageStreamEvent(sessionId: createdSessionId);
            sessionIdEmitted = true;
            print('DEBUG SSE: Captured session_id: $createdSessionId');
          }
        }

        // 处理 'token' 事件 - 单词级别流式传输（普通对话）
        if (eventType == 'token') {
          final text = event['text'] as String?;
          if (text != null && text.isNotEmpty) {
            // 检查当前状态
            if (currentMessageId != null && messageStates.containsKey(currentMessageId)) {
              final state = messageStates[currentMessageId]!;

              // 状态机：根据当前模式决定是否处理token
              if (state.mode == _StreamingMode.streamEventMode) {
                // 已切换到stream_event模式，忽略token
                print('DEBUG SSE: ⊘ Ignoring token (in streamEventMode)');
                continue;
              } else if (state.mode == _StreamingMode.finalized) {
                // 已完成，忽略后续token
                print('DEBUG SSE: ⊘ Ignoring token (finalized)');
                continue;
              }
            }

            tokenBuffer.write(text);
            tokenCount++;

            // 每累积10个token或遇到换行符时发送一次更新（优化性能）
            if (tokenCount >= 10 || text.contains('\n')) {
              // 如果还没有当前消息，创建新的
              if (currentMessageId == null) {
                currentMessageId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
                messageStates[currentMessageId] = _MessageBuildState();
              }

              final state = messageStates[currentMessageId]!;

              // 设置为 tokenMode（如果还是idle）
              if (state.mode == _StreamingMode.idle) {
                state.mode = _StreamingMode.tokenMode;
                print('DEBUG SSE: → Enter TOKEN_MODE');
              }

              // 将token累积到第一个文本块
              if (!state.textBlocksBuilder.containsKey(0)) {
                state.textBlocksBuilder[0] = StringBuffer();
                state.contentBlockTypes[0] = 'text';
              }
              state.textBlocksBuilder[0]!.write(tokenBuffer.toString());

              // 清空token buffer
              tokenBuffer.clear();
              tokenCount = 0;

              // 构建并发送部分消息
              final blocks = _buildContentBlocks(
                state.contentBlockTypes,
                state.textBlocksBuilder,
                state.toolUseBlocks,
                state.finalizedBlocks,
              );

              if (blocks.isNotEmpty) {
                yield MessageStreamEvent(
                  partialMessage: Message.fromBlocks(
                    id: currentMessageId!,
                    role: MessageRole.assistant,
                    blocks: List.from(blocks),
                  ),
                );
              }
            }
          }
          continue;
        }

        // Check if this is a message event with stream_event payload
        bool isStreamEvent = false;
        Map<String, dynamic>? streamEvent;

        if (eventType == 'message') {
          final payload = event['payload'];
          print('DEBUG SSE: Message payload type: ${payload?['type']}');
          if (payload != null && payload['type'] == 'stream_event') {
            isStreamEvent = true;
            streamEvent = payload['event'] as Map<String, dynamic>?;
            print('DEBUG SSE: Stream event type: ${streamEvent?['type']}');
          }
        }

        if (isStreamEvent && streamEvent != null) {
          final streamEventType = streamEvent['type'];

          // message_start: Extract message ID and switch to STREAM_EVENT_MODE
          if (streamEventType == 'message_start') {
            final message = streamEvent['message'];
            if (message != null) {
              final messageId = message['id'] as String?;
              if (messageId != null) {
                // 检查是否已有temp消息（从token创建的）
                if (currentMessageId != null && currentMessageId!.startsWith('temp_')) {
                  // 有temp消息，需要迁移或替换
                  final tempState = messageStates[currentMessageId];
                  if (tempState != null && tempState.mode == _StreamingMode.tokenMode) {
                    print('DEBUG SSE: → Switching from TOKEN_MODE to STREAM_EVENT_MODE');
                    // 清空token累积的数据，使用stream_event重建
                    tempState.textBlocksBuilder.clear();
                    tempState.contentBlockTypes.clear();
                    tempState.mode = _StreamingMode.streamEventMode;
                  }
                  // 使用真实ID替换temp ID
                  messageStates.remove(currentMessageId);
                  messageStates[messageId] = tempState ?? _MessageBuildState();
                } else {
                  // 没有temp消息，直接创建新的
                  if (!messageStates.containsKey(messageId)) {
                    messageStates[messageId] = _MessageBuildState();
                  }
                }

                final state = messageStates[messageId]!;
                state.mode = _StreamingMode.streamEventMode;
                currentMessageId = messageId;
                print('DEBUG SSE: → Enter STREAM_EVENT_MODE, ID: $messageId');
              }
            }
            continue; // Don't emit anything for message_start
          }

          // Get current state
          final state = currentMessageId != null ? messageStates[currentMessageId!] : null;
          if (state == null) continue;

          if (streamEventType == 'content_block_start') {
            // New content block started
            final index = streamEvent['index'] as int?;
            final contentBlock = streamEvent['content_block'];

            if (index != null && contentBlock != null) {
              final blockType = contentBlock['type'] as String?;
              state.contentBlockTypes[index] = blockType ?? 'text';
              print('DEBUG SSE: content_block_start at index $index, type: $blockType');

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
              } else if (blockType == 'tool_result') {
                // 处理工具结果块 - tool_result 通常不会出现在 stream_event 中
                // 它们通常通过 message 事件（type='user'）发送
                // 但如果确实收到了，我们需要立即发送它
                print('DEBUG SSE: tool_result block received in stream_event at index $index');
                final toolResultBlock = ContentBlock(
                  type: ContentBlockType.toolResult,
                  toolUseId: contentBlock['tool_use_id'] as String?,
                  content: contentBlock['content'],
                  isError: contentBlock['is_error'] as bool?,
                );

                // 立即发送 tool_result 作为独立的 assistant 消息
                final toolResultMessageId = 'tool_result_${DateTime.now().millisecondsSinceEpoch}_$index';
                print('DEBUG SSE: Emitting tool_result as separate message with ID: $toolResultMessageId');
                yield MessageStreamEvent(
                  finalMessage: Message.fromBlocks(
                    id: toolResultMessageId,
                    role: MessageRole.assistant,
                    blocks: [toolResultBlock],
                  ),
                );
              }
            }
          } else if (streamEventType == 'content_block_delta') {
            // Incremental content update
            final index = streamEvent['index'] as int? ?? 0;
            final delta = streamEvent['delta'];
            print('DEBUG SSE: content_block_delta at index $index, delta type: ${delta?['type']}');

            if (delta != null) {
              final deltaType = delta['type'] as String?;

              if (deltaType == 'text_delta') {
                final text = delta['text'] as String?;
                print('DEBUG SSE: text_delta: "$text"');
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
                  // Accumulate JSON for tool input
                  state.toolUseBlocks[index]!['input_json'] =
                      (state.toolUseBlocks[index]!['input_json'] ?? '') + jsonDelta;
                }
              }
            }

            // Rebuild content blocks from current state
            final blocks = _buildContentBlocks(
              state.contentBlockTypes,
              state.textBlocksBuilder,
              state.toolUseBlocks,
              state.finalizedBlocks,
            );

            // Emit partial message with current state
            if (blocks.isNotEmpty) {
              print('DEBUG SSE: Emitting partialMessage with ${blocks.length} blocks');
              yield MessageStreamEvent(
                partialMessage: Message.fromBlocks(
                  id: currentMessageId!,
                  role: MessageRole.assistant,
                  blocks: List.from(blocks),
                ),
              );
            }
          } else if (streamEventType == 'content_block_stop') {
            // Content block completed - finalize any pending tool inputs
            final index = streamEvent['index'] as int?;
            if (index != null) {
              // Mark this block as finalized
              state.finalizedBlocks.add(index);

              // For tool_use blocks, parse the accumulated JSON
              if (state.toolUseBlocks.containsKey(index)) {
                final inputJson = state.toolUseBlocks[index]!['input_json'] as String?;
                if (inputJson != null && inputJson.isNotEmpty) {
                  try {
                    final decoded = json.decode(inputJson);
                    if (decoded is Map<String, dynamic>) {
                      state.toolUseBlocks[index]!['input'] = decoded;
                    }
                  } catch (e) {
                    print('Failed to parse tool input JSON: $e');
                    print('JSON string was: $inputJson');
                    // Keep empty input if JSON parsing fails
                  }
                }
              }

              // Rebuild and emit message with newly finalized block
              final blocks = _buildContentBlocks(
                state.contentBlockTypes,
                state.textBlocksBuilder,
                state.toolUseBlocks,
                state.finalizedBlocks,
              );

              if (blocks.isNotEmpty && currentMessageId != null) {
                yield MessageStreamEvent(
                  partialMessage: Message.fromBlocks(
                    id: currentMessageId!,
                    role: MessageRole.assistant,
                    blocks: List.from(blocks),
                  ),
                );
              }
            }
          } else if (streamEventType == 'message_stop') {
            // Message completed - emit final version
            if (currentMessageId != null && state != null && !state.finalized) {
              final blocks = _buildContentBlocks(
                state.contentBlockTypes,
                state.textBlocksBuilder,
                state.toolUseBlocks,
                state.finalizedBlocks,
              );

              if (blocks.isNotEmpty) {
                print('DEBUG SSE: ✓✓✓ EMIT FINAL at message_stop, ID: $currentMessageId ✓✓✓');
                yield MessageStreamEvent(
                  finalMessage: Message.fromBlocks(
                    id: currentMessageId!,
                    role: MessageRole.assistant,
                    blocks: blocks,
                  ),
                );
                // 切换到 FINALIZED 状态
                state.mode = _StreamingMode.finalized;
                state.finalized = true;
                print('DEBUG SSE:     → FINALIZED');
              }
            } else if (state != null && state.finalized) {
              print('DEBUG SSE: ⊘⊘⊘ SKIP message_stop (already finalized) ⊘⊘⊘');
            }
          }
        } else if (eventType == 'message') {
          final payload = event['payload'];

          // Skip stream_event payloads (already handled above)
          if (payload != null && payload['type'] == 'stream_event') {
            continue;
          }

          final payloadType = payload?['type'] as String?;
          print('DEBUG SSE: Processing message payload type: $payloadType');

          if (payload != null && payloadType == 'user') {
            // User type message (usually contains tool_result)
            print('DEBUG SSE: Processing user message (likely tool_result)');
            print('DEBUG SSE: Full user payload: ${json.encode(payload)}');

            // Extract message object and content - tool_result is inside message.content
            final message = payload['message'];
            final messageId = payload['uuid'] as String? ?? payload['id'] as String?;
            final messageContent = message != null ? message['content'] : null;
            print('DEBUG SSE: User message content type: ${messageContent.runtimeType}, content: $messageContent');

            if (messageContent is List) {
              final currentBlocks = <ContentBlock>[];
              for (var blockJson in messageContent) {
                if (blockJson is Map<String, dynamic>) {
                  try {
                    final block = ContentBlock.fromJson(blockJson);
                    currentBlocks.add(block);
                    print('DEBUG SSE: Parsed content block type: ${block.type}');
                  } catch (e) {
                    print('DEBUG SSE: Failed to parse content block: $e');
                    // Skip invalid blocks
                  }
                }
              }

              if (currentBlocks.isNotEmpty) {
                // Tool results are marked as 'user' by backend, but should be displayed as assistant messages
                final hasOnlyToolResults = currentBlocks.every((block) => block.type == ContentBlockType.toolResult);
                final messageRole = hasOnlyToolResults ? MessageRole.assistant : MessageRole.user;
                print('DEBUG SSE: Emitting user message with ${currentBlocks.length} blocks, role: $messageRole');

                final fallbackId = messageId ?? 'user_${DateTime.now().millisecondsSinceEpoch}';
                yield MessageStreamEvent(
                  finalMessage: Message.fromBlocks(
                    id: fallbackId,
                    role: messageRole,
                    blocks: List.from(currentBlocks),
                  ),
                );
              } else {
                print('DEBUG SSE: No content blocks parsed from user message');
              }
            } else {
              print('DEBUG SSE: User message content is not a List');
            }
          } else if (payload != null && payloadType == 'assistant') {
            // Complete message received - only use if no streaming occurred
            final messageId = payload['id'] as String?;

            // Skip if we have any messages built via streaming
            // Check if this specific message was already finalized
            if (messageId != null && messageStates.containsKey(messageId)) {
              final state = messageStates[messageId];
              if (state != null && state.finalized) {
                print('DEBUG SSE: Skipping duplicate assistant message $messageId (already finalized)');
                continue;
              }
            }

            // Also skip if any streaming has occurred (for messages without ID)
            if (messageStates.isNotEmpty) {
              print('DEBUG SSE: Skipping assistant message (streaming occurred)');
              continue;
            }

            // Fallback for truly non-streaming responses (rare)
            final messageContent = payload['content'];
            if (messageContent is List) {
              final currentBlocks = <ContentBlock>[];
              for (var blockJson in messageContent) {
                if (blockJson is Map<String, dynamic>) {
                  try {
                    final block = ContentBlock.fromJson(blockJson);
                    currentBlocks.add(block);
                  } catch (e) {
                    print('DEBUG SSE: Failed to parse content block: $e');
                    // Skip invalid blocks
                  }
                }
              }

              if (currentBlocks.isNotEmpty) {
                final fallbackId = messageId ?? '${sessionId}_${DateTime.now().millisecondsSinceEpoch}';
                print('DEBUG SSE: ✓✓✓ EMIT FINAL non-streaming assistant, ID: $fallbackId ✓✓✓');
                yield MessageStreamEvent(
                  finalMessage: Message.fromBlocks(
                    id: fallbackId,
                    role: MessageRole.assistant,
                    blocks: List.from(currentBlocks),
                  ),
                );
              }
            }
          } else if (payload != null && payloadType == 'result') {
            // ResultMessage: 提取统计信息
            final stats = MessageStats.fromResultPayload(payload);
            // 发送统计信息
            yield MessageStreamEvent(
              stats: stats,
            );
          } else if (payload != null && payloadType != null) {
            // 其他未知类型的消息（如 cost_report 等）
            // 记录日志但不处理，避免崩溃
            print('DEBUG SSE: Ignoring unhandled message payload type: $payloadType');
            // 可以根据需要添加对特定类型的处理
          }
        } else if (eventType == 'done') {
          print('DEBUG SSE: === Event 5: done ===');

          // Stream completed - only flush tokens if in TOKEN_MODE
          if (currentMessageId != null) {
            final state = messageStates[currentMessageId];

            if (state != null) {
              if (state.finalized) {
                print('DEBUG SSE: ⊘ Done event, already finalized');
              } else if (state.mode == _StreamingMode.streamEventMode) {
                print('DEBUG SSE: ⊘ Done event, in STREAM_EVENT_MODE (message_stop already finalized)');
                // message_stop should have already finalized, but just in case:
                state.mode = _StreamingMode.finalized;
                state.finalized = true;
              } else if (state.mode == _StreamingMode.tokenMode && tokenBuffer.isNotEmpty) {
                // Flush remaining tokens in TOKEN_MODE
                print('DEBUG SSE: → Flushing remaining tokens in TOKEN_MODE');

                if (!state.textBlocksBuilder.containsKey(0)) {
                  state.textBlocksBuilder[0] = StringBuffer();
                  state.contentBlockTypes[0] = 'text';
                }
                state.textBlocksBuilder[0]!.write(tokenBuffer.toString());
                tokenBuffer.clear();

                final blocks = _buildContentBlocks(
                  state.contentBlockTypes,
                  state.textBlocksBuilder,
                  state.toolUseBlocks,
                  state.finalizedBlocks,
                );

                if (blocks.isNotEmpty) {
                  print('DEBUG SSE: ✓✓✓ EMIT FINAL at done (TOKEN_MODE), ID: $currentMessageId ✓✓✓');
                  yield MessageStreamEvent(
                    finalMessage: Message.fromBlocks(
                      id: currentMessageId!,
                      role: MessageRole.assistant,
                      blocks: blocks,
                    ),
                  );
                  state.mode = _StreamingMode.finalized;
                  state.finalized = true;
                  print('DEBUG SSE:     → FINALIZED');
                }
              }
            }
          }

          print('DEBUG SSE: ✓ Stream done');
          yield MessageStreamEvent(isDone: true);
          return;
        } else if (eventType == 'error') {
          yield MessageStreamEvent(
            error: event['message']?.toString() ?? 'Unknown error',
            isDone: true,
          );
          return;
        }
      }

      // Fallback: if stream ends without 'done' event (shouldn't happen normally)
      yield MessageStreamEvent(isDone: true);
    } catch (e) {
      // More detailed error logging
      print('Stream error: $e');
      yield MessageStreamEvent(
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

    // Get all indices and sort them
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
        // Only include tool_use blocks that have been finalized
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
      // tool_result blocks are now emitted as separate messages immediately in content_block_start
      // so we don't include them in _buildContentBlocks to avoid duplication
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
          } else if (item['type'] == 'tool_use') {
            // Format tool use for display
            buffer.write('\n[Tool: ${item['name']}]\n');
          } else if (item['type'] == 'tool_result') {
            // Format tool result for display
            buffer.write('\n[Result]\n');
          }
        }
      }
      return buffer.toString();
    }

    return '';
  }

  @override
  Future<ClaudeUserSettings> getUserSettings(String userId) async {
    try {
      final data = await _apiService.getUserSettings(userId);
      return ClaudeUserSettings.fromJson({
        'user_id': userId,
        ...data,
      });
    } catch (e) {
      // Return defaults if settings don't exist
      return ClaudeUserSettings.defaults(userId);
    }
  }

  @override
  Future<void> updateUserSettings(String userId, ClaudeUserSettings settings) async {
    await _apiService.updateUserSettings(userId, settings.toJson());
  }

  // 停止运行中的任务
  Future<void> stopChat(String runId) async {
    await _apiService.stopChat(runId);
  }
}
