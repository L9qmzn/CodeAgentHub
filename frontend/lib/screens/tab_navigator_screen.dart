import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../models/session.dart';
import '../repositories/project_repository.dart';
import '../repositories/api_session_repository.dart';
import 'chat_screen.dart';
import 'sessions/session_list_screen.dart';

class TabNavigatorScreen extends StatefulWidget {
  final ProjectRepository repository;
  final Session? initialSession;

  const TabNavigatorScreen({
    super.key,
    required this.repository,
    this.initialSession,
  });

  @override
  State<TabNavigatorScreen> createState() => _TabNavigatorScreenState();
}

class _TabNavigatorScreenState extends State<TabNavigatorScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<Session> _openSessions = [];
  int _currentTabIndex = 0;

  @override
  void initState() {
    super.initState();

    // 如果有初始会话，添加到标签页列表
    if (widget.initialSession != null) {
      _openSessions.add(widget.initialSession!);
    }

    _tabController = TabController(
      length: _openSessions.length,
      vsync: this,
    );

    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _currentTabIndex = _tabController.index;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _addNewTab() async {
    // 显示会话选择对话框
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _SessionSelectorSheet(repository: widget.repository),
    );

    if (result != null && mounted) {
      final session = result['session'] as Session;

      // 检查会话是否已经打开
      final existingIndex = _openSessions.indexWhere((s) => s.id == session.id);
      if (existingIndex != -1) {
        // 切换到已存在的标签页
        _tabController.animateTo(existingIndex);
        return;
      }

      // 添加新标签页
      setState(() {
        _openSessions.add(session);
      });

      // 重新创建 TabController
      _tabController.dispose();
      _tabController = TabController(
        length: _openSessions.length,
        vsync: this,
        initialIndex: _openSessions.length - 1,
      );
      _tabController.addListener(() {
        if (_tabController.indexIsChanging) {
          setState(() {
            _currentTabIndex = _tabController.index;
          });
        }
      });

      setState(() {
        _currentTabIndex = _openSessions.length - 1;
      });
    }
  }

  void _closeTab(int index) {
    if (_openSessions.length == 1) {
      // 最后一个标签页，返回上一页
      Navigator.pop(context);
      return;
    }

    setState(() {
      _openSessions.removeAt(index);
    });

    // 重新创建 TabController
    final newIndex = index >= _openSessions.length ? _openSessions.length - 1 : index;
    _tabController.dispose();
    _tabController = TabController(
      length: _openSessions.length,
      vsync: this,
      initialIndex: newIndex,
    );
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _currentTabIndex = _tabController.index;
        });
      }
    });

    setState(() {
      _currentTabIndex = newIndex;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final textSecondary = appColors.textSecondary;
    final textTertiary = appColors.textTertiary;

    if (_openSessions.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('对话'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.chat_bubble_outline, size: 64, color: textTertiary),
              const SizedBox(height: 16),
              Text('暂无打开的对话', style: TextStyle(color: textSecondary)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _addNewTab,
                icon: const Icon(Icons.add),
                label: const Text('打开对话'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('对话'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: _openSessions.asMap().entries.map((entry) {
                    final index = entry.key;
                    final session = entry.value;
                    return Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            session.name.length > 15
                                ? '${session.name.substring(0, 15)}...'
                                : session.name,
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => _closeTab(index),
                            child: Icon(Icons.close, size: 16),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: _addNewTab,
                tooltip: '新建标签页',
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _openSessions.map((session) {
          return ChatScreen(
            session: session,
            repository: ApiSessionRepository(widget.repository.apiService),
          );
        }).toList(),
      ),
    );
  }
}

// 会话选择器底部抽屉
class _SessionSelectorSheet extends StatefulWidget {
  final ProjectRepository repository;

  const _SessionSelectorSheet({required this.repository});

  @override
  State<_SessionSelectorSheet> createState() => _SessionSelectorSheetState();
}

class _SessionSelectorSheetState extends State<_SessionSelectorSheet> {
  int _selectedTab = 0;
  List<Session> _recentSessions = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadRecentSessions();
  }

  Future<void> _loadRecentSessions() async {
    setState(() => _isLoading = true);
    try {
      final projects = await widget.repository.getProjects();
      final allSessions = <Session>[];
      for (var project in projects) {
        final sessions = await widget.repository.getProjectSessions(project.id);
        allSessions.addAll(sessions);
      }
      allSessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      setState(() {
        _recentSessions = allSessions.take(20).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = context.appColors;
    final backgroundColor = theme.scaffoldBackgroundColor;
    final cardColor = theme.cardColor;
    final primaryColor = colorScheme.primary;
    final textPrimary = colorScheme.onSurface;
    final textSecondary = appColors.textSecondary;

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        children: [
          // 标题和关闭按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '选择对话',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 选项卡
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildTabButton('最近对话', 0),
                const SizedBox(width: 8),
                _buildTabButton('项目', 1),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 内容
          Expanded(
            child: _selectedTab == 0
                ? _buildRecentSessionsList()
                : _buildProjectsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(String label, int index) {
    final isSelected = _selectedTab == index;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final backgroundColor = theme.scaffoldBackgroundColor;
    final primaryColor = colorScheme.primary;
    final textPrimary = colorScheme.onSurface;

    return Expanded(
      child: Material(
        color: isSelected ? primaryColor : backgroundColor,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => setState(() => _selectedTab = index),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentSessionsList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = context.appColors;
    final cardColor = theme.cardColor;
    final primaryColor = colorScheme.primary;
    final textSecondary = appColors.textSecondary;

    if (_recentSessions.isEmpty) {
      return Center(
        child: Text('暂无最近对话', style: TextStyle(color: textSecondary)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _recentSessions.length,
      itemBuilder: (context, index) {
        final session = _recentSessions[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: cardColor,
          elevation: 0,
          child: ListTile(
            leading: Icon(Icons.chat, color: primaryColor),
            title: Text(
              session.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              session.cwd,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: textSecondary),
            ),
            onTap: () {
              Navigator.pop(context, {'session': session});
            },
          ),
        );
      },
    );
  }

  Widget _buildProjectsList() {
    return SessionListScreen(
      project: null,
      repository: widget.repository,
      isSelectMode: true,
      onSessionSelected: (session) {
        Navigator.pop(context, {'session': session});
      },
    );
  }
}
