import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:window_manager/window_manager.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/panel_theme.dart';
import '../core/utils/platform_helper.dart';
import '../repositories/api_codex_repository.dart';
import '../repositories/api_session_repository.dart';
import '../repositories/project_repository.dart';
import '../repositories/session_repository.dart';
import '../repositories/codex_repository.dart';
import '../models/project.dart';
import '../models/session.dart';
import '../services/app_settings_service.dart';
import '../services/config_service.dart';
import '../services/notification_sound_service.dart';
import '../services/shared_project_data_service.dart';
import '../services/single_instance_service.dart';
import 'chat_screen.dart';
import 'home_screen.dart';
import 'sessions/session_list_screen.dart';

// 定义标签页类型
enum TabType {
  home, // 首页（项目和最近对话）
  chat, // 具体对话
}

class TabInfo {
  final String id;
  final TabType type;
  final String title;
  final Widget content;
  bool hasNewReply; // 是否有新回复（用于标签高亮）
  final ValueNotifier<bool> hasNewReplyNotifier; // 新回复通知器
  final Widget? previousContent; // 上一个界面（用于返回）
  final String? previousTitle; // 上一个界面的标题
  final Widget? previousPreviousContent; // 更深一层的历史界面
  final String? previousPreviousTitle; // 更深一层的历史标题
  final String? cwd; // 当前工作目录（用于在同目录新建对话）
  final bool isCodex; // 是否是 Codex 模式

  TabInfo({
    required this.id,
    required this.type,
    required this.title,
    required this.content,
    this.hasNewReply = false,
    this.previousContent,
    this.previousTitle,
    this.previousPreviousContent,
    this.previousPreviousTitle,
    this.cwd,
    this.isCodex = false,
  }) : hasNewReplyNotifier = ValueNotifier<bool>(hasNewReply);

  void dispose() {
    hasNewReplyNotifier.dispose();
  }
}

class TabManagerScreen extends StatefulWidget {
  final ProjectRepository claudeRepository;
  final CodexRepository codexRepository;
  final String? initialPath; // 从命令行传入的初始文件夹路径
  final SingleInstanceService? singleInstanceService; // 单实例服务，用于接收其他实例的路径
  final VoidCallback? onLogout;
  final Future<void> Function(String)? onApiUrlChanged;

  const TabManagerScreen({
    super.key,
    required this.claudeRepository,
    required this.codexRepository,
    this.initialPath,
    this.singleInstanceService,
    this.onLogout,
    this.onApiUrlChanged,
  });

  @override
  State<TabManagerScreen> createState() => _TabManagerScreenState();
}

