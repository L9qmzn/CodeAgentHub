import 'dart:io';
import 'dart:convert';

class AuthService {
  static const String _fileName = 'user_auth.json';
  static AuthService? _instance;
  static const int _sessionDurationHours = 24; // 会话持续时间（小时）

  String? _username;
  String? _password;
  DateTime? _loginTime; // 登录时间戳
  bool _isInitialized = false;

  AuthService._();

  static Future<AuthService> getInstance() async {
    if (_instance == null) {
      _instance = AuthService._();
      await _instance!._init();
    }
    return _instance!;
  }

  Future<void> _init() async {
    if (!_isInitialized) {
      await _loadCredentials();
      _isInitialized = true;
    }
  }

  String _getAuthFilePath() {
    if (Platform.isAndroid) {
      // Android: 使用应用的data目录
      return '/data/data/com.example.cc_mobile/files/$_fileName';
    } else if (Platform.isWindows) {
      // Windows: 使用APPDATA目录
      final appData = Platform.environment['APPDATA'];
      if (appData != null) {
        final dir = Directory('$appData\\CCMobile');
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }
        return '$appData\\CCMobile\\$_fileName';
      }
    }
    // 其他平台或无法获取路径时，使用当前目录
    return _fileName;
  }

  // 简单的编码（Base64），不是加密但至少不是明文
  String _encodePassword(String password) {
    return base64Encode(utf8.encode(password));
  }

  String _decodePassword(String encoded) {
    return utf8.decode(base64Decode(encoded));
  }

  Future<void> _loadCredentials() async {
    try {
      final filePath = _getAuthFilePath();
      final file = File(filePath);
      if (await file.exists()) {
        final contents = await file.readAsString();
        final data = json.decode(contents) as Map<String, dynamic>;
        _username = data['username'] as String?;

        // 加载密码和登录时间
        final encodedPassword = data['password'] as String?;
        final loginTimeStr = data['login_time'] as String?;

        if (encodedPassword != null && loginTimeStr != null) {
          final loginTime = DateTime.parse(loginTimeStr);
          final now = DateTime.now();

          // 检查是否在24小时内
          if (now.difference(loginTime).inHours < _sessionDurationHours) {
            _password = _decodePassword(encodedPassword);
            _loginTime = loginTime;
            print('DEBUG AuthService: Session valid, auto-login successful');
          } else {
            print('DEBUG AuthService: Session expired, need re-login');
          }
        }

        print('DEBUG AuthService: Loaded credentials from: $filePath');
      }
    } catch (e) {
      print('Error loading credentials: $e');
    }
  }

  Future<void> _saveCredentials() async {
    try {
      final filePath = _getAuthFilePath();
      final file = File(filePath);
      final data = <String, dynamic>{
        'username': _username,
      };

      // 保存密码和登录时间
      if (_password != null && _loginTime != null) {
        data['password'] = _encodePassword(_password!);
        data['login_time'] = _loginTime!.toIso8601String();
      }

      await file.writeAsString(json.encode(data));
      print('DEBUG AuthService: Saved credentials to: $filePath');
    } catch (e) {
      print('Error saving credentials: $e');
    }
  }

  // 设置登录凭证并保存（带时间戳）
  Future<void> setCredentials(String username, String password) async {
    _username = username;
    _password = password;
    _loginTime = DateTime.now();
    await _saveCredentials();
  }

  // 保存用户名（供下次自动填充，不保存密码）
  Future<void> saveUsername(String username) async {
    _username = username;
    // 只保存用户名，不保存密码
    final filePath = _getAuthFilePath();
    final file = File(filePath);
    await file.writeAsString(json.encode({
      'username': _username,
    }));
  }

  // 登出（清除密码和登录时间，保留用户名供下次自动填充）
  Future<void> logout() async {
    _password = null;
    _loginTime = null;
    // 只保存用户名
    await saveUsername(_username ?? '');
  }

  // 检查是否已登录（需要同时有用户名和密码）
  bool get isLoggedIn => _username != null && _password != null;

  // 获取保存的用户名（用于自动填充）
  String? get savedUsername => _username;

  // 获取用户名
  String? get username => _username;

  // 获取密码（用于 HTTP Basic Auth）
  String? get password => _password;

  // 获取 Basic Auth header 值
  String? get basicAuthHeader {
    if (_username == null || _password == null) return null;
    final credentials = '$_username:$_password';
    final encoded = base64Encode(utf8.encode(credentials));
    return 'Basic $encoded';
  }
}
