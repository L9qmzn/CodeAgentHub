import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/panel_theme.dart';
import '../../models/project.dart';
import '../../models/session.dart';
import '../../repositories/project_repository.dart';
import '../../repositories/codex_repository.dart';
import '../../services/api_service.dart';
import '../../repositories/api_session_repository.dart';
import '../../repositories/api_codex_repository.dart';
import '../chat_screen.dart';

class SessionListScreen extends StatefulWidget {
  final Project? project;
  final dynamic repository; // 支持 ProjectRepository 或 CodexRepository
  final bool isSelectMode;
  final Function(Session)? onSessionSelected;
  final Function({
    required String sessionId,
    required String sessionName,
    required Widget chatWidget,
  })? onOpenChat;
  final Function({
    required String id,
    required String title,
    required Widget content,
  })? onNavigate;
  final VoidCallback? onBack; // 返回回调

  const SessionListScreen({
    super.key,
    required this.project,
    required this.repository,
    this.isSelectMode = false,
    this.onSessionSelected,
    this.onOpenChat,
    this.onNavigate,
    this.onBack,
  });

  @override
  State<SessionListScreen> createState() => _SessionListScreenState();
}

class _SessionListScreenState extends State<SessionListScreen> {
  List<Session> _sessions = [];
  bool _isLoading = false;

  // 判断是否为桌面平台
  bool get _isDesktop {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    if (widget.project == null) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final sessions = await widget.repository.getProjectSessions(widget.project!.id);
      setState(() {
        _sessions = sessions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _createNewSession() {
    if (widget.project == null) return;

    // 创建一个临时session（没有id，表示尚未创建）
    final tempSession = Session(
      id: '', // 空id表示还没有创建session
      projectId: widget.project!.id,
      title: '新对话',
      name: '新对话',
      cwd: widget.project!.path,
      messageCount: 0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final apiService = widget.repository.apiService;
    final dynamic sessionRepository = widget.repository is CodexRepository
        ? ApiCodexRepository(apiService)
        : ApiSessionRepository(apiService);

    if (widget.onOpenChat != null) {
      // 使用回调在新标签页打开
      widget.onOpenChat!(
        sessionId: 'new_${DateTime.now().millisecondsSinceEpoch}',
        sessionName: '新对话',
        chatWidget: ChatScreen(
          session: tempSession,
          repository: sessionRepository,
        ),
      );
    } else {
      // 降级到导航方式
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            session: tempSession,
            repository: sessionRepository,
          ),
        ),
      ).then((_) => _loadSessions());
    }
  }


  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final errorColor = Theme.of(context).colorScheme.error;
    final dividerColor = Theme.of(context).dividerColor;
    final cardColor = PanelTheme.cardColor(context);
    final backgroundColor = PanelTheme.backgroundColor(context);

    // 如果是选择模式且 project 为 null，显示项目列表
    if (widget.isSelectMode && widget.project == null) {
      return _buildProjectSelector();
    }

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
        backgroundColor: backgroundColor,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              // 如果有 onBack 回调，使用回调（标签页模式）
              if (widget.onBack != null) {
                widget.onBack!();
              } else {
                // 否则使用 Navigator.pop（导航模式）
                Navigator.of(context).pop();
              }
            },
          ),
          title: Text(widget.project?.name ?? '会话'),
          // 桌面端：添加按钮放在 AppBar 右侧
          actions: _isDesktop && !widget.isSelectMode
              ? [
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: _createNewSession,
                    tooltip: '新建对话',
                  ),
                ]
              : null,
        ),
        // 移动端：使用悬浮按钮
        floatingActionButton: !_isDesktop && !widget.isSelectMode
            ? FloatingActionButton(
                onPressed: _createNewSession,
                backgroundColor: primaryColor,
                child: const Icon(Icons.add),
              )
            : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadSessions,
              child: _sessions.isEmpty
                  ? Center(
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
                            '未找到会话',
                            style: TextStyle(
                              fontSize: 18,
                              color: appColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _sessions.length,
                      itemBuilder: (context, index) {
                        final session = _sessions[index];
                        return _buildSessionCard(session);
                      },
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
        onTap: () {
          // 如果是选择模式，直接回调
          if (widget.isSelectMode && widget.onSessionSelected != null) {
            widget.onSessionSelected!(session);
            return;
          }

          // 如果有 onOpenChat 回调，在新标签页中打开
          if (widget.onOpenChat != null) {
            final apiService = widget.repository.apiService;
            // 根据 repository 类型创建对应的 session repository
            final dynamic sessionRepository = widget.repository is CodexRepository
                ? ApiCodexRepository(apiService)
                : ApiSessionRepository(apiService);

            widget.onOpenChat!(
              sessionId: session.id,
              sessionName: session.name,
              chatWidget: ChatScreen(
                session: session,
                repository: sessionRepository,
              ),
            );
          } else {
            // 降级到导航方式 - 直接打开 ChatScreen
            final apiService = widget.repository.apiService;
            final dynamic sessionRepository = widget.repository is CodexRepository
                ? ApiCodexRepository(apiService)
                : ApiSessionRepository(apiService);

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(
                  session: session,
                  repository: sessionRepository,
                ),
              ),
            ).then((_) => _loadSessions());
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.chat_bubble,
                      color: primaryColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.title,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          session.cwd,
                          style: TextStyle(
                            fontSize: 13,
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
                    icon: Icons.message,
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
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: appColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: appColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectSelector() {
    return FutureBuilder<List<Project>>(
      future: widget.repository.getProjects(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('选择项目')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final projects = snapshot.data ?? [];
        final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
        final primaryColor = Theme.of(context).colorScheme.primary;

        return Scaffold(
          backgroundColor: backgroundColor,
          appBar: AppBar(title: const Text('选择项目')),
          body: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: projects.length,
            itemBuilder: (context, index) {
              final project = projects[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(Icons.folder, color: primaryColor),
                  title: Text(project.name),
                  subtitle: Text(project.path, style: TextStyle(fontSize: 12)),
                  onTap: () {
                    // 显示该项目的会话列表
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SessionListScreen(
                          project: project,
                          repository: widget.repository,
                          isSelectMode: true,
                          onSessionSelected: widget.onSessionSelected,
                          onNavigate: widget.onNavigate,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        );
      },
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
}
