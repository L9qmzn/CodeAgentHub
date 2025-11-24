import 'dart:io' show Platform, exit;
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
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
import 'repositories/api_project_repository.dart';
import 'repositories/api_codex_repository.dart';

// 全局单实例服务
SingleInstanceService? _singleInstanceService;

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // 只在桌面平台初始化 window_manager
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();
  }

  // 检查是否是以管理员身份运行来注册右键菜单
  if (Platform.isWindows && args.contains('--register-context-menu')) {
    // 以管理员身份运行，执行注册操作
    final result = await WindowsRegistryService.registerContextMenu();
    print('Register context menu result: ${result.success ? "success" : result.message}');
    // 注册完成后退出
    exit(result.success ? 0 : 1);
  }

  // 解析启动参数，查找文件夹路径
  String? initialPath;
  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--path' && i + 1 < args.length) {
      initialPath = args[i + 1];
      break;
    }
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
  ));
}

class MyApp extends StatefulWidget {
  final String? initialPath;
  final SingleInstanceService? singleInstanceService;

  const MyApp({
    super.key,
    this.initialPath,
    this.singleInstanceService,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
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

  @override
  void initState() {
    super.initState();
    _settingsService.addListener(_onSettingsChanged);
    _initializeServices();
  }

  @override
  void dispose() {
    _settingsService.removeListener(_onSettingsChanged);
    super.dispose();
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

      // 初始化标题栏颜色
      await _updateWindowTitleBarColor();

      // Windows: 检查并注册右键菜单
      // 在 Release 模式下自动执行，Debug 模式下也执行以便测试
      if (Platform.isWindows) {
        print('DEBUG main: Will check context menu registration (kReleaseMode: $kReleaseMode)');
        // 使用 await 确保能正确捕获错误
        await _checkAndRegisterContextMenu();
      }
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
          ? Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            )
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
