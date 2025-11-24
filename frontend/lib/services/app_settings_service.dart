import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import '../models/user_settings.dart';
import '../models/codex_user_settings.dart';
import '../models/session_settings.dart';

/// Agent 模式
enum AgentMode {
  claudeCode('Claude Code'),
  codex('Codex');

  final String label;
  const AgentMode(this.label);
}

/// 字体选项
enum FontFamilyOption {
  system('系统默认', null),
  microsoftYaHei('微软雅黑', 'Microsoft YaHei'),
  notoSerifSC('Noto Serif SC', 'Noto Serif SC');

  final String label;
  final String? fontFamily;
  const FontFamilyOption(this.label, this.fontFamily);
}

/// 字号选项
enum FontSizeOption {
  small('小', 0.9),
  normal('正常', 1.0),
  large('大', 1.1),
  extraLarge('特大', 1.2);

  final String label;
  final double scale;
  const FontSizeOption(this.label, this.scale);
}

/// 应用设置服务（内存存储）
class AppSettingsService {
  static final AppSettingsService _instance = AppSettingsService._internal();

  factory AppSettingsService() => _instance;

  AppSettingsService._internal();

  // 界面设置
  bool _notificationsEnabled = true; // 默认开启通知
  bool _darkModeEnabled = false;
  double _notificationVolume = 0.5; // 通知音量（0.0 - 1.0）
  FontFamilyOption _fontFamily = FontFamilyOption.notoSerifSC; // 默认Noto Serif SC字体
  FontSizeOption _fontSize = FontSizeOption.normal; // 默认正常字号
  bool _hideToolCalls = false; // 全局隐藏工具调用设置

  // 全局 Agent 设置（内存缓存，从后端加载）
  ClaudeUserSettings? _claudeSettings;
  CodexUserSettings? _codexSettings;

  // 默认项目设置（用于新会话）
  SessionSettings? _defaultSessionSettings;

  // 通知回调（当设置变化时）
  final List<VoidCallback> _listeners = [];

  // 是否已初始化
  bool _initialized = false;

  // Getters - 界面设置
  bool get notificationsEnabled => _notificationsEnabled;
  bool get darkModeEnabled => _darkModeEnabled;
  double get notificationVolume => _notificationVolume;
  FontFamilyOption get fontFamily => _fontFamily;
  FontSizeOption get fontSize => _fontSize;
  bool get hideToolCalls => _hideToolCalls;

  // Getters - Agent 全局设置
  ClaudeUserSettings? get claudeSettings => _claudeSettings;
  CodexUserSettings? get codexSettings => _codexSettings;

  // Getter - 默认项目设置
  SessionSettings? get defaultSessionSettings => _defaultSessionSettings;

  // 初始化方法
  Future<void> initialize() async {
    if (_initialized) return;
    await _loadSettings();
    _initialized = true;
  }

