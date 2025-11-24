import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../models/message.dart';
import '../models/session.dart';
import '../models/session_settings.dart';
import '../models/codex_user_settings.dart';
import '../widgets/message_bubble.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/panel_theme.dart';
import '../core/utils/platform_helper.dart';
import '../repositories/api_codex_repository.dart';
import '../repositories/session_repository.dart';
import '../services/session_settings_service.dart';
import '../services/app_settings_service.dart';
import 'session_settings_screen.dart';
import 'codex_session_settings_screen.dart';

class ChatScreen extends StatefulWidget {
  final Session session;
  final dynamic repository; // Supports both SessionRepository and CodexRepository
  final VoidCallback? onMessageComplete; // 消息完成回调，用于通知标签页
  final ValueNotifier<bool>? hasNewReplyNotifier; // 新回复通知器，用于显示AppBar提示
  final VoidCallback? onBack; // 返回按钮回调，用于返回项目列表

  const ChatScreen({
    super.key,
    required this.session,
    required this.repository,
    this.onMessageComplete,
    this.hasNewReplyNotifier,
    this.onBack,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with AutomaticKeepAliveClientMixin {
  final List<Message> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode(); // 输入框焦点节点
  final ImagePicker _imagePicker = ImagePicker();
  bool _isLoading = false;
  bool _isSending = false;
  SessionSettings? _settings;
  CodexUserSettings? _codexSettings; // Codex 设置（仅当使用 Codex 时）
  MessageStats? _lastMessageStats; // 最后一条消息的统计信息
  bool _showStats = false; // 是否显示统计信息
  bool _userScrolling = false; // 用户是否正在手动滚动
  late Session _currentSession; // 当前session，可能在第一次发送消息时更新
  String? _currentRunId; // 当前运行的任务ID（用于停止任务，仅限 Claude Code）

  // Image attachments
  final List<File> _selectedImages = [];
  final List<String> _imageBase64List = [];
  bool _sessionProcessing = false; // 会话是否正在处理中（用于持续对话功能）

  // 节流相关 - 优化流式传输UI更新
  DateTime? _lastUpdateTime;
  bool _pendingUpdate = false;

  // 消息导航相关
  int _currentUserMessageIndex = -1; // 当前定位到的用户消息索引（从下往上数）

  // 消息分页加载相关
  List<Message> _allMessages = []; // 所有消息（后端返回的完整列表）
  static const int _initialMessageCount = 100; // 初始加载的消息数量
  static const int _loadMoreCount = 50; // 每次加载更多的数量
  bool _hasMoreMessages = false; // 是否有更多历史消息
  bool _isLoadingMore = false; // 是否正在加载更多
  double _messagesOpacity = 0.0; // 消息列表透明度（用于淡入动画）

  // 斜杠命令相关
  bool _showCommandSuggestions = false; // 是否显示命令建议
  String _commandQuery = ''; // 当前的命令查询
  final LayerLink _layerLink = LayerLink(); // 用于定位建议框
  OverlayEntry? _commandOverlay; // 命令建议的 overlay

  // 临时写死的命令列表（后续会从接口获取）
  final List<Map<String, String>> _availableCommands = [
    {'name': '/compact', 'description': '简短对话,可选重点说明'},
    {'name': '/context', 'description': '将当前上下文使用情况可视化为彩色网格'},
    {'name': '/cost', 'description': '显示代币使用统计信息'},
    {'name': '/init', 'description': '使用 CLAUDE.md 指南初始化项目'},
    {'name': '/pr-comments', 'description': '查看拉取请求评论'},
    {'name': '/release-notes', 'description': '生成版本发布说明'},
    {'name': '/todos', 'description': '列出当前待办事项'},
    {'name': '/review', 'description': '请求代码审查'},
    {'name': '/security-review', 'description': '进行安全审查'},
  ];

  // 获取最终的 hideToolCalls 设置（优先使用全局设置）
  bool get _effectiveHideToolCalls {
    final appSettingsService = AppSettingsService();
    final globalHideToolCalls = appSettingsService.hideToolCalls;

    // 全局设置优先
    if (globalHideToolCalls) {
      return true;
    }

    // 否则使用会话设置
    if (widget.repository is ApiCodexRepository) {
      return _codexSettings?.hideToolCalls ?? false;
    } else {
      return _settings?.hideToolCalls ?? false;
    }
  }

  @override
  bool get wantKeepAlive => true; // 保持状态，防止切换标签时丢失消息

  @override
  void initState() {
    super.initState();
    _currentSession = widget.session; // 初始化为widget的session
    _loadSavedSettings(); // 加载保存的设置
    // 监听用户手动滚动
    _scrollController.addListener(_onScroll);
    // 监听输入框文本变化
    _textController.addListener(_onTextChanged);
    _loadMessages();
    _loadCodexSettingsIfNeeded();
  }

  @override
  void didUpdateWidget(ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 检查是否切换到了不同的 session
    // 使用对象引用比较，因为新对话的 ID 都可能是空字符串
    if (oldWidget.session != widget.session) {
      print('DEBUG ChatScreen: Session changed from ${oldWidget.session.id} to ${widget.session.id}');
      _currentSession = widget.session;
      // 清空状态
      _currentRunId = null;
      _isSending = false;
      _sessionProcessing = false;
      _lastMessageStats = null;
      _showStats = false;
      _currentUserMessageIndex = -1;
      _messagesOpacity = 1.0; // 重置透明度
      // 重新加载设置和消息
      _loadSavedSettings();
      _loadMessages();
      _loadCodexSettingsIfNeeded();
    }
  }

  // 加载保存的设置
  Future<void> _loadSavedSettings() async {
    final settingsService = SessionSettingsService();
    await settingsService.initialize();

    if (widget.repository is ApiCodexRepository) {
      // 加载 Codex 设置
      final savedSettings = settingsService.getCodexSessionSettings(widget.session.id);
      if (savedSettings != null && mounted) {
        setState(() {
          _codexSettings = savedSettings;
        });
        print('DEBUG: Loaded Codex settings from local storage for session ${widget.session.id}');
      } else {
        // 如果没有保存的设置，使用全局默认 Codex 设置
        final appSettingsService = AppSettingsService();
        await appSettingsService.initialize();
        final codexRepo = widget.repository as ApiCodexRepository;
        final userId = codexRepo.apiService.authService?.username ?? 'default';
        final defaultSettings = appSettingsService.getOrCreateCodexSettings(userId);

        if (mounted) {
          setState(() {
            _codexSettings = defaultSettings;
          });
        }
        print('DEBUG: Using global default Codex settings for session ${widget.session.id}: skipGitRepoCheck=${defaultSettings.skipGitRepoCheck}');
      }
    } else {
      // 加载 Claude Code 设置
      final savedSettings = settingsService.getClaudeSessionSettings(widget.session.id);
      if (savedSettings != null) {
        _settings = savedSettings;
      } else {
        // 如果没有保存的设置，尝试使用全局默认项目设置
        final appSettingsService = AppSettingsService();
        await appSettingsService.initialize();
        final defaultSettings = appSettingsService.getDefaultSessionSettingsForNewSession(
          widget.session.id,
          widget.session.cwd,
        );

        _settings = defaultSettings ?? SessionSettings(
          sessionId: widget.session.id,
          cwd: widget.session.cwd,
        );
      }
    }
  }

  Future<void> _loadCodexSettingsIfNeeded() async {
    if (widget.repository is ApiCodexRepository) {
      // 注意：这个方法现在的作用是从后端 API 同步用户的全局设置
      // _loadSavedSettings() 已经加载了本地设置或全局默认设置
      // 这里我们不再从后端重新加载，避免覆盖用户在全局设置中的配置
      // 后端的设置应该通过全局设置界面同步到 AppSettingsService
      print('DEBUG: Codex settings loaded from local/global storage, skipping backend API load');
    }
  }

  void _onScroll() {
    // 检测用户是否在底部附近
    if (_scrollController.hasClients) {
      final isAtBottom = _scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 50;
      if (isAtBottom && _userScrolling) {
        setState(() => _userScrolling = false);
      }
    }
  }

  // 节流更新UI - 每100ms最多更新一次
  void _throttledUpdate() {
    final now = DateTime.now();
    final shouldUpdate = _lastUpdateTime == null ||
        now.difference(_lastUpdateTime!) >= const Duration(milliseconds: 100);

    if (shouldUpdate) {
      _lastUpdateTime = now;
      _pendingUpdate = false;
      if (mounted) {
        setState(() {}); // 触发UI重建
      }
    } else if (!_pendingUpdate) {
      _pendingUpdate = true;
      // 延迟更新
      final delay = const Duration(milliseconds: 100) -
          now.difference(_lastUpdateTime!);
      Future.delayed(delay, () {
        if (mounted && _pendingUpdate) {
          _lastUpdateTime = DateTime.now();
          _pendingUpdate = false;
          setState(() {});
        }
      });
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      // 只有当用户向上滚动超过一定距离时才打断自动滚动
      if (notification.scrollDelta != null && notification.scrollDelta! < -10) {
        // 向上滚动超过10像素（scrollDelta 为负数）
        if (_scrollController.hasClients) {
          final distanceFromBottom = _scrollController.position.maxScrollExtent -
                                     _scrollController.position.pixels;
          // 只有当离底部超过100像素时才认为用户想查看历史消息
          if (distanceFromBottom > 100 && !_userScrolling) {
            setState(() => _userScrolling = true);
          }
        }
      }

      // 当滚动到接近顶部时，加载更多历史消息
      if (_scrollController.hasClients && _hasMoreMessages && !_isLoadingMore) {
        final scrollPosition = _scrollController.position.pixels;
        // 当距离顶部小于200像素时触发加载
        if (scrollPosition < 200) {
          _loadMoreMessages();
        }
      }
    }
    return false;
  }

  Future<void> _loadMessages() async {
    // 如果session id为空，说明是新session，跳过加载消息
    if (widget.session.id.isEmpty) {
      print('DEBUG ChatScreen: Session ID is empty, skipping message load');
      if (!mounted) return;
      setState(() {
        _messages.clear(); // 清空旧消息列表
        _allMessages.clear(); // 清空所有消息
        _hasMoreMessages = false;
        _isLoading = false;
        _messagesOpacity = 1.0; // 重置透明度为完全可见
      });
      return;
    }

    print('DEBUG ChatScreen: Loading messages for session ${widget.session.id}');
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final messages = await widget.repository.getSessionMessages(widget.session.id);
      print('DEBUG ChatScreen: Loaded ${messages.length} messages');

      // 检查组件是否还在树中
      if (!mounted) return;

      // 保存所有消息
      _allMessages = messages;

      // 只显示最后 _initialMessageCount 条消息
      final displayMessages = messages.length > _initialMessageCount
          ? messages.sublist(messages.length - _initialMessageCount)
          : messages;

      setState(() {
        _messages.clear();
        _messages.addAll(displayMessages);
        _hasMoreMessages = messages.length > _initialMessageCount;
        _isLoading = false;
        _messagesOpacity = 0.0; // 初始透明
      });

      print('DEBUG ChatScreen: Displaying ${_messages.length} messages, hasMore: $_hasMoreMessages');

      // 确保在消息加载后滚动到底部，使用 jumpTo 直接跳转
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToBottomImmediate();
        // 触发淡入动画
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted) {
            setState(() {
              _messagesOpacity = 1.0;
            });
          }
        });
      });
      // 延迟再次确保滚动到底部（给更长时间让消息渲染完成）
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _scrollToBottomImmediate();
        }
      });
    } catch (e) {
      print('DEBUG ChatScreen: Error loading messages: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  // 加载更多历史消息（当用户滚动到顶部时触发）
  void _loadMoreMessages() {
    if (_isLoadingMore || !_hasMoreMessages || !mounted) return;

    setState(() => _isLoadingMore = true);

    // 短暂延迟让加载动画显示
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;

      // 计算还有多少消息未显示
      final hiddenCount = _allMessages.length - _messages.length;
      if (hiddenCount <= 0) {
        setState(() {
          _isLoadingMore = false;
          _hasMoreMessages = false;
        });
        return;
      }

      // 计算要加载的消息
      final loadCount = hiddenCount > _loadMoreCount ? _loadMoreCount : hiddenCount;
      final startIndex = hiddenCount - loadCount;
      final moreMessages = _allMessages.sublist(startIndex, startIndex + loadCount);

      // 在插入消息前保存滚动位置
      final currentScrollOffset = _scrollController.position.pixels;
      final currentMaxExtent = _scrollController.position.maxScrollExtent;

      setState(() {
        // 在列表开头插入更多消息
        _messages.insertAll(0, moreMessages);
        _hasMoreMessages = startIndex > 0;
        _isLoadingMore = false;
      });

      print('DEBUG ChatScreen: Loaded $loadCount more messages, total displaying: ${_messages.length}, hasMore: $_hasMoreMessages');

      // 恢复滚动位置 - 保持用户看到的内容不变
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          final newMaxExtent = _scrollController.position.maxScrollExtent;
          final addedHeight = newMaxExtent - currentMaxExtent;
          // 将滚动位置向下移动，补偿新增内容的高度
          _scrollController.jumpTo(currentScrollOffset + addedHeight);
        }
      });
    });
  }

  // 刷新当前对话
  Future<void> _refreshCurrentSession() async {
    if (_isLoading || _isSending) {
      print('DEBUG ChatScreen: Already loading or sending, skipping refresh');
      return;
    }

    print('DEBUG ChatScreen: Refreshing session ${widget.session.id}');

    // 重新加载消息
    await _loadMessages();

    // 显示刷新成功提示
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('对话已刷新'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
        ),
      );
    }
  }

  // Pick images from gallery or camera
  Future<void> _pickImages() async {
    try {
      final List<XFile> images = await _imagePicker.pickMultiImage(
        imageQuality: 85,
      );

      if (images.isNotEmpty) {
        for (var image in images) {
          final file = File(image.path);
          final bytes = await file.readAsBytes();
          final base64 = base64Encode(bytes);

          setState(() {
            _selectedImages.add(file);
            _imageBase64List.add(base64);
          });
        }
      }
    } catch (e) {
      print('DEBUG: Error picking images: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择图片失败: $e')),
        );
      }
    }
  }

  // Pick single image from camera
  Future<void> _pickImageFromCamera() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (image != null) {
        final file = File(image.path);
        final bytes = await file.readAsBytes();
        final base64 = base64Encode(bytes);

        setState(() {
          _selectedImages.add(file);
          _imageBase64List.add(base64);
        });
      }
    } catch (e) {
      print('DEBUG: Error picking image from camera: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('拍照失败: $e')),
        );
      }
    }
  }

  // Remove selected image
  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
      _imageBase64List.removeAt(index);
    });
  }

  // Clear all images
  void _clearImages() {
    setState(() {
      _selectedImages.clear();
      _imageBase64List.clear();
    });
  }

  // Get media type from file extension
  String _getMediaType(String path) {
    final ext = path.toLowerCase().split('.').last;
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  Future<void> _handleSubmit(String text) async {
    // 隐藏命令建议（如果正在显示）
    if (_showCommandSuggestions) {
      _hideCommandSuggestions();
    }

    // 允许只发送图片（文本可以为空）
    if (text.trim().isEmpty && _selectedImages.isEmpty) return;

    // 对于 Claude Code，支持持续消息传递（在流式响应中发送新消息）
    // 注意：_sessionProcessing 标记会话是否在处理，现在允许在处理中发送新消息
    // 新消息会被注入到当前活动的流中

    // 对于 Codex，仍然阻止在发送中再次发送
    if (_isSending && widget.repository is ApiCodexRepository) {
      return;
    }

    // 构建content blocks（包括文本和图片）
    final List<ContentBlock> contentBlocks = [];

    // 添加图片blocks
    for (int i = 0; i < _selectedImages.length; i++) {
      final mediaType = _getMediaType(_selectedImages[i].path);
      contentBlocks.add(ContentBlock.image(
        base64Data: _imageBase64List[i],
        mediaType: mediaType,
      ));
    }

    // 添加文本block（如果有文本）
    if (text.trim().isNotEmpty) {
      contentBlocks.add(ContentBlock(
        type: ContentBlockType.text,
        text: text,
      ));
    }

    // 创建用户消息
    final userMessage = Message.fromBlocks(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: MessageRole.user,
      blocks: contentBlocks,
    );

    setState(() {
      _messages.add(userMessage);
      _isSending = true;
      _sessionProcessing = true; // 标记会话开始处理
      _userScrolling = false; // 重置手动滚动标志，确保新消息能自动滚动
    });
    print('DEBUG: Added user message, total messages: ${_messages.length}, opacity: $_messagesOpacity');
    _textController.clear();
    _clearImages(); // 清空选中的图片
    _scrollToBottom();

    // Track current assistant message by ID (for multi-turn support)
    final assistantMessagesByIdIndex = <String, int>{}; // message.id -> index in _messages

    try {
      // 如果session id为空，传null让API创建新session
      final sessionIdToUse = _currentSession.id.isEmpty ? null : _currentSession.id;
      bool sessionIdUpdated = false; // 标记是否已更新session id

      // 根据 repository 类型调用不同的 sendMessageStream
      final Stream<dynamic> eventStream;
      if (widget.repository is ApiCodexRepository) {
        // Codex 使用 codexSettings (暂不支持图片)
        final codexRepo = widget.repository as ApiCodexRepository;

        // 确保有 Codex 设置，如果没有则使用默认设置
        CodexUserSettings settings = _codexSettings ?? CodexUserSettings.defaults(
          codexRepo.apiService.authService?.username ?? 'default'
        );

        // 检查是否禁用了 Git 仓库检查跳过
        if (!settings.skipGitRepoCheck) {
          // 显示错误提示，不发送消息
          if (mounted) {
            setState(() {
              _isSending = false;
              _sessionProcessing = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('发送失败：未开启"跳过 Git 检查"选项。\n请在 Codex 设置中启用此选项后重试。'),
                duration: const Duration(seconds: 5),
                behavior: SnackBarBehavior.floating,
                margin: EdgeInsets.only(
                  top: 16,
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(context).size.height - 100,
                ),
              ),
            );
          }
          return; // 不继续发送消息
        }

        print('DEBUG: Sending Codex message with settings: skipGitRepoCheck=${settings.skipGitRepoCheck}, approvalPolicy=${settings.approvalPolicy}, sandboxMode=${settings.sandboxMode}');

        eventStream = codexRepo.sendMessageStream(
          sessionId: sessionIdToUse,
          content: text,
          cwd: _currentSession.cwd,
          codexSettings: settings,
        );
      } else {
        // Claude Code - 支持图片，发送 contentBlocks
        final claudeRepo = widget.repository as SessionRepository;
        eventStream = claudeRepo.sendMessageStream(
          sessionId: sessionIdToUse,
          contentBlocks: contentBlocks,  // 发送 content blocks（包含图片）
          cwd: _currentSession.cwd,
          settings: _settings,
        );
      }

      await for (var event in eventStream) {
        // 捕获新创建的session ID
        if (event.sessionId != null && event.sessionId!.isNotEmpty) {
          if (_currentSession.id.isEmpty && !sessionIdUpdated) {
            // 更新本地session对象
            _currentSession = Session(
              id: event.sessionId!,
              projectId: _currentSession.projectId,
              title: _currentSession.title,
              name: _currentSession.name,
              cwd: _currentSession.cwd,
              createdAt: _currentSession.createdAt,
              updatedAt: DateTime.now(),
              messageCount: _currentSession.messageCount,
            );
            sessionIdUpdated = true;
            print('DEBUG: Updated session ID to ${event.sessionId}');
          }
        }

        // 捕获 run_id（用于停止任务，仅限 Claude Code）
        // Codex 的事件没有 runId 属性，需要先检查
        if (widget.repository is! ApiCodexRepository) {
          // 只有 Claude Code 才有 runId
          final messageEvent = event as MessageStreamEvent;
          if (messageEvent.runId != null && messageEvent.runId!.isNotEmpty) {
            if (mounted) {
              setState(() {
                _currentRunId = messageEvent.runId;
              });
              print('DEBUG: Captured run_id: ${messageEvent.runId}');
            }
          }
        }

        if (event.error != null) {
          if (mounted) {
            setState(() {
              // 如果有 run_id，说明任务已经在后台运行，保持 _isSending 状态让用户可以停止
              // 如果没有 run_id，说明任务还没开始，可以完全重置状态
              if (_currentRunId == null || _currentRunId!.isEmpty) {
                _isSending = false;
                _sessionProcessing = false;
              }
              // 如果有 run_id，不清除它，让用户可以通过停止按钮取消
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('发送失败: ${event.error}'),
                behavior: SnackBarBehavior.floating,
                margin: EdgeInsets.only(
                  top: 16,
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(context).size.height - 100,
                ),
              ),
            );
          }
          return;
        }

        if (event.stats != null) {
          // 保存统计信息
          if (mounted) {
            setState(() {
              _lastMessageStats = event.stats;
              _showStats = true; // 自动显示统计信息
            });
          }
        }

        if (event.partialMessage != null) {
          final partial = event.partialMessage!;
          final messageId = partial.id;

          // 先检查局部map，再检查全局_messages列表（处理持续对话场景）
          int? existingIndex = assistantMessagesByIdIndex[messageId];
          if (existingIndex == null) {
            // 在_messages中查找是否已存在该消息（可能由其他并行的_handleSubmit添加）
            for (int i = _messages.length - 1; i >= 0; i--) {
              if (_messages[i].id == messageId) {
                existingIndex = i;
                assistantMessagesByIdIndex[messageId] = i; // 更新局部map
                break;
              }
            }
          }

          print('UI: ⟳ PARTIAL MSG, ID: $messageId, existingIndex: $existingIndex, total msgs: ${_messages.length}');

          if (existingIndex != null) {
            // Update existing message
            print('UI:   → UPDATE at index $existingIndex');
            if (existingIndex >= 0 &&
                existingIndex < _messages.length &&
                _messages[existingIndex].role == MessageRole.assistant) {
              _messages[existingIndex] = partial; // 直接更新，不触发setState
              _throttledUpdate(); // 节流更新UI
            }
          } else {
            // Add new assistant message
            print('UI:   → ADD NEW at index ${_messages.length}');
            _messages.add(partial);
            assistantMessagesByIdIndex[messageId] = _messages.length - 1;
            _throttledUpdate(); // 节流更新UI
          }
          _scrollToBottom();
        }

        if (event.finalMessage != null) {
          final final_ = event.finalMessage!;
          final messageId = final_.id;

          // 先检查局部map，再检查全局_messages列表（处理持续对话场景）
          int? existingIndex = assistantMessagesByIdIndex[messageId];
          if (existingIndex == null) {
            // 在_messages中查找是否已存在该消息（可能由其他并行的_handleSubmit添加）
            for (int i = _messages.length - 1; i >= 0; i--) {
              if (_messages[i].id == messageId) {
                existingIndex = i;
                assistantMessagesByIdIndex[messageId] = i; // 更新局部map
                break;
              }
            }
          }

          print('UI: ✓ FINAL MSG, ID: $messageId, existingIndex: $existingIndex, total msgs: ${_messages.length}');

          if (existingIndex != null) {
            // Replace with final message
            print('UI:   → REPLACE at index $existingIndex');
            if (existingIndex >= 0 &&
                existingIndex < _messages.length &&
                _messages[existingIndex].role == MessageRole.assistant) {
              if (mounted) {
                setState(() {
                  _messages[existingIndex!] = final_;
                });
              }
            }
          } else {
            // Fallback: add final message if no partial was received
            print('UI:   → ADD NEW FINAL at index ${_messages.length} (NO PARTIAL!)');
            if (mounted) {
              setState(() {
                _messages.add(final_);
                assistantMessagesByIdIndex[messageId] = _messages.length - 1;
              });
            }
          }
          _scrollToBottom();
        }

        if (event.isDone) {
          if (mounted) {
            setState(() {
              _isSending = false;
              _sessionProcessing = false; // 标记会话处理完成
              _currentRunId = null; // 清除 run_id
            });
          }
          // 消息完成，通知标签页
          widget.onMessageComplete?.call();
          return;
        }
      }

      // 如果流结束但没有收到 isDone 事件（不应该发生，但作为后备）
      if (mounted) {
        setState(() {
          _isSending = false;
          _sessionProcessing = false; // 标记会话处理完成
          _currentRunId = null; // 清除 run_id
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSending = false;
          _sessionProcessing = false; // 错误时也标记会话处理完成
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('发送失败: $e'),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              top: 16,
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).size.height - 100,
            ),
          ),
        );
      }
    }
  }

  Future<void> _handleStop() async {
    // 只有 Claude Code 支持停止功能
    if (widget.repository is ApiCodexRepository) {
      return;
    }

    // 检查是否有 run_id
    if (_currentRunId == null || _currentRunId!.isEmpty) {
      print('DEBUG: No run_id available to stop');
      return;
    }

    try {
      print('DEBUG: Stopping task with run_id: $_currentRunId');
      // 调用 repository 的 stopChat 方法
      final repository = widget.repository as dynamic;
      await repository.stopChat(_currentRunId!);

      if (mounted) {
        setState(() {
          _isSending = false;
          _sessionProcessing = false; // 停止任务后重置会话状态
          _currentRunId = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('已停止任务'),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              top: 16,
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).size.height - 100,
            ),
          ),
        );
      }
    } catch (e) {
      print('DEBUG: Failed to stop task: $e');
      if (mounted) {
        // 即使停止失败，也应该重置状态，让用户可以继续操作
        setState(() {
          _isSending = false;
          _sessionProcessing = false;
          _currentRunId = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('停止失败: $e'),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              top: 16,
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).size.height - 100,
            ),
          ),
        );
      }
    }
  }

  void _openSettings() async {
    // 检测是否为 Codex 仓库
    final isCodex = widget.repository is ApiCodexRepository;
    print('DEBUG ChatScreen._openSettings: isCodex=$isCodex, repository=${widget.repository.runtimeType}');

    final settingsService = SessionSettingsService();
    await settingsService.initialize();

    if (isCodex) {
      // 打开 Codex 设置
      print('DEBUG ChatScreen._openSettings: Opening Codex settings, _codexSettings=$_codexSettings');
      if (_codexSettings == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('正在加载 Codex 设置...'),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              top: 16,
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).size.height - 100,
            ),
          ),
        );
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CodexSessionSettingsScreen(
            settings: _codexSettings!,
            repository: widget.repository as ApiCodexRepository,
            sessionId: _currentSession.id.isNotEmpty ? _currentSession.id : null,
            cwd: _currentSession.cwd,
            onSave: (newSettings) async {
              print('DEBUG ChatScreen._openSettings: Codex settings saved: $newSettings');
              // 保存到本地持久化存储
              await settingsService.saveCodexSessionSettings(
                widget.session.id,
                newSettings,
              );
              setState(() {
                _codexSettings = newSettings;
              });
            },
          ),
        ),
      );
    } else {
      // 打开 Claude Code 设置
      print('DEBUG ChatScreen._openSettings: Opening Claude Code settings');

      // 确保 _settings 已初始化
      if (_settings == null) {
        print('ERROR: _settings is null when trying to open settings screen');
        // 创建默认设置
        _settings = SessionSettings(
          sessionId: widget.session.id,
          cwd: widget.session.cwd,
        );
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SessionSettingsScreen(
            settings: _settings!,
            onSave: (newSettings) async {
              // 保存到本地持久化存储
              await settingsService.saveClaudeSessionSettings(
                widget.session.id,
                newSettings,
              );
              setState(() {
                _settings = newSettings;
              });
            },
          ),
        ),
      );
    }
  }


  // 立即跳转到底部（无动画）
  void _scrollToBottomImmediate() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  // 平滑滚动到底部（仅在用户未手动滚动时）
  void _scrollToBottom() {
    if (_userScrolling) return; // 用户正在手动滚动，不自动滚动

    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 50), () {
        if (_scrollController.hasClients && !_userScrolling) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  // 判断消息是否是真正的用户输入消息（排除只包含工具返回结果的消息）
  bool _isRealUserMessage(Message message) {
    if (message.role != MessageRole.user) return false;

    // 检查是否包含文本内容块（不是工具返回结果）
    return message.contentBlocks.any((block) =>
      block.type == ContentBlockType.text &&
      (block.text?.trim().isNotEmpty ?? false)
    );
  }

  // 导航到上一条用户消息（向上）
  void _navigateToPreviousUserMessage() {
    // 找到所有真正的用户消息的索引（排除只有工具返回结果的）
    final userMessageIndices = <int>[];
    for (int i = 0; i < _messages.length; i++) {
      if (_isRealUserMessage(_messages[i])) {
        userMessageIndices.add(i);
      }
    }

    if (userMessageIndices.isEmpty) return;

    // 从当前索引向上找（索引减小）
    if (_currentUserMessageIndex == -1) {
      // 首次点击，从最后一条用户消息开始
      _currentUserMessageIndex = userMessageIndices.length - 1;
    } else if (_currentUserMessageIndex > 0) {
      _currentUserMessageIndex--;
    } else {
      // 已经在第一条，循环到最后一条
      _currentUserMessageIndex = userMessageIndices.length - 1;
    }

    final targetIndex = userMessageIndices[_currentUserMessageIndex];
    _scrollToMessageByIndex(targetIndex);
  }

  // 导航到下一条用户消息（向下）
  void _navigateToNextUserMessage() {
    // 找到所有真正的用户消息的索引（排除只有工具返回结果的）
    final userMessageIndices = <int>[];
    for (int i = 0; i < _messages.length; i++) {
      if (_isRealUserMessage(_messages[i])) {
        userMessageIndices.add(i);
      }
    }

    if (userMessageIndices.isEmpty) return;

    // 从当前索引向下找（索引增大）
    if (_currentUserMessageIndex == -1) {
      // 首次点击，从第一条用户消息开始
      _currentUserMessageIndex = 0;
    } else if (_currentUserMessageIndex < userMessageIndices.length - 1) {
      _currentUserMessageIndex++;
    } else {
      // 已经在最后一条，循环到第一条
      _currentUserMessageIndex = 0;
    }

    final targetIndex = userMessageIndices[_currentUserMessageIndex];
    _scrollToMessageByIndex(targetIndex);
  }

  // 根据消息索引计算并滚动到对应位置（让目标消息显示在屏幕底部）
  void _scrollToMessageByIndex(int messageIndex) {
    if (!_scrollController.hasClients) return;

    // 估算每条消息的平均高度
    const double estimatedMessageHeight = 150.0;

    // 获取屏幕可见高度
    final viewportHeight = _scrollController.position.viewportDimension;

    // 计算目标消息的估算位置
    final targetMessagePosition = messageIndex * estimatedMessageHeight;

    // 计算滚动位置：让目标消息出现在屏幕底部
    // targetMessagePosition 是消息顶部的位置
    // 我们希望消息底部对齐到屏幕底部，所以需要加上消息高度再减去viewport高度
    final scrollPosition = (targetMessagePosition + estimatedMessageHeight - viewportHeight)
        .clamp(0.0, _scrollController.position.maxScrollExtent);

    // 滚动到目标位置
    _scrollController.animateTo(
      scrollPosition,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须调用以保持状态
    return PopScope(
      canPop: widget.onBack == null, // 如果有 onBack 回调，不允许默认 pop
      onPopInvoked: (didPop) {
        // 如果已经 pop 了（使用默认行为），不需要再处理
        if (didPop) return;

        // 如果有 onBack 回调，使用回调
        if (widget.onBack != null) {
          widget.onBack!();
        }
      },
      child: Scaffold(
        backgroundColor: PanelTheme.backgroundColor(context),
        appBar: AppBar(
          leading: widget.onBack != null
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: widget.onBack,
                  tooltip: '返回项目列表',
                )
              : null,
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.session.name),
                  Text(
                    widget.session.cwd,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                      color: context.appColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            // 显示新回复提示圆点或发送中指示器
            if (widget.hasNewReplyNotifier != null)
              ValueListenableBuilder<bool>(
                valueListenable: widget.hasNewReplyNotifier!,
                builder: (context, hasNewReply, child) {
                  if (hasNewReply || _isSending) {
                    final primaryColor = Theme.of(context).colorScheme.primary;
                    return Container(
                      margin: const EdgeInsets.only(left: 8),
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _isSending
                            ? primaryColor.withOpacity(0.8)
                            : primaryColor,
                        shape: BoxShape.circle,
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              )
            else if (_isSending)
              Builder(
                builder: (context) {
                  return Container(
                    margin: const EdgeInsets.only(left: 8),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.8),
                      shape: BoxShape.circle,
                    ),
                  );
                },
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshCurrentSession,
            tooltip: '刷新对话',
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
            tooltip: '会话设置',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isLoading)
            const LinearProgressIndicator()
          else
            Container(height: 4),
          // 持续消息状态横幅
          if (_sessionProcessing)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.repository is ApiCodexRepository
                          ? 'Codex 正在回复中...'
                          : 'Claude 正在回复中... 您可以随时补充信息或提出新问题',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.appColors.textSecondary,
                      ),
                    ),
                  ),
                  if (_currentRunId != null)
                    TextButton(
                      onPressed: _handleStop,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('停止', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ),
          Expanded(
            child: _messages.isEmpty && !_isLoading
                ? _buildEmptyState()
                : _messages.isEmpty && _isLoading
                    ? _buildLoadingState()
                    : AnimatedOpacity(
                        opacity: _messagesOpacity,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                        child: Stack(
                          children: [
                            // 桌面版使用SelectionArea包装，允许自由选择文本
                            PlatformHelper.shouldEnableTextSelection
                                ? Listener(
                                    onPointerDown: (_) {
                                      // 点击消息区域时，让输入框失去焦点，以便SelectionArea可以选择文本
                                      _inputFocusNode.unfocus();
                                    },
                                    child: SelectionArea(
                                    child: NotificationListener<ScrollNotification>(
                                      onNotification: _handleScrollNotification,
                                      child: ListView.builder(
                                  controller: _scrollController,
                                  physics: PlatformHelper.getScrollPhysics(),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  itemCount: _messages.length + (_isLoadingMore || _hasMoreMessages ? 1 : 0),
                                  cacheExtent: 1000, // 增加缓存范围，减少重建
                                  addAutomaticKeepAlives: true, // 保持已构建的item
                                  addRepaintBoundaries: true, // 添加重绘边界，隔离重绘
                                  itemBuilder: (context, index) {
                                    // 第一个item显示加载指示器
                                    if ((_isLoadingMore || _hasMoreMessages) && index == 0) {
                                      return _buildLoadMoreIndicator();
                                    }
                                    final messageIndex = (_isLoadingMore || _hasMoreMessages) ? index - 1 : index;
                                    return RepaintBoundary(
                                      child: MessageBubble(
                                        key: ValueKey(_messages[messageIndex].id),
                                        message: _messages[messageIndex],
                                        hideToolCalls: _effectiveHideToolCalls,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          )
                          : NotificationListener<ScrollNotification>(
                              onNotification: _handleScrollNotification,
                              child: ListView.builder(
                                controller: _scrollController,
                                physics: PlatformHelper.getScrollPhysics(),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                itemCount: _messages.length + (_isLoadingMore || _hasMoreMessages ? 1 : 0),
                                cacheExtent: 1000, // 增加缓存范围，减少重建
                                addAutomaticKeepAlives: true, // 保持已构建的item
                                addRepaintBoundaries: true, // 添加重绘边界，隔离重绘
                                itemBuilder: (context, index) {
                                  // 第一个item显示加载指示器
                                  if ((_isLoadingMore || _hasMoreMessages) && index == 0) {
                                    return _buildLoadMoreIndicator();
                                  }
                                  final messageIndex = (_isLoadingMore || _hasMoreMessages) ? index - 1 : index;
                                  return RepaintBoundary(
                                    child: MessageBubble(
                                      key: ValueKey(_messages[messageIndex].id),
                                      message: _messages[messageIndex],
                                      hideToolCalls: _effectiveHideToolCalls,
                                    ),
                                  );
                                },
                              ),
                            ),
                            // 消息导航按钮（在右下角）- 暂时禁用
                            // if (_messages.where((m) => _isRealUserMessage(m)).length > 1)
                            //   _buildMessageNavigationButtons(),
                            // 滚动到底部按钮
                            if (_userScrolling) _buildScrollToBottomButton(),
                            // 浮动模式指示器
                            _buildModeIndicator(),
                          ],
                        ),
                      ),
          ),
          if (_lastMessageStats != null) _buildStatsPanel(),
          _buildInputArea(),
        ],
      ), // body: Column 结束
    ), // Scaffold 结束
  ); // PopScope 结束
  }

  Widget _buildStatsPanel() {
    final stats = _lastMessageStats!;
    final appColors = context.appColors;
    final dividerColor = Theme.of(context).dividerColor;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: _showStats ? null : 0,
      child: _showStats
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: appColors.toolBackground.withOpacity(0.3),
                border: Border(
                  top: BorderSide(color: dividerColor, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        _buildStatChip(
                          icon: Icons.token,
                          label: '${stats.totalTokens} tokens',
                          tooltip: 'Input: ${stats.inputTokens ?? 0}, Output: ${stats.outputTokens ?? 0}',
                        ),
                        _buildStatChip(
                          icon: Icons.schedule,
                          label: stats.formattedDuration,
                          tooltip: 'API: ${(stats.durationApiMs / 1000).toStringAsFixed(1)}s',
                        ),
                        if (stats.costUsd != null)
                          _buildStatChip(
                            icon: Icons.attach_money,
                            label: stats.formattedCost,
                          ),
                        if (stats.numTurns > 1)
                          _buildStatChip(
                            icon: Icons.refresh,
                            label: '${stats.numTurns} 轮',
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _showStats ? Icons.expand_more : Icons.expand_less,
                      size: 20,
                    ),
                    onPressed: () {
                      setState(() {
                        _showStats = !_showStats;
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    String? tooltip,
  }) {
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
    final dividerColor = Theme.of(context).dividerColor;
    final textSecondary = context.appColors.textSecondary;

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: textSecondary,
            ),
          ),
        ],
      ),
    );

    if (tooltip != null) {
      return Tooltip(
        message: tooltip,
        child: chip,
      );
    }
    return chip;
  }

  Widget _buildMessageNavigationButtons() {
    final appColors = context.appColors;
    final cardColor = Theme.of(context).cardColor;
    final dividerColor = Theme.of(context).dividerColor;

    return Positioned(
      right: 16,
      bottom: 88, // 在滚动到底部按钮上方
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 向上按钮（跳转到上一条用户消息）
          Container(
            decoration: BoxDecoration(
              color: cardColor.withOpacity(0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: dividerColor.withOpacity(0.5),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _navigateToPreviousUserMessage,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 32,
                  height: 48,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.arrow_upward,
                    color: appColors.textSecondary,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // 向下按钮（跳转到下一条用户消息）
          Container(
            decoration: BoxDecoration(
              color: cardColor.withOpacity(0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: dividerColor.withOpacity(0.5),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _navigateToNextUserMessage,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 32,
                  height: 48,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.arrow_downward,
                    color: appColors.textSecondary,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrollToBottomButton() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 8,
      child: Center(
        child: AnimatedOpacity(
          opacity: _userScrolling ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: _ScrollToBottomIcon(
            onTap: () {
              setState(() => _userScrolling = false);
              _scrollToBottomImmediate();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildModeIndicator() {
    final isCodex = widget.repository is ApiCodexRepository;
    final modeName = isCodex ? 'Codex' : 'Claude Code';
    final modeColor = isCodex ? Colors.green : Colors.orange;

    return Positioned(
      top: 8,
      right: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: modeColor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: modeColor.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: modeColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              modeName,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: modeColor.withOpacity(0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final appColors = context.appColors;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: appColors.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无消息',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: appColors.textSecondary,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.repository is ApiCodexRepository
                ? '开始与 Codex 对话'
                : '开始与 Claude Code 对话',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: appColors.textTertiary,
                ),
          ),
        ],
      ),
    );
  }

  // 加载中状态（进入对话时显示）
  Widget _buildLoadingState() {
    final appColors = context.appColors;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: appColors.textTertiary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '加载中',
            style: TextStyle(
              fontSize: 13,
              color: appColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  // 加载更多指示器（列表顶部）
  Widget _buildLoadMoreIndicator() {
    final appColors = context.appColors;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.symmetric(vertical: _isLoadingMore ? 20 : 8),
      child: Center(
        child: AnimatedOpacity(
          opacity: _isLoadingMore ? 1.0 : 0.4,
          duration: const Duration(milliseconds: 200),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isLoadingMore)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: primaryColor.withOpacity(0.7),
                  ),
                )
              else
                Icon(
                  Icons.keyboard_arrow_up,
                  size: 20,
                  color: appColors.textTertiary,
                ),
              if (_isLoadingMore) ...[
                const SizedBox(height: 8),
                Text(
                  '加载中...',
                  style: TextStyle(
                    fontSize: 12,
                    color: appColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    final cardColor = Theme.of(context).cardColor;
    final dividerColor = Theme.of(context).dividerColor;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final appColors = context.appColors;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        border: Border(
          top: BorderSide(
            color: dividerColor,
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 图片预览区域
              if (_selectedImages.isNotEmpty)
                Container(
                  height: 100,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _selectedImages.length,
                    itemBuilder: (context, index) {
                      return Stack(
                        children: [
                          Container(
                            width: 100,
                            height: 100,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: dividerColor),
                              image: DecorationImage(
                                image: FileImage(_selectedImages[index]),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 12,
                            child: GestureDetector(
                              onTap: () => _removeImage(index),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(4),
                                child: const Icon(
                                  Icons.close,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              // 输入框和按钮
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // 图片选择按钮（仅 Claude Code 模式显示）
                  if (widget.repository is! ApiCodexRepository) ...[
                    Material(
                      color: appColors.claudeBubble,
                      borderRadius: BorderRadius.circular(24),
                      child: InkWell(
                        onTap: _pickImages,
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.image,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: CompositedTransformTarget(
                      link: _layerLink,
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 150),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: CallbackShortcuts(
                          bindings: Platform.isAndroid || Platform.isIOS
                              ? {} // 移动端不使用快捷键
                              : {
                                  // 桌面端：纯 Enter 键发送消息（不带任何修饰键）
                                  const SingleActivator(
                                    LogicalKeyboardKey.enter,
                                    shift: false,
                                    control: false,
                                    alt: false,
                                    meta: false,
                                  ): () {
                                    if (!_isSending && _textController.text.trim().isNotEmpty) {
                                      _handleSubmit(_textController.text);
                                    }
                                  },
                                },
                          child: TextField(
                            controller: _textController,
                            focusNode: _inputFocusNode,
                            decoration: InputDecoration(
                              hintText: _sessionProcessing && widget.repository is! ApiCodexRepository
                                  ? '补充信息或继续提问...'
                                  : '输入消息...',
                              hintStyle: TextStyle(
                                color: Colors.grey.shade400,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            maxLines: null,
                            minLines: 1,
                            keyboardType: TextInputType.multiline,
                            textInputAction: Platform.isAndroid || Platform.isIOS
                                ? TextInputAction.send
                                : TextInputAction.newline, // 桌面端支持 Shift+Enter 换行
                            enabled: true,
                            enableInteractiveSelection: true,
                            onSubmitted: Platform.isAndroid || Platform.isIOS
                                ? (text) {
                                    // 移动端：键盘发送按钮
                                    if (!_isSending && text.trim().isNotEmpty) {
                                      _handleSubmit(text);
                                    }
                                  }
                                : null, // 桌面端由 CallbackShortcuts 处理
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 停止按钮（仅在发送中且为 Claude Code 时显示）
                  if (_isSending && widget.repository is! ApiCodexRepository) ...[
                    Material(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(24),
                      child: InkWell(
                        onTap: _handleStop,
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.stop,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // 发送按钮
                  Material(
                    color: (_sessionProcessing && widget.repository is! ApiCodexRepository)
                        ? primaryColor.withOpacity(0.8) // 持续消息模式：稍微变暗表示可以补充信息
                        : primaryColor,
                    borderRadius: BorderRadius.circular(24),
                    child: InkWell(
                      onTap: () => _handleSubmit(_textController.text),
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        child: Icon(
                          _sessionProcessing && widget.repository is! ApiCodexRepository
                              ? Icons.add_comment // 持续消息模式：使用不同图标
                              : Icons.send,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 监听文本变化，检测斜杠命令
  void _onTextChanged() {
    // 仅在 Claude Code 模式下启用斜杠命令
    if (widget.repository is ApiCodexRepository) {
      if (_showCommandSuggestions) {
        _hideCommandSuggestions();
      }
      return;
    }

    final text = _textController.text;
    final cursorPosition = _textController.selection.baseOffset;

    // 检查光标前的文本
    if (cursorPosition > 0) {
      final textBeforeCursor = text.substring(0, cursorPosition);

      // 查找最后一个斜杠的位置
      final lastSlashIndex = textBeforeCursor.lastIndexOf('/');

      if (lastSlashIndex >= 0) {
        // 检查斜杠是否在行首或前面是空格
        final isValidSlash = lastSlashIndex == 0 ||
            textBeforeCursor[lastSlashIndex - 1] == ' ' ||
            textBeforeCursor[lastSlashIndex - 1] == '\n';

        if (isValidSlash) {
          // 提取斜杠后的查询文本
          final query = textBeforeCursor.substring(lastSlashIndex);

          // 检查查询是否被空格或换行符打断
          if (!query.contains(' ') && !query.contains('\n')) {
            _commandQuery = query.toLowerCase();
            _showCommandSuggestionsOverlay();
            return;
          }
        }
      }
    }

    // 如果不符合条件，隐藏建议
    if (_showCommandSuggestions) {
      _hideCommandSuggestions();
    }
  }

  // 显示命令建议
  void _showCommandSuggestionsOverlay() {
    if (!mounted) return;

    // 过滤匹配的命令
    final filteredCommands = _availableCommands.where((cmd) {
      return cmd['name']!.toLowerCase().startsWith(_commandQuery);
    }).toList();

    if (filteredCommands.isEmpty) {
      _hideCommandSuggestions();
      return;
    }

    // 如果已经有 overlay，先移除
    _commandOverlay?.remove();

    _commandOverlay = OverlayEntry(
      builder: (context) => _buildCommandSuggestionsOverlay(filteredCommands),
    );

    Overlay.of(context).insert(_commandOverlay!);
    setState(() {
      _showCommandSuggestions = true;
    });
  }

  // 隐藏命令建议
  void _hideCommandSuggestions() {
    _commandOverlay?.remove();
    _commandOverlay = null;
    _showCommandSuggestions = false;
    _commandQuery = '';
  }

  // 选择命令
  void _selectCommand(String commandName) {
    final text = _textController.text;
    final cursorPosition = _textController.selection.baseOffset;

    if (cursorPosition > 0) {
      final textBeforeCursor = text.substring(0, cursorPosition);
      final lastSlashIndex = textBeforeCursor.lastIndexOf('/');

      if (lastSlashIndex >= 0) {
        // 替换斜杠到光标之间的文本为选中的命令
        final newText = text.substring(0, lastSlashIndex) +
                       commandName + ' ' +
                       text.substring(cursorPosition);

        final newCursorPosition = lastSlashIndex + commandName.length + 1;

        _textController.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newCursorPosition),
        );
      }
    }

    _hideCommandSuggestions();
    _inputFocusNode.requestFocus();
  }

  // 构建命令建议浮层
  Widget _buildCommandSuggestionsOverlay(List<Map<String, String>> commands) {
    final appColors = context.appColors;
    final cardColor = Theme.of(context).cardColor;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;

    return Positioned(
      width: MediaQuery.of(context).size.width - 32,
      child: CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        offset: const Offset(0, -8), // 在输入框上方，增加间距避免遮挡
        targetAnchor: Alignment.topLeft,
        followerAnchor: Alignment.bottomLeft,
        child: Material(
          elevation: 3,
          shadowColor: Colors.black.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxHeight: 280),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: cardColor,
              border: Border.all(
                color: primaryColor.withOpacity(0.15),
                width: 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: commands.length,
                itemBuilder: (context, index) {
                  final cmd = commands[index];
                  return _CommandItem(
                    command: cmd,
                    primaryColor: primaryColor,
                    textSecondary: appColors.textSecondary,
                    onTap: () => _selectCommand(cmd['name']!),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _hideCommandSuggestions();
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }
}

// 命令项组件 - 使用 StatefulWidget 来实现 hover 效果
class _CommandItem extends StatefulWidget {
  final Map<String, String> command;
  final Color primaryColor;
  final Color textSecondary;
  final VoidCallback onTap;

  const _CommandItem({
    required this.command,
    required this.primaryColor,
    required this.textSecondary,
    required this.onTap,
  });

  @override
  State<_CommandItem> createState() => _CommandItemState();
}

class _CommandItemState extends State<_CommandItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          color: _isHovered
              ? widget.primaryColor.withOpacity(0.08)
              : Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.command['name']!,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: widget.primaryColor,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 3),
              Text(
                widget.command['description']!,
                style: TextStyle(
                  fontSize: 12,
                  color: widget.textSecondary,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 滚动到底部按钮 - hover 时箭头加深
class _ScrollToBottomIcon extends StatefulWidget {
  final VoidCallback onTap;

  const _ScrollToBottomIcon({required this.onTap});

  @override
  State<_ScrollToBottomIcon> createState() => _ScrollToBottomIconState();
}

class _ScrollToBottomIconState extends State<_ScrollToBottomIcon> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            Icons.keyboard_arrow_down,
            color: _isHovered ? Colors.black87 : Colors.black54,
            size: 28,
          ),
        ),
      ),
    );
  }
}
