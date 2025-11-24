enum PermissionMode {
  defaultMode('default'),
  plan('plan'),
  acceptEdits('acceptEdits'),
  bypassPermissions('bypassPermissions');

  final String value;
  const PermissionMode(this.value);

  static PermissionMode fromString(String value) {
    return PermissionMode.values.firstWhere(
      (mode) => mode.value == value,
      orElse: () => PermissionMode.defaultMode,
    );
  }
}

enum SystemPromptMode {
  preset,
  custom,
}

class SessionSettings {
  final String sessionId;
  final String cwd; // Read-only, cannot be changed
  final PermissionMode permissionMode;
  final String? systemPrompt; // Custom text
  final String? systemPromptPreset; // Preset name: advanced, default, concise, creative
  final SystemPromptMode systemPromptMode;
  final List<String> settingSources; // user is required, project is optional
  final bool hideToolCalls; // 是否隐藏工具调用信息
  final Map<String, dynamic>? advancedOptions; // 高级参数（对话级）

  SessionSettings({
    required this.sessionId,
    required this.cwd,
    this.permissionMode = PermissionMode.defaultMode,
    this.systemPrompt,
    this.systemPromptPreset,
    this.systemPromptMode = SystemPromptMode.custom,
    List<String>? settingSources,
    this.hideToolCalls = false,
    this.advancedOptions,
  }) : settingSources = settingSources ?? ['user'];

  SessionSettings copyWith({
    String? sessionId,
    String? cwd,
    PermissionMode? permissionMode,
    String? systemPrompt,
    String? systemPromptPreset,
    SystemPromptMode? systemPromptMode,
    List<String>? settingSources,
    bool? hideToolCalls,
    Map<String, dynamic>? advancedOptions,
  }) {
    return SessionSettings(
      sessionId: sessionId ?? this.sessionId,
      cwd: cwd ?? this.cwd,
      permissionMode: permissionMode ?? this.permissionMode,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      systemPromptPreset: systemPromptPreset ?? this.systemPromptPreset,
      systemPromptMode: systemPromptMode ?? this.systemPromptMode,
      settingSources: settingSources ?? this.settingSources,
      hideToolCalls: hideToolCalls ?? this.hideToolCalls,
      advancedOptions: advancedOptions ?? this.advancedOptions,
    );
  }

  Map<String, dynamic> toJson() {
    final json = {
      'session_id': sessionId,
      'cwd': cwd,
      'permission_mode': permissionMode.value,
      'setting_sources': settingSources,
      'hide_tool_calls': hideToolCalls,
    };

    // Add system_prompt based on mode
    if (systemPromptMode == SystemPromptMode.preset) {
      final preset = systemPromptPreset;
      if (preset != null) {
        json['system_prompt'] = {'preset': preset};
      }
    } else if (systemPromptMode == SystemPromptMode.custom) {
      final prompt = systemPrompt;
      if (prompt != null && prompt.isNotEmpty) {
        json['system_prompt'] = prompt;
      }
    }

    // Add advanced_options if present
    if (advancedOptions != null && advancedOptions!.isNotEmpty) {
      json['advanced_options'] = advancedOptions!;
    }

    return json;
  }

  factory SessionSettings.fromJson(Map<String, dynamic> json) {
    final systemPromptValue = json['system_prompt'];
    String? systemPrompt;
    String? systemPromptPreset;
    SystemPromptMode mode = SystemPromptMode.custom;

    if (systemPromptValue is Map) {
      // Preset format: {"preset": "advanced"}
      systemPromptPreset = systemPromptValue['preset'];
      mode = SystemPromptMode.preset;
    } else if (systemPromptValue is String) {
      // Custom text format
      systemPrompt = systemPromptValue;
      mode = SystemPromptMode.custom;
    }

    return SessionSettings(
      sessionId: json['session_id'],
      cwd: json['cwd'],
      permissionMode: json['permission_mode'] != null
          ? PermissionMode.fromString(json['permission_mode'])
          : PermissionMode.defaultMode,
      systemPrompt: systemPrompt,
      systemPromptPreset: systemPromptPreset,
      systemPromptMode: mode,
      settingSources: json['setting_sources'] != null
          ? List<String>.from(json['setting_sources'])
          : ['user'],
      hideToolCalls: json['hide_tool_calls'] ?? false,
      advancedOptions: json['advanced_options'] as Map<String, dynamic>?,
    );
  }
}
