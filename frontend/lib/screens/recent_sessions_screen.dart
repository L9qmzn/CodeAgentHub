import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/panel_theme.dart';
import '../models/session.dart';
import '../repositories/project_repository.dart';
import '../repositories/codex_repository.dart';
import '../repositories/api_session_repository.dart';
import '../repositories/api_codex_repository.dart';
import '../services/app_settings_service.dart';
import '../services/config_service.dart';
import '../services/shared_project_data_service.dart';
import 'tab_navigator_screen.dart';
import 'chat_screen.dart';
import 'settings/settings_screen.dart';

class RecentSessionsScreen extends StatefulWidget {
  final ProjectRepository claudeRepository;
  final CodexRepository codexRepository;
  final Function({
    required String sessionId,
    required String sessionName,
    required Widget chatWidget,
  })? onOpenChat;
  final AgentMode? sharedMode; // 共享的模式状态
  final Function(AgentMode)? onModeChanged; // 模式切换回调
  final VoidCallback? onLogout; // 退出登录回调

  const RecentSessionsScreen({
    super.key,
    required this.claudeRepository,
    required this.codexRepository,
    this.onOpenChat,
    this.sharedMode,
    this.onModeChanged,
    this.onLogout,
  });

  @override
  State<RecentSessionsScreen> createState() => _RecentSessionsScreenState();
}

class _RecentSessionsScreenState extends State<RecentSessionsScreen> with AutomaticKeepAliveClientMixin {
  List<Session> _recentSessions = [];
  bool _isLoading = false;
  String? _error;
  static const int _pageSize = 50; // 每页加载50条
  bool _hasMore = true; // 是否还有更多数据

  @override
  bool get wantKeepAlive => true; // 保持状态

  // 获取共享数据服务
  SharedProjectDataService get _dataService => SharedProjectDataService.instance;

  // 获取当前模式（优先使用共享模式）
  AgentMode get _currentMode => widget.sharedMode ?? AgentMode.claudeCode;

  // 获取当前使用的仓库
  dynamic get _currentRepository => _currentMode == AgentMode.claudeCode
      ? widget.claudeRepository
      : widget.codexRepository;

  @override
  void initState() {
    super.initState();
    _setupDataListeners();
    _loadRecentSessions();
  }

  @override
  void dispose() {
    _removeDataListeners();
    super.dispose();
  }

  // 设置数据监听器
  void _setupDataListeners() {
    _dataService.claudeRecentSessionsNotifier.addListener(_onClaudeSessionsChanged);
    _dataService.codexRecentSessionsNotifier.addListener(_onCodexSessionsChanged);
    _dataService.claudeSessionsLoadingNotifier.addListener(_onLoadingChanged);
    _dataService.codexSessionsLoadingNotifier.addListener(_onLoadingChanged);
    _dataService.claudeSessionsErrorNotifier.addListener(_onErrorChanged);
    _dataService.codexSessionsErrorNotifier.addListener(_onErrorChanged);
  }

  // 移除数据监听器
  void _removeDataListeners() {
    _dataService.claudeRecentSessionsNotifier.removeListener(_onClaudeSessionsChanged);
    _dataService.codexRecentSessionsNotifier.removeListener(_onCodexSessionsChanged);
    _dataService.claudeSessionsLoadingNotifier.removeListener(_onLoadingChanged);
    _dataService.codexSessionsLoadingNotifier.removeListener(_onLoadingChanged);
    _dataService.claudeSessionsErrorNotifier.removeListener(_onErrorChanged);
    _dataService.codexSessionsErrorNotifier.removeListener(_onErrorChanged);
  }

  // Claude 对话数据变化
  void _onClaudeSessionsChanged() {
    if (_currentMode == AgentMode.claudeCode && mounted) {
      setState(() {
        _recentSessions = _dataService.claudeRecentSessionsNotifier.value;
      });
    }
  }

