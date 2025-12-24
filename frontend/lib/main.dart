import 'dart:io' show Platform, exit, File;
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path/path.dart' as path;
import 'core/theme/app_theme.dart';
import 'config/app_config.dart';
import 'screens/tab_manager_screen.dart';
import 'screens/auth/login_screen.dart';
import 'services/api_service.dart';
import 'services/codex_api_service.dart';
import 'services/auth_service.dart';
import 'services/config_service.dart';
import 'services/app_settings_service.dart';
import 'services/single_instance_service.dart';
import 'services/windows_registry_service.dart';
import 'services/backend_process_service.dart';
import 'services/shared_project_data_service.dart';
import 'repositories/api_project_repository.dart';
import 'repositories/api_codex_repository.dart';
import 'core/constants/colors.dart';

// 全局单实例服务
SingleInstanceService? _singleInstanceService;
// 全局后端进程服务
BackendProcessService? _backendProcessService;

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // 只在桌面平台初始化 window_manager
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();
  }

  // 解析启动参数（必须在使用这些参数之前）
  String? initialPath;

  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--path' && i + 1 < args.length) {
      initialPath = args[i + 1];
    }
  }

  print('DEBUG main: Command line args: $args');

  // 检查是否是以管理员身份运行来注册右键菜单
  if (Platform.isWindows && args.contains('--register-context-menu')) {
    // 以管理员身份运行，执行注册操作
    final result = await WindowsRegistryService.registerContextMenu();
    print('Register context menu result: ${result.success ? "success" : result.message}');
    // 注册完成后退出
    exit(result.success ? 0 : 1);
  }

  // 桌面平台在后台异步启动后端进程（不阻塞 UI）
  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    _backendProcessService = BackendProcessService.getInstance();
    // 异步启动，不等待结果，让 UI 先显示
    // 后端窗口始终隐藏，调试请使用 start_backend_debug.bat
    _backendProcessService!.startBackend().then((started) {
      if (started) {
        print('DEBUG main: Backend process started/detected successfully');
      } else {
        print('WARN main: Backend not started, user can manually start from login page');
      }
    }).catchError((e) {
      print('ERROR main: Failed to start backend: $e');
    });
  }

  // 只在桌面平台的 Release 模式使用单实例功能
  // Debug 模式下允许多实例运行，方便开发调试
  if (!kIsWeb &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
      kReleaseMode) {
    _singleInstanceService = SingleInstanceService();

    // 尝试成为主实例
    final isMainInstance = await _singleInstanceService!.tryBecomeMainInstance();

    if (!isMainInstance) {
      // 已有实例在运行
      if (initialPath != null) {
        // 发送路径给已有实例
        await _singleInstanceService!.sendPathToExistingInstance(initialPath);
      }
      // 退出当前进程
      exit(0);
    }
  }

  runApp(MyApp(
    initialPath: initialPath,
    singleInstanceService: _singleInstanceService,
    backendProcessService: _backendProcessService,
  ));
}

class MyApp extends StatefulWidget {
  final String? initialPath;
  final SingleInstanceService? singleInstanceService;
  final BackendProcessService? backendProcessService;