  // 获取配置文件路径
  String _getSettingsFilePath() {
    if (Platform.isAndroid) {
      // Android: 使用应用的data目录
      return '/data/data/com.example.cc_mobile/files/app_settings.json';
    } else if (Platform.isWindows) {
      // Windows: 使用APPDATA目录
      final appData = Platform.environment['APPDATA'];
      if (appData != null) {
        final dir = Directory('$appData\\CCMobile');
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }
        return '$appData\\CCMobile\\app_settings.json';
      }
    }
    // 其他平台或无法获取路径时，使用当前目录
    return 'app_settings.json';
  }

  // 加载设置
  Future<void> _loadSettings() async {
    try {
      final filePath = _getSettingsFilePath();
      final file = File(filePath);

      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;

        _notificationsEnabled = json['notifications_enabled'] as bool? ?? true;
        _darkModeEnabled = json['dark_mode_enabled'] as bool? ?? false;
        _notificationVolume = (json['notification_volume'] as num?)?.toDouble() ?? 0.5;

        // 加载字体
        final fontFamilyName = json['font_family'] as String?;
        if (fontFamilyName != null) {
          _fontFamily = FontFamilyOption.values.firstWhere(
            (f) => f.name == fontFamilyName,
            orElse: () => FontFamilyOption.notoSerifSC,
          );
        }

        // 加载字号
        final fontSizeName = json['font_size'] as String?;
        if (fontSizeName != null) {
          _fontSize = FontSizeOption.values.firstWhere(
            (f) => f.name == fontSizeName,
            orElse: () => FontSizeOption.normal,
          );
        }

        // 加载隐藏工具调用设置
        _hideToolCalls = json['hide_tool_calls'] ?? false;

        // 加载默认项目设置
        final defaultSessionJson = json['default_session_settings'] as Map<String, dynamic>?;
        if (defaultSessionJson != null) {
          try {
            _defaultSessionSettings = SessionSettings.fromJson(defaultSessionJson);
          } catch (e) {
            print('Error parsing default session settings: $e');
          }
        }
      }
    } catch (e) {
      print('Error loading app settings: $e');
    }
  }

  // 保存设置
  Future<void> _saveSettings() async {
    try {
      final filePath = _getSettingsFilePath();
      final file = File(filePath);

      final json = {
        'notifications_enabled': _notificationsEnabled,
        'dark_mode_enabled': _darkModeEnabled,
        'notification_volume': _notificationVolume,
        'font_family': _fontFamily.name,
        'font_size': _fontSize.name,
        'hide_tool_calls': _hideToolCalls,
      };

      // 保存默认项目设置
      if (_defaultSessionSettings != null) {
        json['default_session_settings'] = _defaultSessionSettings!.toJson();
      }

      await file.writeAsString(jsonEncode(json));
    } catch (e) {
      print('Error saving app settings: $e');
    }
  }

  // Setters - 界面设置
  void setNotificationsEnabled(bool value) {
    _notificationsEnabled = value;
    _saveSettings();
    _notifyListeners();
  }

  void setDarkModeEnabled(bool value) {
    _darkModeEnabled = value;
    _saveSettings();
    _notifyListeners();
  }

  void setNotificationVolume(double value) {
    _notificationVolume = value.clamp(0.0, 1.0);
    _saveSettings();
    _notifyListeners();
  }

  void setFontFamily(FontFamilyOption value) {
    _fontFamily = value;
    _saveSettings();
    _notifyListeners();
  }

  void setFontSize(FontSizeOption value) {
    _fontSize = value;
    _saveSettings();
    _notifyListeners();
  }

  void setHideToolCalls(bool value) {
    _hideToolCalls = value;
    _saveSettings();
    _notifyListeners();
  }

  // Setters - Agent 全局设置（缓存到内存）
  void setClaudeSettings(ClaudeUserSettings settings) {
    _claudeSettings = settings;
    _notifyListeners();
  }

  void setCodexSettings(CodexUserSettings settings) {
    _codexSettings = settings;
    _notifyListeners();
  }

  // 获取或创建默认 Claude 设置
  ClaudeUserSettings getOrCreateClaudeSettings(String userId) {
    return _claudeSettings ?? ClaudeUserSettings.defaults(userId);
  }

  // 获取或创建默认 Codex 设置
  CodexUserSettings getOrCreateCodexSettings(String userId) {
    return _codexSettings ?? CodexUserSettings.defaults(userId);
  }

  // Setter - 默认项目设置
  void setDefaultSessionSettings(SessionSettings? settings) {
    _defaultSessionSettings = settings;
    _saveSettings();
    _notifyListeners();
  }

  // 获取默认项目设置（用于创建新会话）
  SessionSettings? getDefaultSessionSettingsForNewSession(String sessionId, String cwd) {
    if (_defaultSessionSettings == null) return null;

    // 复制默认设置，但使用新的 sessionId 和 cwd
    return SessionSettings(
      sessionId: sessionId,
      cwd: cwd,
      permissionMode: _defaultSessionSettings!.permissionMode,
      systemPrompt: _defaultSessionSettings!.systemPrompt,
      systemPromptPreset: _defaultSessionSettings!.systemPromptPreset,
      systemPromptMode: _defaultSessionSettings!.systemPromptMode,
      settingSources: _defaultSessionSettings!.settingSources,
      hideToolCalls: _defaultSessionSettings!.hideToolCalls,
    );
  }

  // 监听器管理
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    for (var listener in _listeners) {
      listener();
    }
  }
}