  // Codex 对话数据变化
  void _onCodexSessionsChanged() {
    if (_currentMode == AgentMode.codex && mounted) {
      setState(() {
        _recentSessions = _dataService.codexRecentSessionsNotifier.value;
      });
    }
  }

  // 加载状态变化
  void _onLoadingChanged() {
    if (!mounted) return;
    final isLoading = _currentMode == AgentMode.claudeCode
        ? _dataService.claudeSessionsLoadingNotifier.value
        : _dataService.codexSessionsLoadingNotifier.value;
    if (_isLoading != isLoading) {
      setState(() {
        _isLoading = isLoading;
      });
    }
  }

  // 错误状态变化
  void _onErrorChanged() {
    if (!mounted) return;
    final error = _currentMode == AgentMode.claudeCode
        ? _dataService.claudeSessionsErrorNotifier.value
        : _dataService.codexSessionsErrorNotifier.value;
    if (_error != error) {
      setState(() {
        _error = error;
      });
    }
  }

  @override
  void didUpdateWidget(RecentSessionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 如果共享模式变化，重新加载会话
    if (oldWidget.sharedMode != widget.sharedMode && widget.sharedMode != null) {
      _loadRecentSessions();
    }
  }

  // 加载会话（使用共享数据服务）
  Future<void> _loadRecentSessions({bool forceRefresh = false}) async {
    if (!mounted) return;

    final isCodex = _currentMode == AgentMode.codex;
    await _dataService.refreshRecentSessions(
      isCodex: isCodex,
      force: forceRefresh,
      limit: _pageSize,
    );
  }

  // 加载更多会话
  Future<void> _loadMoreSessions() async {
    if (!mounted || _isLoading || !_hasMore) return;

    setState(() => _isLoading = true);

    try {
      // 获取所有项目
      final projects = await _currentRepository.getProjects();

      // 获取所有项目的会话
      final allSessions = <Session>[];
      for (var project in projects) {
        final sessions = await _currentRepository.getProjectSessions(project.id);
        allSessions.addAll(sessions);
      }

      // 按 updatedAt 降序排序
      allSessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      if (!mounted) return;

      final currentLength = _recentSessions.length;
      final nextBatch = allSessions.skip(currentLength).take(_pageSize).toList();

      setState(() {
        _recentSessions.addAll(nextBatch);
        _hasMore = _recentSessions.length < allSessions.length;
        _isLoading = false;
      });

      print('DEBUG: Loaded ${nextBatch.length} more sessions (total now: ${_recentSessions.length}, hasMore: $_hasMore)');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      print('ERROR: Failed to load more sessions: $e');
    }
  }