  const MyApp({
    super.key,
    this.initialPath,
    this.singleInstanceService,
    this.backendProcessService,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WindowListener {
  AuthService? _authService;
  ConfigService? _configService;
  final _settingsService = AppSettingsService();
  bool _isInitializing = true;

  // API services - 保持实例以便动态更新
  ApiService? _apiService;
  CodexApiService? _codexApiService;

  // 全局导航键，用于在 MaterialApp 上下文中显示对话框
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  // 标记是否需要显示管理员权限对话框（延迟到 MaterialApp 准备好后显示）
  bool _pendingAdminDialog = false;

  // 后端启动状态信息（用于显示启动提示）
  String? _backendStatusMessage;
  bool? _backendStartSuccess;
  bool _backendStarting = false; // 后端正在启动中

  @override
  void initState() {
    super.initState();
    _settingsService.addListener(_onSettingsChanged);

    // 如果有后端服务，立即标记为启动中（确保第一帧就显示正确状态）
    if (widget.backendProcessService != null) {
      _backendStarting = true;
    }

    _initializeServices();

    // 注册窗口关闭监听器（仅桌面平台）
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      windowManager.addListener(this);
    }
  }

  /// 检查后端启动状态并准备提示消息
  Future<void> _checkBackendStatus() async {
    if (widget.backendProcessService == null) return;

    final backendPort = widget.backendProcessService!.backendPort;

    // 轮询等待后端启动完成（最多 12 秒）
    const maxWaitTime = Duration(seconds: 12);
    const checkInterval = Duration(milliseconds: 500);
    final startTime = DateTime.now();

    while (DateTime.now().difference(startTime) < maxWaitTime) {
      if (!mounted) return;

      // 检查后端是否已经启动
      if (widget.backendProcessService!.isRunning) {
        // 后端启动成功，额外等待一小段时间确保后端完全准备好
        print('DEBUG main: Backend health check passed, waiting for full initialization...');
        await Future.delayed(const Duration(milliseconds: 800));

        if (mounted) {
          setState(() {
            _backendStarting = false;
            _backendStartSuccess = true;
          });
        }
        print('DEBUG main: Backend is ready, continuing initialization');
        return;
      }

      await Future.delayed(checkInterval);
    }

    // 超时，后端启动失败
    if (mounted) {
      setState(() {
        _backendStarting = false;
        _backendStatusMessage = '后端服务启动失败\n端口 $backendPort 可能被占用\n您可以在登录页手动启动';
        _backendStartSuccess = false;
      });

      // 延迟显示通知，确保 UI 准备好
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _showBackendStatusNotification();
      });
    }
  }

  /// 显示后端启动失败的通知（使用 SnackBar，仅失败时调用）
  void _showBackendStatusNotification() {
    if (!mounted || _backendStatusMessage == null) return;

    // 只在失败时显示提示
    if (_backendStartSuccess == true) return;

    final navigatorContext = _navigatorKey.currentContext;
    if (navigatorContext == null) {
      Future.delayed(const Duration(milliseconds: 500), () {
        _showBackendStatusNotification();
      });
      return;
    }

    ScaffoldMessenger.of(navigatorContext).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _backendStatusMessage!,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 6),
        backgroundColor: Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        action: SnackBarAction(
          label: '知道了',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  @override
  void dispose() {
    print('DEBUG main: Disposing resources');

    // 停止并释放共享项目数据服务的定时器
    try {
      SharedProjectDataService.instance.dispose();
      print('DEBUG main: SharedProjectDataService disposed');
    } catch (e) {
      print('DEBUG main: Error disposing SharedProjectDataService: $e');
    }

    _settingsService.removeListener(_onSettingsChanged);

    // 移除窗口关闭监听器
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      windowManager.removeListener(this);
    }

    super.dispose();
    print('DEBUG main: Dispose completed');
  }

  /// 窗口关闭事件（WindowListener 接口）
  @override
  Future<void> onWindowClose() async {
    print('DEBUG main: onWindowClose triggered');

    // 询问用户是否关闭后端
    bool? shouldStopBackend;
    if (widget.backendProcessService != null && widget.backendProcessService!.isRunning) {
      final navigatorContext = _navigatorKey.currentContext;
      if (navigatorContext != null && mounted) {
        shouldStopBackend = await _showBackendCloseDialog(navigatorContext);
      }
    }

    // 处理后端停止（如果用户选择关闭）
    if (shouldStopBackend == true && widget.backendProcessService != null) {
      // 显示"正在关闭后端"的加载对话框
      final navigatorContext = _navigatorKey.currentContext;
      if (navigatorContext != null && mounted) {
        _showStoppingBackendDialog(navigatorContext);
      }

      print('DEBUG main: Stopping backend, please wait...');
      // 等待后端完全停止
      await widget.backendProcessService!.stopBackend();
      print('DEBUG main: Backend stopped');

      // 额外等待，确保进程完全终止
      await Future.delayed(const Duration(milliseconds: 500));
    } else if (shouldStopBackend == false) {
      print('DEBUG main: User chose to keep backend running');
    } else if (shouldStopBackend == null) {
      print('DEBUG main: No backend running or service not available');
    }

    // 在退出之前手动释放资源（因为 exit(0) 不会触发 dispose）
    print('DEBUG main: Manually disposing resources before exit');

    // 停止并释放共享项目数据服务的定时器
    try {
      SharedProjectDataService.instance.dispose();
      print('DEBUG main: SharedProjectDataService disposed');
    } catch (e) {
      print('DEBUG main: Error disposing SharedProjectDataService: $e');
    }

    // 移除设置服务监听器
    _settingsService.removeListener(_onSettingsChanged);

    // 移除窗口关闭监听器
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      windowManager.removeListener(this);
    }

