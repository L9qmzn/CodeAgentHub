import 'dart:convert';
import 'dart:io';
import '../models/session_settings.dart';
import '../models/codex_user_settings.dart';

/// 会话设置服务 - 本地持久化存储每个会话的设置
class SessionSettingsService {
  static final SessionSettingsService _instance = SessionSettingsService._();
  factory SessionSettingsService() => _instance;
  SessionSettingsService._();

  bool _initialized = false;

  // 存储：sessionId -> SessionSettings (Claude Code)
  final Map<String, SessionSettings> _claudeSessionSettings = {};

  // 存储：sessionId -> CodexUserSettings (Codex)
  final Map<String, CodexUserSettings> _codexSessionSettings = {};

  Future<void> initialize() async {
    if (_initialized) return;
    await _loadSettings();
    _initialized = true;
  }

  // 获取配置文件路径
  String _getSettingsFilePath() {
    if (Platform.isAndroid) {
      return '/data/data/com.example.cc_mobile/files/session_settings.json';
    } else if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null) {
        final dir = Directory('$appData\\CCMobile');
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }
        return '$appData\\CCMobile\\session_settings.json';
      }
    }
    return 'session_settings.json';
  }

  // 加载设置
  Future<void> _loadSettings() async {
    try {
      final filePath = _getSettingsFilePath();
      final file = File(filePath);

      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;

        // 加载 Claude Code 会话设置
        if (json['claude_sessions'] != null) {
          final claudeSessions = json['claude_sessions'] as Map<String, dynamic>;
          claudeSessions.forEach((sessionId, settingsJson) {
            try {
              _claudeSessionSettings[sessionId] = SessionSettings.fromJson(
                settingsJson as Map<String, dynamic>,
              );
            } catch (e) {
              print('Error loading Claude session settings for $sessionId: $e');
            }
          });
        }

        // 加载 Codex 会话设置
        if (json['codex_sessions'] != null) {
          final codexSessions = json['codex_sessions'] as Map<String, dynamic>;
          codexSessions.forEach((sessionId, settingsJson) {
            try {
              _codexSessionSettings[sessionId] = CodexUserSettings.fromJson(
                settingsJson as Map<String, dynamic>,
              );
            } catch (e) {
              print('Error loading Codex session settings for $sessionId: $e');
            }
          });
        }

        print('Loaded settings for ${_claudeSessionSettings.length} Claude sessions and ${_codexSessionSettings.length} Codex sessions');
      }
    } catch (e) {
      print('Error loading session settings: $e');
    }
  }

  // 保存设置
  Future<void> _saveSettings() async {
    try {
      final filePath = _getSettingsFilePath();
      final file = File(filePath);

      final json = {
        'claude_sessions': _claudeSessionSettings.map(
          (sessionId, settings) => MapEntry(sessionId, settings.toJson()),
        ),
        'codex_sessions': _codexSessionSettings.map(
          (sessionId, settings) => MapEntry(sessionId, settings.toJson()),
        ),
      };

      await file.writeAsString(jsonEncode(json));
      print('Saved settings for ${_claudeSessionSettings.length} Claude sessions and ${_codexSessionSettings.length} Codex sessions');
    } catch (e) {
      print('Error saving session settings: $e');
    }
  }

  // ========== Claude Code 会话设置 ==========

  /// 获取 Claude Code 会话设置
  SessionSettings? getClaudeSessionSettings(String sessionId) {
    return _claudeSessionSettings[sessionId];
  }

  /// 保存 Claude Code 会话设置
  Future<void> saveClaudeSessionSettings(String sessionId, SessionSettings settings) async {
    _claudeSessionSettings[sessionId] = settings;
    await _saveSettings();
  }

  /// 删除 Claude Code 会话设置
  Future<void> removeClaudeSessionSettings(String sessionId) async {
    _claudeSessionSettings.remove(sessionId);
    await _saveSettings();
  }

  // ========== Codex 会话设置 ==========

  /// 获取 Codex 会话设置
  CodexUserSettings? getCodexSessionSettings(String sessionId) {
    return _codexSessionSettings[sessionId];
  }

  /// 保存 Codex 会话设置
  Future<void> saveCodexSessionSettings(String sessionId, CodexUserSettings settings) async {
    _codexSessionSettings[sessionId] = settings;
    await _saveSettings();
  }

  /// 删除 Codex 会话设置
  Future<void> removeCodexSessionSettings(String sessionId) async {
    _codexSessionSettings.remove(sessionId);
    await _saveSettings();
  }

  // ========== 清理 ==========

  /// 清除所有会话设置
  Future<void> clearAll() async {
    _claudeSessionSettings.clear();
    _codexSessionSettings.clear();
    await _saveSettings();
  }
}
