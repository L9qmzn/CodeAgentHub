import 'package:flutter/material.dart';
import '../core/theme/panel_theme.dart';
import '../repositories/project_repository.dart';
import '../repositories/codex_repository.dart';
import '../services/app_settings_service.dart';
import '../services/config_service.dart';
import 'projects/project_list_screen.dart';
import 'recent_sessions_screen.dart';

class HomeScreen extends StatefulWidget {
  final ProjectRepository claudeRepository;
  final CodexRepository codexRepository;
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
  final VoidCallback? onLogout;
  final VoidCallback? onGoBack; // 返回到上一个页面
  final AgentMode? initialMode; // 标签页创建时的后端模式，用于锁定

  const HomeScreen({
    super.key,
    required this.claudeRepository,
    required this.codexRepository,
    this.onOpenChat,
    this.onNavigate,
    this.onLogout,
    this.onGoBack,
    this.initialMode, // 可选参数
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  AgentMode _currentMode = AgentMode.claudeCode; // 共享的模式状态

  @override
  void initState() {
    super.initState();
    _loadPreferredBackend();
  }

  // 从ConfigService加载用户上次选择的后端，或使用提供的初始模式
  Future<void> _loadPreferredBackend() async {
    // 如果提供了 initialMode，优先使用它（用于锁定标签页的后端选择）
    if (widget.initialMode != null) {
      setState(() {
        _currentMode = widget.initialMode!;
      });
      return;
    }

    // 否则从 ConfigService 读取（用于新建标签页）
    final configService = await ConfigService.getInstance();
    final preferredBackend = configService.preferredBackend;

    setState(() {
      if (preferredBackend == 'codex') {
        _currentMode = AgentMode.codex;
      } else {
        _currentMode = AgentMode.claudeCode;
      }
    });
  }

  // 模式切换回调
  void _onModeChanged(AgentMode mode) {
    setState(() {
      _currentMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 使用 PanelTheme 提供的背景色（如果有）
    final backgroundColor = PanelTheme.backgroundColor(context);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          ProjectListScreen(
            claudeRepository: widget.claudeRepository,
            codexRepository: widget.codexRepository,
            onOpenChat: widget.onOpenChat,
            onNavigate: widget.onNavigate,
            onLogout: widget.onLogout,
            onGoBack: widget.onGoBack, // 传递返回回调
            initialMode: widget.initialMode,
            sharedMode: _currentMode, // 传递共享模式
            onModeChanged: _onModeChanged, // 传递模式切换回调
          ),
          RecentSessionsScreen(
            claudeRepository: widget.claudeRepository,
            codexRepository: widget.codexRepository,
            onOpenChat: widget.onOpenChat,
            sharedMode: _currentMode, // 传递共享模式
            onModeChanged: _onModeChanged, // 传递模式切换回调
            onLogout: widget.onLogout, // 传递退出登录回调
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        backgroundColor: Theme.of(context).cardColor,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: '项目',
          ),
          NavigationDestination(
            icon: Icon(Icons.history),
            selectedIcon: Icon(Icons.history),
            label: '最近对话',
          ),
        ],
      ),
    );
  }
}
