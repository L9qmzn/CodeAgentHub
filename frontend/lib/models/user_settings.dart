/// Claude Code 用户全局设置
class ClaudeUserSettings {
  final String userId;
  final String permissionMode; // default | plan | acceptEdits | bypassPermissions
  final SystemPrompt systemPrompt;
  final Map<String, dynamic>? advancedOptions; // 高级参数

  ClaudeUserSettings({
    required this.userId,
    required this.permissionMode,
    required this.systemPrompt,
    this.advancedOptions,
  });

  factory ClaudeUserSettings.defaults(String userId) {
    return ClaudeUserSettings(
      userId: userId,
      permissionMode: 'default',
      systemPrompt: SystemPrompt.preset('claude_code'),
    );
  }

  factory ClaudeUserSettings.fromJson(Map<String, dynamic> json) {
    return ClaudeUserSettings(
      userId: json['user_id'] as String,
      permissionMode: json['permission_mode'] as String? ?? 'default',
      systemPrompt: _parseSystemPrompt(json['system_prompt']),
      advancedOptions: json['advanced_options'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    final result = {
      'permission_mode': permissionMode,
      'system_prompt': systemPrompt.toJson(),
    };
    if (advancedOptions != null && advancedOptions!.isNotEmpty) {
      result['advanced_options'] = advancedOptions!;
    }
    return result;
  }

  static SystemPrompt _parseSystemPrompt(dynamic value) {
    if (value == null) {
      return SystemPrompt.preset('claude_code');
    }
    if (value is String) {
      return SystemPrompt.custom(value);
    }
    if (value is Map<String, dynamic>) {
      final type = value['type'] as String?;
      if (type == 'preset') {
        return SystemPrompt.preset(value['preset'] as String);
      }
      return SystemPrompt.custom(value.toString());
    }
    return SystemPrompt.preset('claude_code');
  }

  ClaudeUserSettings copyWith({
    String? userId,
    String? permissionMode,
    SystemPrompt? systemPrompt,
    Map<String, dynamic>? advancedOptions,
  }) {
    return ClaudeUserSettings(
      userId: userId ?? this.userId,
      permissionMode: permissionMode ?? this.permissionMode,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      advancedOptions: advancedOptions ?? this.advancedOptions,
    );
  }
}

/// System Prompt 配置
class SystemPrompt {
  final String type; // 'preset' or 'custom'
  final String? preset; // preset name if type is 'preset'
  final String? custom; // custom text if type is 'custom'

  SystemPrompt._({
    required this.type,
    this.preset,
    this.custom,
  });

  factory SystemPrompt.preset(String presetName) {
    return SystemPrompt._(
      type: 'preset',
      preset: presetName,
    );
  }

  factory SystemPrompt.custom(String text) {
    return SystemPrompt._(
      type: 'custom',
      custom: text,
    );
  }

  dynamic toJson() {
    if (type == 'preset') {
      return {
        'type': 'preset',
        'preset': preset,
      };
    }
    return custom;
  }

  String get displayText {
    if (type == 'preset') {
      return '预设: $preset';
    }
    return custom ?? '';
  }
}