class _TabManagerScreenState extends State<TabManagerScreen>
    with TickerProviderStateMixin {
  // 左侧面板（主面板）
  late TabController _tabController;
  final List<TabInfo> _tabs = [];
  int _currentIndex = 0;

  // 分屏模式相关
  bool _isSplitScreen = false;
  TabController? _rightTabController;
  final List<TabInfo> _rightTabs = [];
  int _rightCurrentIndex = 0;
  double _splitRatio = 0.5; // 左侧面板占比（0.0-1.0），默认50%
  bool _isDraggingDivider = false; // 是否正在拖动分隔条
  bool _hoveringSplitButton = false; // 鼠标是否悬停在分屏按钮区域

  @override
  void initState() {
    super.initState();
    // 初始化共享数据服务
    _initSharedDataService();

    // 初始化 TabController
    _tabController = TabController(
      length: 0,
      vsync: this,
    );
    // 默认打开一个首页标签
    _addHomeTab();

    // 如果有初始路径，自动打开对应项目
    if (widget.initialPath != null) {
      _handleInitialPath(widget.initialPath!);
    }

    // 监听来自其他实例的新路径请求
    widget.singleInstanceService?.onNewPath.listen(_onNewPathFromOtherInstance);
  }

  /// 初始化共享数据服务
  void _initSharedDataService() {
    SharedProjectDataService.instance.initialize(
      claudeRepository: widget.claudeRepository,
      codexRepository: widget.codexRepository,
      refreshInterval: const Duration(seconds: 30),
    );
  }

  /// 处理来自其他实例的新路径请求
  Future<void> _onNewPathFromOtherInstance(String path) async {
    print('TabManager: Received path from another instance: $path');

    // 聚焦窗口（仅桌面平台）
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      try {
        // 导入 window_manager 需要的类
        final windowManager = WindowManager.instance;
        await windowManager.show();
        await windowManager.focus();
      } catch (e) {
        print('TabManager: Failed to focus window: $e');
      }
    }

    // 在新标签页中打开路径
    await _handleInitialPath(path);
  }

  // 处理从命令行传入的文件夹路径
  Future<void> _handleInitialPath(String path) async {
    // 等待首页标签加载完成
    await Future.delayed(const Duration(milliseconds: 500));

    try {
      // 从 ConfigService 获取首选后端
      final configService = await ConfigService.getInstance();
      final preferredBackend = configService.preferredBackend;

      // 根据后端类型选择 repository
      final dynamic projectRepository = preferredBackend == 'codex'
          ? widget.codexRepository
          : widget.claudeRepository;

      // 创建 SessionRepository（用于 ChatScreen）
      final dynamic sessionRepository = preferredBackend == 'codex'
          ? ApiCodexRepository(projectRepository.apiService)
          : ApiSessionRepository(projectRepository.apiService);

      // 查找是否已有该路径的项目
      final projects = await projectRepository.getProjects();
      Project? existingProject;

      // 查找匹配的项目
      for (final project in projects) {
        if (project.path == path) {
          existingProject = project;
          break;
        }
      }

      if (existingProject != null) {
        // 项目已存在，获取其会话列表
        final sessions = await projectRepository.getProjectSessions(existingProject.id);

        if (sessions.isNotEmpty) {
          // 有会话，打开最近的会话
          final latestSession = sessions.first;
          _openChatFromInitialPath(latestSession, sessionRepository, existingProject.name);
        } else {
          // 无会话，创建新会话
          await _createNewSessionForPath(existingProject, sessionRepository);
        }
      } else {
        // 项目不存在，使用路径作为项目名创建新会话
        final projectName = path.split(Platform.pathSeparator).last;
        await _createNewSessionForPath(
          Project(id: '', name: projectName, path: path, createdAt: DateTime.now()),
          sessionRepository,
        );
      }
    } catch (e) {
      print('Error handling initial path: $e');
    }
  }

  // 为指定路径创建新会话
  Future<void> _createNewSessionForPath(Project project, dynamic sessionRepository) async {
    final session = Session(
      id: '', // 空ID，后端会创建
      projectId: project.id,
      title: '新对话',
      name: project.name,
      cwd: project.path, // Project 使用 path，Session 使用 cwd
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    _openChatFromInitialPath(session, sessionRepository, project.name);
  }

  // 打开从初始路径来的会话（在新标签页中打开）
  void _openChatFromInitialPath(Session session, dynamic sessionRepository, String projectName) {
    final sessionId = session.id.isEmpty ? 'new_${DateTime.now().millisecondsSinceEpoch}' : session.id;
    final tabId = 'chat_$sessionId';

    // 检查是否已经在其他标签页打开该会话
    final existingIndex = _tabs.indexWhere(
      (tab) => tab.id == tabId,
    );

    if (existingIndex != -1) {
      // 切换到已存在的标签
      _tabController.animateTo(existingIndex);
      return;
    }

    // 创建新的TabInfo（包含ValueNotifier）
    final newTab = TabInfo(
      id: tabId,
      type: TabType.chat,
      title: projectName,
      content: Container(), // 临时占位
    );

    // 创建带回调的 ChatScreen
    final wrappedWidget = ChatScreen(
      key: ValueKey(tabId),
      session: session,
      repository: sessionRepository,
      onMessageComplete: () {
        final currentTabIndex = _tabs.indexWhere((tab) => tab.id == tabId);
        if (currentTabIndex != -1) {
          _handleMessageComplete(currentTabIndex);
        }
      },
      hasNewReplyNotifier: newTab.hasNewReplyNotifier,
    );

    // 获取 isCodex 信息
    final bool isCodex = sessionRepository is ApiCodexRepository;

    // 更新 content
    final finalTab = TabInfo(
      id: newTab.id,
      type: newTab.type,
      title: newTab.title,
      content: wrappedWidget,
      cwd: session.cwd,
      isCodex: isCodex,
    );

    // 添加新标签页
    setState(() {
      _tabs.add(finalTab);
    });

    // 切换到新标签页
    _rebuildTabController(_tabs.length - 1);
  }

  Future<void> _addHomeTab() async {
    // 从 ConfigService 读取当前的后端选择，作为标签页的初始模式
    final configService = await ConfigService.getInstance();
    final preferredBackend = configService.preferredBackend;
    final initialMode = preferredBackend == 'codex' ? AgentMode.codex : AgentMode.claudeCode;

    final newTab = TabInfo(
      id: 'home_${DateTime.now().millisecondsSinceEpoch}',
      type: TabType.home,
      title: '主页',
      content: HomeScreen(
        claudeRepository: widget.claudeRepository,
        codexRepository: widget.codexRepository,
        onOpenChat: _openChatInCurrentTab,
        onNavigate: _replaceCurrentTab,
        onLogout: widget.onLogout,
        onGoBack: _goBackInCurrentTab, // 传递返回回调
        initialMode: initialMode, // 传入初始模式，锁定标签页的后端选择
      ),
    );

    setState(() {
      _tabs.add(newTab);
    });

    _rebuildTabController(_tabs.length - 1);
  }

  void _replaceCurrentTab({
    required String id,
    required String title,
    required Widget content,
  }) {
    final currentTab = _tabs[_currentIndex];

    final newTab = TabInfo(
      id: id,
      type: TabType.home, // 保持为 home 类型，因为不是聊天
      title: title,
      content: content,
      previousContent: currentTab.content, // 保存当前内容，用于返回
      previousTitle: currentTab.title, // 保存当前标题
      // 保存更深一层的历史（如果当前tab已经有历史的话）
      previousPreviousContent: currentTab.previousContent,
      previousPreviousTitle: currentTab.previousTitle,
    );

    setState(() {
      _tabs[_currentIndex] = newTab;
    });
  }

  void _goBackInCurrentTab() {
    final currentTab = _tabs[_currentIndex];

    // 找到最底层的主页内容
    Widget? targetContent = currentTab.previousContent;
    String? targetTitle = currentTab.previousTitle;

    // 如果有更深层的历史，一直往下找到最底层
    if (currentTab.previousPreviousContent != null) {
      targetContent = currentTab.previousPreviousContent;
      targetTitle = currentTab.previousPreviousTitle;
    }

    // 如果有之前的内容，恢复到最底层的内容（主页）
    if (targetContent != null) {
      final restoredTab = TabInfo(
        id: 'home_${DateTime.now().millisecondsSinceEpoch}',
        type: TabType.home,
        title: targetTitle ?? '主页',
        content: targetContent,
        // 不再保留历史，直接回到主页
      );

      setState(() {
        _tabs[_currentIndex] = restoredTab;
      });
    }
  }

  void _openChatInCurrentTab({
    required String sessionId,
    required String sessionName,
    required Widget chatWidget,
  }) {
    // 检查是否已经在其他标签页打开该会话
    final existingIndex = _tabs.indexWhere(
      (tab) => tab.id == 'chat_$sessionId',
    );

    if (existingIndex != -1) {
      // 切换到已存在的标签
      _tabController.animateTo(existingIndex);
      return;
    }

    // 保存当前要替换的标签索引
    final targetIndex = _currentIndex;

    // 创建新的TabInfo（包含ValueNotifier）
    final newTab = TabInfo(
      id: 'chat_$sessionId',
      type: TabType.chat,
      title: sessionName,
      content: Container(), // 临时占位
    );

    // 如果 chatWidget 是 ChatScreen，重新创建并添加回调和通知器
    Widget wrappedWidget = chatWidget;
    final tabId = 'chat_$sessionId'; // 使用 tab ID 来查找正确的标签页
    if (chatWidget is ChatScreen) {
      wrappedWidget = ChatScreen(
        key: ValueKey(tabId), // 添加唯一 key，确保 Flutter 正确识别不同的 ChatScreen
        session: chatWidget.session,
        repository: chatWidget.repository,
        onMessageComplete: () {
          // 通过 tab ID 查找当前索引，避免索引失效问题
          final currentTabIndex = _tabs.indexWhere((tab) => tab.id == tabId);
          if (currentTabIndex != -1) {
            _handleMessageComplete(currentTabIndex);
          }
        },
        hasNewReplyNotifier: newTab.hasNewReplyNotifier,
        onBack: () => _handleBackToHome(targetIndex),
      );
    }

    // 获取 cwd 和 isCodex 信息
    String? cwd;
    bool isCodex = false;
    if (chatWidget is ChatScreen) {
      cwd = chatWidget.session.cwd;
      isCodex = chatWidget.repository is ApiCodexRepository;
    }

    // 替换当前标签页（需要先dispose旧的）
    setState(() {
      // 保存当前界面及其历史，以便返回时恢复
      final currentTab = _tabs[_currentIndex];
      final previousContent = currentTab.content;
      final previousTitle = currentTab.title;
      final previousPreviousContent = currentTab.previousContent;
      final previousPreviousTitle = currentTab.previousTitle;

      currentTab.dispose();
      _tabs[_currentIndex] = TabInfo(
        id: 'chat_$sessionId',
        type: TabType.chat,
        title: sessionName,
        content: wrappedWidget,
        previousContent: previousContent,
        previousTitle: previousTitle,
        // 保留更深层次的历史
        previousPreviousContent: previousPreviousContent,
        previousPreviousTitle: previousPreviousTitle,
        cwd: cwd,
        isCodex: isCodex,
      );
    });
  }

  void _handleBackToHome(int tabIndex) async {
    final currentTab = _tabs[tabIndex];

    // 如果有保存的上一个界面，则恢复到上一个界面
    if (currentTab.previousContent != null) {
      final newTab = TabInfo(
        id: 'home_${DateTime.now().millisecondsSinceEpoch}',
        type: TabType.home,
        title: currentTab.previousTitle ?? '主页',
        content: currentTab.previousContent!,
        // 保留更深层次的历史，这样从会话列表还能返回到主页
        previousContent: currentTab.previousPreviousContent,
        previousTitle: currentTab.previousPreviousTitle,
      );

      setState(() {
        _tabs[tabIndex].dispose();
        _tabs[tabIndex] = newTab;
      });
      return;
    }

    // 如果没有保存的上一个界面，则创建新的主页
    // 从 ConfigService 读取当前的后端选择，作为标签页的初始模式
    final configService = await ConfigService.getInstance();
    final preferredBackend = configService.preferredBackend;
    final initialMode = preferredBackend == 'codex' ? AgentMode.codex : AgentMode.claudeCode;

    final newTab = TabInfo(
      id: 'home_${DateTime.now().millisecondsSinceEpoch}',
      type: TabType.home,
      title: '主页',
      content: HomeScreen(
        claudeRepository: widget.claudeRepository,
        codexRepository: widget.codexRepository,
        onOpenChat: _openChatInCurrentTab,
        onNavigate: _replaceCurrentTab,
        onLogout: widget.onLogout,
        onGoBack: _goBackInCurrentTab, // 传递返回回调
        initialMode: initialMode,
      ),
    );

    setState(() {
      _tabs[tabIndex].dispose();
      _tabs[tabIndex] = newTab;
    });
  }

  void _addNewTab() {
    // 默认添加主页标签
    _addHomeTab();
  }

  void _closeTab(int index) {
    if (_tabs.length == 1) {
      // 最后一个标签，关闭后回到主页
      final oldTab = _tabs[index];
      setState(() {
        _tabs.removeAt(index);
      });
      oldTab.dispose();
      // 添加一个新的主页标签
      _addHomeTab();
      return;
    }

    final oldTab = _tabs[index];
    setState(() {
      _tabs.removeAt(index);
    });
    oldTab.dispose();

    // 重新创建 TabController
    final newIndex = index >= _tabs.length ? _tabs.length - 1 : index;
    _rebuildTabController(newIndex);
  }

  /// 显示标签页右键菜单
  void _showTabContextMenu(BuildContext context, int index, Offset position) {
    final tab = _tabs[index];

    // 只有 chat 类型的标签页才显示"在同目录新建对话"选项
    if (tab.type != TabType.chat || tab.cwd == null || tab.cwd!.isEmpty) {
      // 不是 chat 标签页或没有 cwd，只显示关闭选项
      showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
        items: [
          PopupMenuItem<String>(
            value: 'close',
            child: Row(
              children: [
                const Icon(Icons.close, size: 18),
                const SizedBox(width: 8),
                const Text('关闭标签页'),
              ],
            ),
          ),
        ],
      ).then((value) {
        if (value == 'close') {
          _closeTab(index);
        }
      });
      return;
    }

    // chat 标签页，显示完整菜单
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem<String>(
          value: 'new_claude',
          child: Row(
            children: [
              const Icon(Icons.add_comment_outlined, size: 18),
              const SizedBox(width: 8),
              const Text('在此目录新建 Claude 对话'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'new_codex',
          child: Row(
            children: [
              const Icon(Icons.code, size: 18),
              const SizedBox(width: 8),
              const Text('在此目录新建 Codex 对话'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'close',
          child: Row(
            children: [
              const Icon(Icons.close, size: 18),
              const SizedBox(width: 8),
              const Text('关闭标签页'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'new_claude') {
        _openNewChatInSameDirectory(tab.cwd!, tab.title, false);
      } else if (value == 'new_codex') {
        _openNewChatInSameDirectory(tab.cwd!, tab.title, true);
      } else if (value == 'close') {
        _closeTab(index);
      }
    });
  }

  /// 在同目录打开新对话
  void _openNewChatInSameDirectory(String cwd, String projectName, bool useCodex) {
    // 创建新的空 session
    final newSessionId = 'new_${DateTime.now().millisecondsSinceEpoch}';
    final session = Session(
      id: '', // 空 ID 表示新会话
      projectId: '', // 空项目 ID
      title: projectName, // 标题
      name: projectName,
      cwd: cwd,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // 选择对应的 repository
    final dynamic sessionRepository = useCodex
        ? ApiCodexRepository((widget.codexRepository as ApiCodexRepository).apiService)
        : ApiSessionRepository((widget.claudeRepository as dynamic).apiService);

    final tabId = 'chat_$newSessionId';

    // 创建新的 TabInfo
    final newTab = TabInfo(
      id: tabId,
      type: TabType.chat,
      title: projectName,
      content: Container(), // 临时占位
    );

    // 创建带回调的 ChatScreen
    final wrappedWidget = ChatScreen(
      key: ValueKey(tabId),
      session: session,
      repository: sessionRepository,
      onMessageComplete: () {
        final currentTabIndex = _tabs.indexWhere((tab) => tab.id == tabId);
        if (currentTabIndex != -1) {
          _handleMessageComplete(currentTabIndex);
        }
      },
      hasNewReplyNotifier: newTab.hasNewReplyNotifier,
    );

    // 更新 content
    final finalTab = TabInfo(
      id: newTab.id,
      type: newTab.type,
      title: newTab.title,
      content: wrappedWidget,
      cwd: cwd,
      isCodex: useCodex,
    );

    // 添加新标签页
    setState(() {
      _tabs.add(finalTab);
    });

    // 切换到新标签页
    _rebuildTabController(_tabs.length - 1);
  }

  // 处理标签的消息完成通知
  void _handleMessageComplete(int tabIndex) {
    print('DEBUG: _handleMessageComplete called, tabIndex=$tabIndex, currentIndex=$_currentIndex');

    // 检查是否启用了通知
    final settingsService = AppSettingsService();
    print('DEBUG: notificationsEnabled=${settingsService.notificationsEnabled}');

    if (!settingsService.notificationsEnabled) {
      print('DEBUG: Notifications disabled, skipping');
      return; // 通知已禁用，不显示
    }

    // 播放通知提示音
    final soundService = NotificationSoundService();
    soundService.setVolume(settingsService.notificationVolume);
    soundService.playNotificationSound();

    // 如果是当前标签页，显示简短的 SnackBar 提示
    if (tabIndex == _currentIndex && tabIndex < _tabs.length) {
      print('DEBUG: Showing completion notification for current tab');
      if (context.mounted) {
        final primaryColor = Theme.of(context).colorScheme.primary;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                const Text('消息已完成'),
              ],
            ),
            backgroundColor: primaryColor,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              bottom: MediaQuery.of(context).size.height - 100,
              left: 16,
              right: 16,
            ),
          ),
        );
      }
      return;
    }

    // 后台标签页的通知（保持原有逻辑）
    if (tabIndex != _currentIndex && tabIndex < _tabs.length) {
      print('DEBUG: Showing notification for background tab');
      setState(() {
        _tabs[tabIndex].hasNewReply = true;
        _tabs[tabIndex].hasNewReplyNotifier.value = true;
      });

      // 显示通知界面
      if (context.mounted) {
        final primaryColor = Theme.of(context).colorScheme.primary;
        // 显示顶部MaterialBanner通知（比SnackBar更显眼）
        ScaffoldMessenger.of(context).showMaterialBanner(
          MaterialBanner(
            backgroundColor: primaryColor.withOpacity(0.95),
            content: Row(
              children: [
                const Icon(Icons.chat, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${_tabs[tabIndex].title} 有新回复',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                  _tabController.animateTo(tabIndex);
                },
                child: const Text(
                  '查看',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                },
                child: const Text(
                  '关闭',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        );

        // 3秒后自动隐藏
        Future.delayed(const Duration(seconds: 3), () {
          if (context.mounted) {
            ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
          }
        });
      }
    }
  }

  void _rebuildTabController(int initialIndex) {
    _tabController.dispose();
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: initialIndex,
    );
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _currentIndex = _tabController.index;
          // 切换到标签时清除新回复标记
          if (_currentIndex < _tabs.length) {
            _tabs[_currentIndex].hasNewReply = false;
            _tabs[_currentIndex].hasNewReplyNotifier.value = false;
          }
        });
      }
    });

    setState(() {
      _currentIndex = initialIndex;
      // 初始标签也清除标记
      if (_currentIndex < _tabs.length) {
        _tabs[_currentIndex].hasNewReply = false;
        _tabs[_currentIndex].hasNewReplyNotifier.value = false;
      }
    });
  }

  // ==================== 分屏模式相关方法 ====================

  /// 切换分屏模式
  void _toggleSplitScreen() {
    // 移动端不支持分屏
    if (!_isDesktop) {
      return;
    }

    if (_isSplitScreen) {
      // 关闭分屏：清理右侧所有标签
      setState(() {
        _isSplitScreen = false;
      });
      _closeAllRightTabs();
    } else {
      // 开启分屏：先设置状态，再添加标签
      setState(() {
        _isSplitScreen = true;
      });
      _addRightHomeTab();
    }
  }

  /// 为右侧面板添加主页标签
  Future<void> _addRightHomeTab() async {
    final configService = await ConfigService.getInstance();
    final preferredBackend = configService.preferredBackend;
    final initialMode = preferredBackend == 'codex' ? AgentMode.codex : AgentMode.claudeCode;

    final newTab = TabInfo(
      id: 'right_home_${DateTime.now().millisecondsSinceEpoch}',
      type: TabType.home,
      title: '主页',
      content: HomeScreen(
        claudeRepository: widget.claudeRepository,
        codexRepository: widget.codexRepository,
        onOpenChat: _openChatInRightCurrentTab,
        onNavigate: _replaceRightCurrentTab,
        onLogout: widget.onLogout,
        onGoBack: _goBackInRightCurrentTab,
        initialMode: initialMode,
      ),
    );

    setState(() {
      _rightTabs.add(newTab);
    });

    _rebuildRightTabController(_rightTabs.length - 1);
  }

  /// 关闭右侧所有标签
  void _closeAllRightTabs() {
    _rightTabController?.dispose();
    _rightTabController = null;
    for (var tab in _rightTabs) {
      tab.dispose();
    }
    _rightTabs.clear();
    _rightCurrentIndex = 0;
  }

  /// 右侧面板：替换当前标签页内容
  void _replaceRightCurrentTab({
    required String id,
    required String title,
    required Widget content,
  }) {
    if (_rightTabs.isEmpty || _rightCurrentIndex >= _rightTabs.length) return;
    final currentTab = _rightTabs[_rightCurrentIndex];

    final newTab = TabInfo(
      id: id,
      type: TabType.home,
      title: title,
      content: content,
      previousContent: currentTab.content,
      previousTitle: currentTab.title,
      previousPreviousContent: currentTab.previousContent,
      previousPreviousTitle: currentTab.previousTitle,
    );

    setState(() {
      _rightTabs[_rightCurrentIndex] = newTab;
    });
  }

  /// 右侧面板：返回上一个界面
  void _goBackInRightCurrentTab() {
    if (_rightTabs.isEmpty || _rightCurrentIndex >= _rightTabs.length) return;
    final currentTab = _rightTabs[_rightCurrentIndex];

    Widget? targetContent = currentTab.previousContent;
    String? targetTitle = currentTab.previousTitle;

    if (currentTab.previousPreviousContent != null) {
      targetContent = currentTab.previousPreviousContent;
      targetTitle = currentTab.previousPreviousTitle;
    }

    if (targetContent != null) {
      final restoredTab = TabInfo(
        id: 'right_home_${DateTime.now().millisecondsSinceEpoch}',
        type: TabType.home,
        title: targetTitle ?? '主页',
        content: targetContent,
      );

      setState(() {
        _rightTabs[_rightCurrentIndex] = restoredTab;
      });
    }
  }

  /// 右侧面板：在当前标签页打开聊天
  void _openChatInRightCurrentTab({
    required String sessionId,
    required String sessionName,
    required Widget chatWidget,
  }) {
    if (_rightTabs.isEmpty || _rightCurrentIndex >= _rightTabs.length) return;

    final existingIndex = _rightTabs.indexWhere(
      (tab) => tab.id == 'right_chat_$sessionId',
    );

    if (existingIndex != -1) {
      _rightTabController?.animateTo(existingIndex);
      return;
    }

    final targetIndex = _rightCurrentIndex;
    final tabId = 'right_chat_$sessionId';

    final newTab = TabInfo(
      id: tabId,
      type: TabType.chat,
      title: sessionName,
      content: Container(),
    );

    Widget wrappedWidget = chatWidget;
    if (chatWidget is ChatScreen) {
      wrappedWidget = ChatScreen(
        key: ValueKey(tabId),
        session: chatWidget.session,
        repository: chatWidget.repository,
        onMessageComplete: () {
          final currentTabIndex = _rightTabs.indexWhere((tab) => tab.id == tabId);
          if (currentTabIndex != -1) {
            _handleRightMessageComplete(currentTabIndex);
          }
        },
        hasNewReplyNotifier: newTab.hasNewReplyNotifier,
        onBack: () => _handleRightBackToHome(targetIndex),
      );
    }

    String? cwd;
    bool isCodex = false;
    if (chatWidget is ChatScreen) {
      cwd = chatWidget.session.cwd;
      isCodex = chatWidget.repository is ApiCodexRepository;
    }

    setState(() {
      final currentTab = _rightTabs[_rightCurrentIndex];
      final previousContent = currentTab.content;
      final previousTitle = currentTab.title;
      final previousPreviousContent = currentTab.previousContent;
      final previousPreviousTitle = currentTab.previousTitle;

      currentTab.dispose();
      _rightTabs[_rightCurrentIndex] = TabInfo(
        id: tabId,
        type: TabType.chat,
        title: sessionName,
        content: wrappedWidget,
        previousContent: previousContent,
        previousTitle: previousTitle,
        previousPreviousContent: previousPreviousContent,
        previousPreviousTitle: previousPreviousTitle,
        cwd: cwd,
        isCodex: isCodex,
      );
    });
  }

  /// 右侧面板：返回主页
  void _handleRightBackToHome(int tabIndex) async {
    final currentTab = _rightTabs[tabIndex];

    if (currentTab.previousContent != null) {
      final newTab = TabInfo(
        id: 'right_home_${DateTime.now().millisecondsSinceEpoch}',
        type: TabType.home,
        title: currentTab.previousTitle ?? '主页',
        content: currentTab.previousContent!,
        previousContent: currentTab.previousPreviousContent,
        previousTitle: currentTab.previousPreviousTitle,
      );

      setState(() {
        _rightTabs[tabIndex].dispose();
        _rightTabs[tabIndex] = newTab;
      });
      return;
    }

    final configService = await ConfigService.getInstance();
    final preferredBackend = configService.preferredBackend;
    final initialMode = preferredBackend == 'codex' ? AgentMode.codex : AgentMode.claudeCode;

    final newTab = TabInfo(
      id: 'right_home_${DateTime.now().millisecondsSinceEpoch}',
      type: TabType.home,
      title: '主页',
      content: HomeScreen(
        claudeRepository: widget.claudeRepository,
        codexRepository: widget.codexRepository,
        onOpenChat: _openChatInRightCurrentTab,
        onNavigate: _replaceRightCurrentTab,
        onLogout: widget.onLogout,
        onGoBack: _goBackInRightCurrentTab,
        initialMode: initialMode,
      ),
    );

    setState(() {
      _rightTabs[tabIndex].dispose();
      _rightTabs[tabIndex] = newTab;
    });
  }

  /// 右侧面板：添加新标签
  void _addRightNewTab() {
    _addRightHomeTab();
  }

  /// 右侧面板：关闭标签
  void _closeRightTab(int index) {
    if (_rightTabs.length == 1) {
      // 最后一个标签，关闭后回到主页
      final oldTab = _rightTabs[index];
      setState(() {
        _rightTabs.removeAt(index);
      });
      oldTab.dispose();
      _addRightHomeTab();
      return;
    }

    final oldTab = _rightTabs[index];
    setState(() {
      _rightTabs.removeAt(index);
    });
    oldTab.dispose();

    final newIndex = index >= _rightTabs.length ? _rightTabs.length - 1 : index;
    _rebuildRightTabController(newIndex);
  }

  /// 右侧面板：显示标签右键菜单
  void _showRightTabContextMenu(BuildContext context, int index, Offset position) {
    final tab = _rightTabs[index];

    if (tab.type != TabType.chat || tab.cwd == null || tab.cwd!.isEmpty) {
      showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
        items: [
          PopupMenuItem<String>(
            value: 'close',
            child: Row(
              children: [
                const Icon(Icons.close, size: 18),
                const SizedBox(width: 8),
                const Text('关闭标签页'),
              ],
            ),
          ),
        ],
      ).then((value) {
        if (value == 'close') {
          _closeRightTab(index);
        }
      });
      return;
    }

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem<String>(
          value: 'new_claude',
          child: Row(
            children: [
              const Icon(Icons.add_comment_outlined, size: 18),
              const SizedBox(width: 8),
              const Text('在此目录新建 Claude 对话'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'new_codex',
          child: Row(
            children: [
              const Icon(Icons.code, size: 18),
              const SizedBox(width: 8),
              const Text('在此目录新建 Codex 对话'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'close',
          child: Row(
            children: [
              const Icon(Icons.close, size: 18),
              const SizedBox(width: 8),
              const Text('关闭标签页'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'new_claude') {
        _openRightNewChatInSameDirectory(tab.cwd!, tab.title, false);
      } else if (value == 'new_codex') {
        _openRightNewChatInSameDirectory(tab.cwd!, tab.title, true);
      } else if (value == 'close') {
        _closeRightTab(index);
      }
    });
  }

  /// 右侧面板：在同目录打开新对话
  void _openRightNewChatInSameDirectory(String cwd, String projectName, bool useCodex) {
    final newSessionId = 'new_${DateTime.now().millisecondsSinceEpoch}';
    final session = Session(
      id: '',
      projectId: '',
      title: projectName,
      name: projectName,
      cwd: cwd,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final dynamic sessionRepository = useCodex
        ? ApiCodexRepository((widget.codexRepository as ApiCodexRepository).apiService)
        : ApiSessionRepository((widget.claudeRepository as dynamic).apiService);

    final tabId = 'right_chat_$newSessionId';

    final newTab = TabInfo(
      id: tabId,
      type: TabType.chat,
      title: projectName,
      content: Container(),
    );

    final wrappedWidget = ChatScreen(
      key: ValueKey(tabId),
      session: session,
      repository: sessionRepository,
      onMessageComplete: () {
        final currentTabIndex = _rightTabs.indexWhere((tab) => tab.id == tabId);
        if (currentTabIndex != -1) {
          _handleRightMessageComplete(currentTabIndex);
        }
      },
      hasNewReplyNotifier: newTab.hasNewReplyNotifier,
    );

    final finalTab = TabInfo(
      id: newTab.id,
      type: newTab.type,
      title: newTab.title,
      content: wrappedWidget,
      cwd: cwd,
      isCodex: useCodex,
    );

    setState(() {
      _rightTabs.add(finalTab);
    });

    _rebuildRightTabController(_rightTabs.length - 1);
  }

  /// 右侧面板：处理消息完成通知
  void _handleRightMessageComplete(int tabIndex) {
    final settingsService = AppSettingsService();
    if (!settingsService.notificationsEnabled) return;

    final soundService = NotificationSoundService();
    soundService.setVolume(settingsService.notificationVolume);
    soundService.playNotificationSound();

    if (tabIndex == _rightCurrentIndex && tabIndex < _rightTabs.length) {
      if (context.mounted) {
        final primaryColor = Theme.of(context).colorScheme.primary;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                const Text('消息已完成'),
              ],
            ),
            backgroundColor: primaryColor,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              bottom: MediaQuery.of(context).size.height - 100,
              left: 16,
              right: 16,
            ),
          ),
        );
      }
      return;
    }

    if (tabIndex != _rightCurrentIndex && tabIndex < _rightTabs.length) {
      setState(() {
        _rightTabs[tabIndex].hasNewReply = true;
        _rightTabs[tabIndex].hasNewReplyNotifier.value = true;
      });

      if (context.mounted) {
        final primaryColor = Theme.of(context).colorScheme.primary;
        ScaffoldMessenger.of(context).showMaterialBanner(
          MaterialBanner(
            backgroundColor: primaryColor.withOpacity(0.95),
            content: Row(
              children: [
                const Icon(Icons.chat, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${_rightTabs[tabIndex].title} 有新回复',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                  _rightTabController?.animateTo(tabIndex);
                },
                child: const Text(
                  '查看',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                },
                child: const Text(
                  '关闭',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        );

        Future.delayed(const Duration(seconds: 3), () {
          if (context.mounted) {
            ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
          }
        });
      }
    }
  }

  /// 重建右侧 TabController
  void _rebuildRightTabController(int initialIndex) {
    _rightTabController?.dispose();
    _rightTabController = TabController(
      length: _rightTabs.length,
      vsync: this,
      initialIndex: initialIndex,
    );
    _rightTabController!.addListener(() {
      if (_rightTabController!.indexIsChanging) {
        setState(() {
          _rightCurrentIndex = _rightTabController!.index;
          if (_rightCurrentIndex < _rightTabs.length) {
            _rightTabs[_rightCurrentIndex].hasNewReply = false;
            _rightTabs[_rightCurrentIndex].hasNewReplyNotifier.value = false;
          }
        });
      }
    });

    setState(() {
      _rightCurrentIndex = initialIndex;
      if (_rightCurrentIndex < _rightTabs.length) {
        _rightTabs[_rightCurrentIndex].hasNewReply = false;
        _rightTabs[_rightCurrentIndex].hasNewReplyNotifier.value = false;
      }
    });
  }

  // ==================== 分屏模式相关方法结束 ====================

  @override
  void dispose() {
    _tabController.dispose();
    for (var tab in _tabs) {
      tab.dispose();
    }
    // 清理右侧面板
    _rightTabController?.dispose();
    for (var tab in _rightTabs) {
      tab.dispose();
    }
    super.dispose();
  }

  // 获取AppBar标题
  String _getAppBarTitle() {
    if (_tabs.isEmpty) return 'CodeAgent Hub';

    final currentTab = _tabs[_currentIndex];

    // 如果是主页标签
    if (currentTab.type == TabType.home) {
      final content = currentTab.content;

      // 检查是否是 SessionListScreen（项目的会话列表）
      if (content is SessionListScreen) {
        // 获取 SessionListScreen 的 repository 来判断模式
        if (content.repository is CodexRepository) {
          return 'Codex';
        } else {
          return 'Claude Code';
        }
      }

      // 如果是 HomeScreen，显示 CodeAgent Hub
      return 'CodeAgent Hub';
    }

    // 如果是对话标签，检查是哪个后端
    if (currentTab.type == TabType.chat && currentTab.content is ChatScreen) {
      final chatScreen = currentTab.content as ChatScreen;
      // 判断repository类型
      if (chatScreen.repository is ApiCodexRepository) {
        return 'Codex';
      } else {
        return 'Claude Code';
      }
    }

    return 'CodeAgent Hub';
  }

  // 判断是否为桌面平台
  bool get _isDesktop {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  /// 构建紧凑的图标按钮（桌面端浏览器风格）
  Widget _buildCompactIconButton({
    required IconData icon,
    required double size,
    required String tooltip,
    required VoidCallback onPressed,
    required Color dividerColor,
  }) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: dividerColor, width: 1),
        ),
      ),
      child: IconButton(
        icon: Icon(icon, size: size),
        onPressed: onPressed,
        tooltip: tooltip,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        constraints: const BoxConstraints(
          minWidth: 32,
          minHeight: 32,
        ),
      ),
    );
  }

  /// 构建单个面板的标签栏
  Widget _buildTabBar({
    required List<TabInfo> tabs,
    required TabController controller,
    required void Function(int) onCloseTab,
    required void Function(BuildContext, int, Offset) onContextMenu,
    required VoidCallback onAddTab,
    required Color cardColor,
    required Color primaryColor,
    required Color dividerColor,
    bool showOpenSplitButton = false, // 左侧面板：显示"开启分屏"按钮
    bool showCloseSplitButton = false, // 右侧面板：显示"关闭分屏"按钮
  }) {
    // 构建标签列表
    final tabWidgets = tabs.asMap().entries.map((entry) {
      final index = entry.key;
      final tab = entry.value;
      return _buildTabItem(tab, index, primaryColor, onCloseTab, onContextMenu);
    }).toList();

    // 桌面端：添加按钮在标签后面（浏览器风格）
    if (_isDesktop) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final bottomLineColor = isDark ? Colors.white : Colors.black;

      return Container(
        color: cardColor,
        child: Row(
          children: [
            // 标签栏 + 添加按钮区域（用 Stack 让底线延伸到整个宽度）
            Expanded(
              child: Stack(
                children: [
                  // 底层：底线延伸到整个宽度
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 1,
                      color: bottomLineColor,
                    ),
                  ),
                  // 上层：TabBar + 添加按钮
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // TabBar 保持原样
                        TabBar(
                          controller: controller,
                          isScrollable: true,
                          tabAlignment: TabAlignment.start,
                          tabs: tabWidgets,
                        ),
                        // 添加按钮紧跟在标签后面
                        _AddTabButton(
                          onTap: onAddTab,
                          dividerColor: dividerColor,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // 开启分屏按钮（仅左侧面板，未分屏时显示）
            if (showOpenSplitButton && !_isSplitScreen)
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: dividerColor, width: 1),
                  ),
                ),
                child: MouseRegion(
                  onEnter: (_) => setState(() => _hoveringSplitButton = true),
                  onExit: (_) => setState(() => _hoveringSplitButton = false),
                  child: AnimatedOpacity(
                    opacity: _hoveringSplitButton ? 1.0 : 0.3,
                    duration: const Duration(milliseconds: 150),
                    child: _buildCompactIconButton(
                      icon: Icons.book,
                      size: 16,
                      tooltip: '开启分屏',
                      onPressed: _toggleSplitScreen,
                      dividerColor: dividerColor,
                    ),
                  ),
                ),
              ),
            // 关闭分屏按钮（仅右侧面板，分屏时显示）
            if (showCloseSplitButton && _isSplitScreen)
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: dividerColor, width: 1),
                  ),
                ),
                child: MouseRegion(
                  onEnter: (_) => setState(() => _hoveringSplitButton = true),
                  onExit: (_) => setState(() => _hoveringSplitButton = false),
                  child: AnimatedOpacity(
                    opacity: _hoveringSplitButton ? 1.0 : 0.3,
                    duration: const Duration(milliseconds: 150),
                    child: _buildCompactIconButton(
                      icon: Icons.menu_book,
                      size: 16,
                      tooltip: '关闭分屏',
                      onPressed: _toggleSplitScreen,
                      dividerColor: dividerColor,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    // 移动端：保持原有布局
    return Container(
      color: cardColor,
      child: Row(
        children: [
          Expanded(
            child: TabBar(
              controller: controller,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: tabWidgets,
            ),
          ),
          // 移动端：添加按钮在右侧
          Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: dividerColor, width: 1),
              ),
            ),
            child: IconButton(
              icon: const Icon(Icons.add, size: 20),
              onPressed: onAddTab,
              tooltip: '新建标签页',
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建单个标签项
  Widget _buildTabItem(
    TabInfo tab,
    int index,
    Color primaryColor,
    void Function(int) onCloseTab,
    void Function(BuildContext, int, Offset) onContextMenu,
  ) {
    return GestureDetector(
      onSecondaryTapUp: (details) {
        onContextMenu(context, index, details.globalPosition);
      },
      child: Tab(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              tab.type == TabType.home ? Icons.home_outlined : Icons.chat_outlined,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              tab.title.length > 12 ? '${tab.title.substring(0, 12)}...' : tab.title,
              style: const TextStyle(fontSize: 13),
            ),
            if (tab.hasNewReply) ...[
              const SizedBox(width: 4),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: primaryColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
            const SizedBox(width: 6),
            InkWell(
              onTap: () => onCloseTab(index),
              child: const Icon(Icons.close, size: 14),
            ),
          ],
        ),
      ),
    );
  }

  /// 用独立的 Navigator 包裹标签页内容
  /// 这样页面跳转（如打开设置）只会在当前标签页/面板内进行，不会覆盖整个屏幕
  Widget _wrapWithNavigator(TabInfo tab) {
    return Navigator(
      key: ValueKey('nav_${tab.id}'),
      onGenerateRoute: (settings) {
        return MaterialPageRoute(
          builder: (context) => tab.content,
          settings: settings,
        );
      },
    );
  }

  /// 构建可拖动的分隔条
  Widget _buildDraggableDivider(Color dividerColor, Color primaryColor) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onHorizontalDragStart: (details) {
          setState(() {
            _isDraggingDivider = true;
          });
        },
        onHorizontalDragUpdate: (details) {
          setState(() {
            // 获取屏幕宽度
            final RenderBox box = context.findRenderObject() as RenderBox;
            final screenWidth = box.size.width;

            // 计算新的分隔比例
            final dx = details.delta.dx;
            final newRatio = _splitRatio + (dx / screenWidth);

            // 限制范围在 0.2 到 0.8 之间（最小20%，最大80%）
            _splitRatio = newRatio.clamp(0.2, 0.8);
          });
        },
        onHorizontalDragEnd: (details) {
          setState(() {
            _isDraggingDivider = false;
          });
        },
        child: Container(
          width: 8,
          color: _isDraggingDivider ? primaryColor.withOpacity(0.3) : Colors.transparent,
          child: Center(
            child: Container(
              width: 1,
              color: dividerColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPanel({
    required List<TabInfo> tabs,
    required TabController controller,
    required void Function(int) onCloseTab,
    required void Function(BuildContext, int, Offset) onContextMenu,
    required VoidCallback onAddTab,
    required Color cardColor,
    required Color primaryColor,
    required Color dividerColor,
    bool showOpenSplitButton = false,
    bool showCloseSplitButton = false,
    Color? tabBarBackgroundColor, // 标签栏背景颜色（用于区分面板）
    PanelType panelType = PanelType.single, // 面板类型
    Color? contentBackgroundColor, // 内容区背景颜色
  }) {
    return Column(
      children: [
        // 标签栏
        PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _buildTabBar(
            tabs: tabs,
            controller: controller,
            onCloseTab: onCloseTab,
            onContextMenu: onContextMenu,
            onAddTab: onAddTab,
            cardColor: tabBarBackgroundColor ?? cardColor,
            primaryColor: primaryColor,
            dividerColor: dividerColor,
            showOpenSplitButton: showOpenSplitButton,
            showCloseSplitButton: showCloseSplitButton,
          ),
        ),
        // 内容区（包裹 PanelTheme 让子组件能获取面板信息）
        // 每个标签页内容用 Navigator 包裹，使页面跳转只在当前面板内进行
        Expanded(
          child: PanelTheme(
            data: PanelThemeData(
              panelType: panelType,
              backgroundColorOverride: contentBackgroundColor,
            ),
            child: TabBarView(
              controller: controller,
              children: tabs.map((tab) => _wrapWithNavigator(tab)).toList(),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final dividerColor = Theme.of(context).dividerColor;

    // 非分屏模式：使用原有布局
    if (!_isSplitScreen) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_getAppBarTitle()),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: _buildTabBar(
              tabs: _tabs,
              controller: _tabController,
              onCloseTab: _closeTab,
              onContextMenu: _showTabContextMenu,
              onAddTab: _addNewTab,
              cardColor: cardColor,
              primaryColor: primaryColor,
              dividerColor: dividerColor,
              showOpenSplitButton: true,
            ),
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: _tabs.map((tab) => _wrapWithNavigator(tab)).toList(),
        ),
      );
    }

    // 分屏模式：左右两个独立面板，隐藏顶部标题栏
    // 右侧面板背景色调整（可在此处修改）
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // ========== 右侧面板背景色配置 ==========
    // 调整这里的颜色来改变右侧面板的背景色
    // 深色模式：可以用 Colors.white.withOpacity(0.05) 变亮，或 Colors.black.withOpacity(0.1) 变暗
    // 浅色模式：可以用 Colors.black.withOpacity(0.03) 变暗，或 Colors.white.withOpacity(0.5) 变亮
    final rightPanelContentBgColor = isDark
        ? Color.alphaBlend(const Color(0xFFF7A55A).withOpacity(0.03), Theme.of(context).scaffoldBackgroundColor)
        : Color.alphaBlend(const Color(0xFFF7A55A).withOpacity(0.03), Theme.of(context).scaffoldBackgroundColor);
    // ========================================

    return Scaffold(
      body: Row(
        children: [
          // 左侧面板
          Expanded(
            flex: (_splitRatio * 1000).round(),
            child: _buildPanel(
              tabs: _tabs,
              controller: _tabController,
              onCloseTab: _closeTab,
              onContextMenu: _showTabContextMenu,
              onAddTab: _addNewTab,
              cardColor: cardColor,
              primaryColor: primaryColor,
              dividerColor: dividerColor,
              showOpenSplitButton: true,
              panelType: PanelType.left,
            ),
          ),
          // 可拖动的分隔条
          _buildDraggableDivider(dividerColor, primaryColor),
          // 右侧面板
          if (_rightTabController != null && _rightTabs.isNotEmpty)
            Expanded(
              flex: ((1.0 - _splitRatio) * 1000).round(),
              child: _buildPanel(
                tabs: _rightTabs,
                controller: _rightTabController!,
                onCloseTab: _closeRightTab,
                onContextMenu: _showRightTabContextMenu,
                onAddTab: _addRightNewTab,
                cardColor: cardColor,
                primaryColor: primaryColor,
                dividerColor: dividerColor,
                showCloseSplitButton: true,
                panelType: PanelType.right,
                contentBackgroundColor: rightPanelContentBgColor,
              ),
            ),
        ],
      ),
    );
  }
}

// 添加标签按钮 - 带 hover 效果
class _AddTabButton extends StatefulWidget {
  final VoidCallback onTap;
  final Color dividerColor;

  const _AddTabButton({
    required this.onTap,
    required this.dividerColor,
  });

  @override
  State<_AddTabButton> createState() => _AddTabButtonState();
}

class _AddTabButtonState extends State<_AddTabButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedOpacity(
          opacity: _isHovered ? 1.0 : 0.3,
          duration: const Duration(milliseconds: 150),
          child: Container(
            height: 48,
            width: 32,
            alignment: Alignment.center,
            child: Icon(
              Icons.add,
              size: 18,
              color: widget.dividerColor,
            ),
          ),
        ),
      ),
    );
  }
}