    // 取消阻止关闭，然后立即退出
    print('DEBUG main: Exiting application');
    await windowManager.setPreventClose(false);

    // 给系统一点时间清理资源
    await Future.delayed(const Duration(milliseconds: 100));

    // 使用 exit(0) 退出应用
    exit(0);
  }

  /// 显示"正在关闭后端"的加载对话框
  void _showStoppingBackendDialog(BuildContext context) {
    final appColors = context.appColors;
    final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;
    final cardColor = Theme.of(context).cardColor;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: cardColor,
          content: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 20),
              Text(
                '正在关闭后端服务...',
                style: TextStyle(color: textPrimary, fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 显示关闭后端确认对话框
  Future<bool?> _showBackendCloseDialog(BuildContext context) async {
    final appColors = context.appColors;
    final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final cardColor = Theme.of(context).cardColor;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: cardColor,
        title: Text('关闭后端服务？', style: TextStyle(color: textPrimary)),
        content: Text(
          '应用即将关闭，是否同时关闭后端服务？\n\n'
          '• 关闭：停止后端服务\n'
          '• 保持运行：后端继续运行，下次打开时可直接使用',
          style: TextStyle(color: appColors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext, false);
            },
            child: Text('保持运行', style: TextStyle(color: appColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext, true);
            },
            child: Text('关闭', style: TextStyle(color: primaryColor)),
          ),
        ],
      ),
    );
  }

  void _onSettingsChanged() {
    setState(() {}); // 重建应用以应用新设置
    _updateWindowTitleBarColor(); // 更新标题栏颜色
  }

  Future<void> _updateWindowTitleBarColor() async {
    // 只在桌面平台设置窗口标题栏
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      final isDark = _settingsService.darkModeEnabled;
      final backgroundColor = isDark ? const Color(0xFF121212) : const Color(0xFFFFFBF5);

      await windowManager.setTitleBarStyle(
        TitleBarStyle.normal,
        windowButtonVisibility: true,
      );

      // 设置标题栏背景色
      await windowManager.setBackgroundColor(backgroundColor);
    }
  }

  Future<void> _initializeServices() async {
    try {
      await _settingsService.initialize(); // 先初始化设置
      _authService = await AuthService.getInstance();
      _configService = await ConfigService.getInstance();

      // 修正配置中的无效地址（0.0.0.0 不能作为客户端连接地址，但保留端口）
      final currentUrl = _configService!.apiBaseUrl;
      if (currentUrl.contains('0.0.0.0')) {
        try {
          final uri = Uri.parse(currentUrl);
          final fixedUrl = 'http://127.0.0.1:${uri.port}';
          print('DEBUG main: Fixing invalid API URL in config: $currentUrl -> $fixedUrl');
          await _configService!.setApiBaseUrl(fixedUrl, isAutoConfig: true);
        } catch (e) {
          print('ERROR main: Failed to parse URL: $e, using default');
          await _configService!.setApiBaseUrl('http://127.0.0.1:8207', isAutoConfig: true);
        }
      }

      // 初始化标题栏颜色
      await _updateWindowTitleBarColor();

      // 设置窗口关闭前拦截（仅桌面平台）
      if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        await windowManager.setPreventClose(true);
        print('DEBUG main: Window close prevention enabled');
      }

      // Windows: 检查并注册右键菜单
      // 在 Release 模式下自动执行，Debug 模式下也执行以便测试
      if (Platform.isWindows) {
        print('DEBUG main: Will check context menu registration (kReleaseMode: $kReleaseMode)');
        // 使用 await 确保能正确捕获错误
        await _checkAndRegisterContextMenu();
      }

      // 等待后端启动完成（如果有后端服务）
      await _checkBackendStatus();
    } catch (e) {
      print('Error initializing services: $e');
    }
    setState(() {
      _isInitializing = false;
    });
  }

  /// 检查并注册 Windows 右键菜单
  Future<void> _checkAndRegisterContextMenu() async {
    print('DEBUG main: _checkAndRegisterContextMenu START');
    // 只在 Windows 平台执行
    if (!Platform.isWindows) {
      print('DEBUG main: Not Windows, skipping');
      return;
    }

    try {
      print('DEBUG main: Calling WindowsRegistryService.checkAndRegister()...');
      final result = await WindowsRegistryService.checkAndRegister();
      print('DEBUG main: Got result - status: ${result.status}, message: ${result.message}');

      switch (result.status) {
        case RegistryStatus.registered:
        case RegistryStatus.updated:
          print('DEBUG main: Showing success notification');
          // 注册/更新成功，显示通知
          _showRegistryNotification(result.message, isSuccess: true);
          break;

        case RegistryStatus.alreadyRegistered:
          print('DEBUG main: Already registered correctly, no action needed');
          // 已经正确注册，无需通知用户
          break;

        case RegistryStatus.needsAdmin:
          print('DEBUG main: NEEDS ADMIN - attempting UAC elevation directly');
          // 需要管理员权限，直接尝试触发 UAC 提权
          await _attemptUACElevation();
          break;

        case RegistryStatus.failed:
        case RegistryStatus.notSupported:
          print('DEBUG main: Failed or not supported - ${result.message}');
          break;
      }
    } catch (e) {
      print('DEBUG main: Exception in _checkAndRegisterContextMenu: $e');
    }
    print('DEBUG main: _checkAndRegisterContextMenu END');
  }

  /// 直接尝试 UAC 提权来注册右键菜单
  Future<void> _attemptUACElevation() async {
    print('DEBUG main: _attemptUACElevation - triggering UAC...');

    final success = await WindowsRegistryService.restartAsAdmin();

    print('DEBUG main: UAC elevation result: $success');

    if (!success) {
      // UAC 被用户取消或失败，显示提示对话框
      print('DEBUG main: UAC failed or cancelled, showing fallback dialog');
      _showAdminPermissionDialog();
    }
    // 如果 UAC 成功，会启动一个新的管理员进程来注册，当前进程继续运行
  }

  /// 显示管理员权限请求对话框（作为 UAC 失败后的备选方案）
  void _showAdminPermissionDialog() {
    print('DEBUG main: _showAdminPermissionDialog called');

    // 标记需要显示对话框，等待 MaterialApp 准备好
    setState(() {
      _pendingAdminDialog = true;
    });

    // 延迟更长时间，确保 MaterialApp 完全准备好
    Future.delayed(const Duration(milliseconds: 1500), () {
      _tryShowAdminDialog();
    });
  }

  /// 尝试显示管理员对话框（使用 navigatorKey）
  void _tryShowAdminDialog() {
    print('DEBUG main: _tryShowAdminDialog called');

    if (!_pendingAdminDialog) {
      print('DEBUG main: No pending admin dialog');
      return;
    }

    final navigatorContext = _navigatorKey.currentContext;
    print('DEBUG main: Navigator context: $navigatorContext');

    if (navigatorContext == null) {
      print('DEBUG main: Navigator context not ready, retrying in 500ms...');
      // 如果 context 还没准备好，延迟重试
      Future.delayed(const Duration(milliseconds: 500), () {
        _tryShowAdminDialog();
      });
      return;
    }

    // 清除标记
    _pendingAdminDialog = false;

    print('DEBUG main: Showing admin permission dialog with navigator context...');
    showDialog(
      context: navigatorContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('需要管理员权限'),
        content: const Text(
          '首次运行需要管理员权限来注册右键菜单功能。\n\n'
          '注册后，您可以在文件夹上右键选择"使用 CodeAgent Hub 打开"。\n\n'
          '是否以管理员身份重新运行？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('稍后再说'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              // 触发 UAC 提权
              final success = await WindowsRegistryService.restartAsAdmin();
              if (!success && navigatorContext.mounted) {
                ScaffoldMessenger.of(navigatorContext).showSnackBar(
                  const SnackBar(
                    content: Text('无法启动管理员权限请求，您可以手动右键程序选择"以管理员身份运行"'),
                    duration: Duration(seconds: 5),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 显示注册表相关通知
  void _showRegistryNotification(String message, {required bool isSuccess}) {
    // 延迟显示，确保 UI 已经准备好
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 5),
            backgroundColor: isSuccess ? Colors.green : Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
  }

  Widget _buildLoadingScreen() {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final primaryColor = colorScheme.primary;
        final textPrimary = colorScheme.onSurface;
        final textSecondary = colorScheme.onSurface.withOpacity(0.6);
        final backgroundColor = theme.scaffoldBackgroundColor;

        return Scaffold(
          backgroundColor: backgroundColor,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 应用图标
                Icon(
                  Icons.hub_outlined,
                  size: 80,
                  color: primaryColor,
                ),
                const SizedBox(height: 24),
                // 应用名称
                Text(
                  'CodeAgent Hub',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 48),
                // 加载指示器
                SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                  ),
                ),
                const SizedBox(height: 24),
                // 状态文本
                Text(
                  _backendStarting ? '正在启动后端服务...' : '正在初始化...',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 使用AppTheme.generate生成动态主题
    final theme = AppTheme.generate(
      isDark: _settingsService.darkModeEnabled,
      fontFamily: _settingsService.fontFamily.fontFamily,
      fontScale: _settingsService.fontSize.scale,
    );

    return MaterialApp(
      title: AppConfig.appName,
      theme: theme,
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey, // 添加导航键以便在 MaterialApp 上下文中显示对话框
      builder: (context, child) {
        // 应用全局字号缩放
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaleFactor: _settingsService.fontSize.scale,
          ),
          child: child!,
        );
      },
      home: _isInitializing
          ? _buildLoadingScreen()
          : _authService?.isLoggedIn == true
              ? _buildMainApp()
              : _buildLoginPrompt(),
    );
  }

  Widget _buildMainApp() {
    final apiUrl = _configService?.apiBaseUrl ?? AppConfig.apiBaseUrl;

    // 如果还没有创建 ApiService 实例，或者 URL 发生变化，则创建/更新
    if (_apiService == null) {
      print('DEBUG: Creating ApiService with URL: $apiUrl');
      _apiService = ApiService(
        baseUrl: apiUrl,
        authService: _authService,
      );
    } else if (_apiService!.baseUrl != apiUrl) {
      print('DEBUG: Updating ApiService URL from ${_apiService!.baseUrl} to $apiUrl');
      _apiService!.updateBaseUrl(apiUrl);
    }

    if (_codexApiService == null) {
      print('DEBUG: Creating CodexApiService with URL: $apiUrl');
      _codexApiService = CodexApiService(
        baseUrl: apiUrl,
        authService: _authService,
      );
    } else if (_codexApiService!.baseUrl != apiUrl) {
      print('DEBUG: Updating CodexApiService URL from ${_codexApiService!.baseUrl} to $apiUrl');
      _codexApiService!.updateBaseUrl(apiUrl);
    }

    final claudeRepository = ApiProjectRepository(_apiService!);
    final codexRepository = ApiCodexRepository(_codexApiService!);

    return TabManagerScreen(
      claudeRepository: claudeRepository,
      codexRepository: codexRepository,
      initialPath: widget.initialPath,
      singleInstanceService: widget.singleInstanceService,
      onLogout: () {
        setState(() {});
      },
      onApiUrlChanged: _handleApiUrlChanged,
    );
  }

  /// 当 API 地址变化时调用此方法
  Future<void> _handleApiUrlChanged(String newUrl) async {
    print('DEBUG: API URL changed to: $newUrl');

    // 更新 ApiService 实例
    _apiService?.updateBaseUrl(newUrl);
    _codexApiService?.updateBaseUrl(newUrl);

    // 触发重建
    setState(() {});
  }

  Widget _buildLoginPrompt() {
    return LoginScreen(
      onLoginSuccess: () async {
        // 登录成功后重新加载配置并刷新UI
        _configService = await ConfigService.getInstance();
        await _configService?.reload();
        print('DEBUG main.dart: ConfigService reloaded, URL is now: ${_configService?.apiBaseUrl}');
        setState(() {});
      },
    );
  }
}
