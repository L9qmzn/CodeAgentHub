import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../core/theme/app_theme.dart';
import '../../config/app_config.dart';
import '../../services/auth_service.dart';
import '../../services/config_service.dart';

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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