  // 局部更新单个会话（避免重新加载整个列表）
  Future<void> updateSession(String sessionId) async {
    if (!mounted) return;

    print('DEBUG: Updating single session $sessionId');

    try {
      // 获取所有项目
      final projects = await _currentRepository.getProjects();

      // 查找包含此会话的项目
      Session? updatedSession;
      for (var project in projects) {
        final sessions = await _currentRepository.getProjectSessions(project.id);
        final found = sessions.firstWhere(
          (s) => s.id == sessionId,
          orElse: () => Session(
            id: '',
            projectId: '',
            title: '',
            name: '',
            cwd: '',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        if (found.id == sessionId) {
          updatedSession = found;
          break;
        }
      }

      if (updatedSession == null || !mounted) return;

      // 在列表中找到并更新这个会话
      final index = _recentSessions.indexWhere((s) => s.id == sessionId);
      if (index != -1) {
        setState(() {
          _recentSessions[index] = updatedSession!;
          // 重新排序
          _recentSessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        });
        print('DEBUG: Updated session $sessionId at index $index');
      } else {
        // 如果列表中没有这个会话，添加到开头
        setState(() {
          _recentSessions.insert(0, updatedSession!);
          // 如果超过分页大小，移除最后一个
          if (_recentSessions.length > _pageSize) {
            _recentSessions.removeLast();
          }
        });
        print('DEBUG: Added new session $sessionId to list');
      }
    } catch (e) {
      print('ERROR: Failed to update session $sessionId: $e');
    }
  }

  // 切换模式
  Future<void> _switchMode(AgentMode mode) async {
    if (_currentMode != mode) {
      // 通知父组件模式变化
      widget.onModeChanged?.call(mode);

      // 保存到ConfigService
      final configService = await ConfigService.getInstance();
      final backendString = mode == AgentMode.codex ? 'codex' : 'claude_code';
      await configService.setPreferredBackend(backendString);
    }
  }

  void _openSession(Session session) {
    if (widget.onOpenChat != null) {
      // 使用回调在新标签页中打开
      final apiService = _currentRepository.apiService;
      final sessionRepository = _currentMode == AgentMode.claudeCode
          ? ApiSessionRepository(apiService)
          : ApiCodexRepository(apiService);

      widget.onOpenChat!(
        sessionId: session.id,
        sessionName: session.name,
        chatWidget: ChatScreen(
          session: session,
          repository: sessionRepository,
        ),
      );
    } else {
      // 降级到导航方式（用于独立测试）
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TabNavigatorScreen(
            repository: _currentRepository,
            initialSession: session,
          ),
        ),
      ).then((_) => _loadRecentSessions());
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须调用以支持 AutomaticKeepAliveClientMixin

    final appColors = context.appColors;
    final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final errorColor = Theme.of(context).colorScheme.error;
    final dividerColor = Theme.of(context).dividerColor;
    final cardColor = Theme.of(context).cardColor;
    final backgroundColor = PanelTheme.backgroundColor(context);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: _buildBackendSelector(primaryColor, cardColor, backgroundColor),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addNewSession,
            tooltip: '新建对话',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadRecentSessions(forceRefresh: true),
            tooltip: '刷新最近对话',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    claudeRepository: widget.claudeRepository,
                    codexRepository: widget.codexRepository,
                    onLogout: widget.onLogout,
                  ),
                ),
              );
            },
            tooltip: '设置',
          ),
        ],
      ),
      body: _isLoading && _recentSessions.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _loadRecentSessions(forceRefresh: true),
              child: _recentSessions.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _recentSessions.length + (_hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        // 显示"加载更多"按钮
                        if (index == _recentSessions.length) {
                          return _buildLoadMoreButton();
                        }
                        final session = _recentSessions[index];
                        return _buildSessionCard(session);
                      },
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
            '暂无最近对话',
            style: TextStyle(
              fontSize: 18,
              color: appColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadMoreButton() {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final appColors = context.appColors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton.icon(
                onPressed: _loadMoreSessions,
                icon: Icon(Icons.expand_more, color: primaryColor),
                label: Text(
                  '加载更多',
                  style: TextStyle(color: primaryColor, fontSize: 14),
                ),
              ),
      ),
    );
  }

  Widget _buildSessionCard(Session session) {
    final appColors = context.appColors;
    final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final dividerColor = Theme.of(context).dividerColor;
    final cardColor = Theme.of(context).cardColor;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: dividerColor),
      ),
      child: InkWell(
        onTap: () => _openSession(session),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.chat,
                      color: primaryColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          session.cwd,
                          style: TextStyle(
                            fontSize: 12,
                            color: appColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildInfoChip(
                    icon: Icons.message_outlined,
                    label: '${session.messageCount} 条消息',
                  ),
                  const SizedBox(width: 12),
                  _buildInfoChip(
                    icon: Icons.access_time,
                    label: _formatTime(session.updatedAt),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip({required IconData icon, required String label}) {
    final appColors = context.appColors;
    final backgroundColor = PanelTheme.backgroundColor(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: appColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: appColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays == 1) return '昨天';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${time.year}/${time.month}/${time.day}';
  }

  // 新建对话
  Future<void> _addNewSession() async {
    final pathController = TextEditingController(text: 'C:\\Users');

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        final appColors = context.appColors;
        final primaryColor = Theme.of(context).colorScheme.primary;

        return AlertDialog(
          title: const Text('新建对话'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pathController,
                decoration: const InputDecoration(
                  labelText: '项目路径',
                  hintText: '输入项目目录路径',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '创建后将直接进入对话界面',
                style: TextStyle(
                  fontSize: 12,
                  color: appColors.textSecondary,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                if (pathController.text.trim().isNotEmpty) {
                  Navigator.pop(context, pathController.text.trim());
                }
              },
              child: Text('创建', style: TextStyle(color: primaryColor)),
            ),
          ],
        );
      },
    );

    if (result != null && mounted) {
      _openNewSessionChat(result);
    }
  }

  void _openNewSessionChat(String cwd) {
    // 创建一个临时session（没有id，表示尚未创建）
    final tempSession = Session(
      id: '', // 空id表示还没有创建session
      projectId: cwd,
      title: '新对话',
      name: '新对话',
      cwd: cwd,
      messageCount: 0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // 根据当前模式选择 repository
    final apiService = _currentMode == AgentMode.claudeCode
        ? widget.claudeRepository.apiService
        : widget.codexRepository.apiService;
    final dynamic sessionRepository = _currentMode == AgentMode.claudeCode
        ? ApiSessionRepository(apiService)
        : ApiCodexRepository(apiService);

    if (widget.onOpenChat != null) {
      // 使用回调在新标签页打开
      widget.onOpenChat!(
        sessionId: 'new_${DateTime.now().millisecondsSinceEpoch}',
        sessionName: '新对话 - ${cwd.split('\\').last}',
        chatWidget: ChatScreen(
          session: tempSession,
          repository: sessionRepository,
        ),
      );
    }
  }

  // 构建后端选择器
  Widget _buildBackendSelector(Color primaryColor, Color cardColor, Color backgroundColor) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryColor.withOpacity(0.2), width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showBackendPicker(primaryColor, cardColor),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _currentMode == AgentMode.claudeCode ? Icons.code : Icons.terminal,
                  size: 16,
                  color: primaryColor,
                ),
                const SizedBox(width: 6),
                Text(
                  _currentMode.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.expand_more, size: 18, color: primaryColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showBackendPicker(Color primaryColor, Color cardColor) {
    final appColors = context.appColors;
    final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;

    showModalBottomSheet(
      context: context,
      backgroundColor: cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: appColors.textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '选择后端模式',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            _buildBackendOption(
              mode: AgentMode.claudeCode,
              icon: Icons.code,
              title: 'Claude Code',
              description: '官方 Claude Code 后端',
              primaryColor: primaryColor,
              appColors: appColors,
              textPrimary: textPrimary,
            ),
            const SizedBox(height: 12),
            _buildBackendOption(
              mode: AgentMode.codex,
              icon: Icons.terminal,
              title: 'Codex',
              description: 'Codex 兼容后端',
              primaryColor: primaryColor,
              appColors: appColors,
              textPrimary: textPrimary,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildBackendOption({
    required AgentMode mode,
    required IconData icon,
    required String title,
    required String description,
    required Color primaryColor,
    required dynamic appColors,
    required Color textPrimary,
  }) {
    final isSelected = _currentMode == mode;
    final cardColor = Theme.of(context).cardColor;
    final dividerColor = Theme.of(context).dividerColor;

    return Material(
      color: isSelected ? primaryColor.withOpacity(0.1) : cardColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.pop(context);
          _switchMode(mode);
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? primaryColor : dividerColor,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 24, color: isSelected ? primaryColor : textPrimary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 13,
                        color: appColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle, size: 24, color: primaryColor),
            ],
          ),
        ),
      ),
    );
  }
}
