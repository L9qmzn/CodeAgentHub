import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import '../../core/theme/app_theme.dart';
import '../../config/app_config.dart';
import '../../services/auth_service.dart';
import '../../services/config_service.dart';
import '../../services/backend_process_service.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback? onLoginSuccess;

  const LoginScreen({
    super.key,
    this.onLoginSuccess,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  bool _isStartingBackend = false;
  bool _showStartBackendButton = false;

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  Future<void> _loadSavedData() async {
    final authService = await AuthService.getInstance();
    final configService = await ConfigService.getInstance();

    setState(() {
      _apiUrlController.text = configService.apiBaseUrl;
      if (authService.savedUsername != null) {
        _usernameController.text = authService.savedUsername!;
      }
    });
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final apiUrl = _apiUrlController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    try {
      // 验证凭证是否正确 - 尝试调用API
      final credentials = '$username:$password';
      final encoded = base64Encode(utf8.encode(credentials));
      final authHeader = 'Basic $encoded';

      final response = await http.get(
        Uri.parse('$apiUrl/sessions'),
        headers: {
          'Authorization': authHeader,
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        // 登录成功
        print('DEBUG LoginScreen: Login successful with URL: $apiUrl');
        final authService = await AuthService.getInstance();
        final configService = await ConfigService.getInstance();

        await authService.setCredentials(username, password);
        print('DEBUG LoginScreen: About to save API URL: $apiUrl');
        await configService.setApiBaseUrl(apiUrl);
        print('DEBUG LoginScreen: API URL saved, calling onLoginSuccess');

        if (mounted) {
          // 调用回调通知登录成功
          widget.onLoginSuccess?.call();
        }
      } else if (response.statusCode == 401) {
        // 认证失败
        setState(() {
          _errorMessage = '用户名或密码错误';
          _isLoading = false;
        });
      } else {
        // 其他错误
        setState(() {
          _errorMessage = '登录失败: HTTP ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        if (e.toString().contains('TimeoutException')) {
          _errorMessage = '连接超时，请检查网络和服务器地址';
        } else if (e.toString().contains('SocketException')) {
          _errorMessage = '无法连接到服务器，请检查服务器地址';
        } else {
          _errorMessage = '登录失败: $e';
        }
        _isLoading = false;

        // 在桌面平台上，连接失败时显示启动后端按钮
        if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
          final apiUrl = _apiUrlController.text.trim();
          // 检查是否是本地地址（127.0.0.1 或 localhost）
          if (apiUrl.contains('127.0.0.1') || apiUrl.contains('localhost')) {
            _showStartBackendButton = true;
          }
        }
      });
    }
  }

  Future<void> _handleStartBackend() async {
    setState(() {
      _isStartingBackend = true;
      _errorMessage = null;
    });

    try {
      // 从用户填写的 API URL 中解析端口
      final apiUrl = _apiUrlController.text.trim();
      int? port;
      try {
        final uri = Uri.parse(apiUrl);
        port = uri.port;
        // 如果 URL 没有显式指定端口，默认使用 8207
        if (port == 0 || port == 80 || port == 443) {
          port = 8207;
        }
      } catch (e) {
        port = 8207; // 解析失败，使用默认端口
      }

      final backendService = BackendProcessService.getInstance();
      final started = await backendService.startBackend(port: port);

      if (started) {
        setState(() {
          _isStartingBackend = false;
          _showStartBackendButton = false;
          _errorMessage = null;
        });
        // 后端启动成功，提示用户重试登录
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('后端服务已启动在端口 $port，请重新登录'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // 检查是否是 Node.js 未安装导致的失败
        String errorMsg = '后端启动失败';
        try {
          final nodeCheck = await Process.run('node', ['--version']);
          if (nodeCheck.exitCode != 0) {
            errorMsg = '后端启动失败：Node.js 未安装\n请从 https://nodejs.org/ 下载并安装 Node.js';
          } else {
            errorMsg = '后端启动失败，端口 $port 可能被占用';
          }
        } catch (e) {
          errorMsg = '后端启动失败：Node.js 未安装\n请从 https://nodejs.org/ 下载并安装 Node.js';
        }

        setState(() {
          _isStartingBackend = false;
          _errorMessage = errorMsg;
        });
      }
    } catch (e) {
      setState(() {
        _isStartingBackend = false;
        _errorMessage = '后端启动失败: $e';
      });
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
    final dividerColor = theme.dividerColor;
    final textPrimary = colorScheme.onSurface;
    final textSecondary = appColors.textSecondary;
    final textTertiary = appColors.textTertiary;
    final errorColor = colorScheme.error;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo or App Name
                  Icon(
                    Icons.lock_outline,
                    size: 80,
                    color: primaryColor,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'CodeAgent Hub',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '请登录以继续',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: textSecondary,
                    ),
                  ),
                  const SizedBox(height: 48),

                  // API URL Field
                  TextFormField(
                    controller: _apiUrlController,
                    style: TextStyle(color: textPrimary),
                    decoration: InputDecoration(
                      labelText: 'API地址',
                      labelStyle: TextStyle(color: textSecondary),
                      prefixIcon: Icon(Icons.cloud, color: primaryColor),
                      filled: true,
                      fillColor: cardColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: dividerColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: dividerColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: primaryColor, width: 2),
                      ),
                      hintText: 'http://127.0.0.1:8207',
                      hintStyle: TextStyle(color: textTertiary),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return '请输入API地址';
                      }
                      if (!value.trim().startsWith('http://') && !value.trim().startsWith('https://')) {
                        return 'API地址必须以http://或https://开头';
                      }
                      return null;
                    },
                    enabled: !_isLoading,
                  ),
                  const SizedBox(height: 16),

                  // Username Field
                  TextFormField(
                    controller: _usernameController,
                    style: TextStyle(color: textPrimary),
                    decoration: InputDecoration(
                      labelText: '用户名',
                      labelStyle: TextStyle(color: textSecondary),
                      prefixIcon: Icon(Icons.person, color: primaryColor),
                      filled: true,
                      fillColor: cardColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: dividerColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: dividerColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: primaryColor, width: 2),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return '请输入用户名';
                      }
                      return null;
                    },
                    enabled: !_isLoading,
                  ),
                  const SizedBox(height: 16),

                  // Password Field
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: TextStyle(color: textPrimary),
                    decoration: InputDecoration(
                      labelText: '密码',
                      labelStyle: TextStyle(color: textSecondary),
                      prefixIcon: Icon(Icons.lock, color: primaryColor),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          color: textSecondary,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                      filled: true,
                      fillColor: cardColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: dividerColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: dividerColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: primaryColor, width: 2),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '请输入密码';
                      }
                      return null;
                    },
                    enabled: !_isLoading,
                    onFieldSubmitted: (_) => _handleLogin(),
                  ),
                  const SizedBox(height: 24),

                  // Error Message
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: errorColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: errorColor),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: errorColor, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(color: errorColor, fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Login Button
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: primaryColor.withOpacity(0.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              '登录',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),

                  // Start Backend Button (Windows only, shown when connection fails)
                  if (_showStartBackendButton) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: _isStartingBackend ? null : _handleStartBackend,
                        icon: _isStartingBackend
                            ? SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                                ),
                              )
                            : Icon(Icons.power_settings_new, color: primaryColor),
                        label: Text(
                          _isStartingBackend ? '正在启动...' : '启动本地后端',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: primaryColor,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: primaryColor, width: 2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
