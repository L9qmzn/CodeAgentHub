/// Codex 用户全局设置
class CodexUserSettings {
  final String userId;
  final String approvalPolicy; // never | on-request | on-failure | untrusted
  final String sandboxMode; // read-only | workspace-write | danger-full-access
  final String modelReasoningEffort; // low | medium | high
  final bool networkAccessEnabled;
  final bool webSearchEnabled;
  final bool skipGitRepoCheck;
  final String? model; // 可选模型名称
  final bool hideToolCalls; // 是否隐藏工具调用信息

  CodexUserSettings({
    required this.userId,
    required this.approvalPolicy,
    required this.sandboxMode,
    required this.modelReasoningEffort,
    required this.networkAccessEnabled,
    required this.webSearchEnabled,
    required this.skipGitRepoCheck,
    this.model,
    this.hideToolCalls = false,
  });

  factory CodexUserSettings.defaults(String userId) {
    return CodexUserSettings(
      userId: userId,
      approvalPolicy: 'on-request',
      sandboxMode: 'read-only',
      modelReasoningEffort: 'medium',
      networkAccessEnabled: false,
      webSearchEnabled: false,
      skipGitRepoCheck: true, // 默认跳过 Git 仓库检查
    );
  }

  factory CodexUserSettings.fromJson(Map<String, dynamic> json) {
    return CodexUserSettings(
      userId: json['user_id'] as String? ?? '',
      approvalPolicy: json['approval_policy'] as String? ?? 'on-request',
      sandboxMode: json['sandbox_mode'] as String? ?? 'read-only',
      modelReasoningEffort: json['model_reasoning_effort'] as String? ?? 'medium',
      networkAccessEnabled: json['network_access_enabled'] as bool? ?? false,
      webSearchEnabled: json['web_search_enabled'] as bool? ?? false,
      skipGitRepoCheck: json['skip_git_repo_check'] as bool? ?? true, // 默认跳过 Git 仓库检查
      model: json['model'] as String?,
      hideToolCalls: json['hide_tool_calls'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'approval_policy': approvalPolicy,
      'sandbox_mode': sandboxMode,
      'model_reasoning_effort': modelReasoningEffort,
      'network_access_enabled': networkAccessEnabled,
      'web_search_enabled': webSearchEnabled,
      'skip_git_repo_check': skipGitRepoCheck,
      'hide_tool_calls': hideToolCalls,
    };
    if (model != null) {
      json['model'] = model;
    }
    return json;
  }

  CodexUserSettings copyWith({
    String? userId,
    String? approvalPolicy,
    String? sandboxMode,
    String? modelReasoningEffort,
    bool? networkAccessEnabled,
    bool? webSearchEnabled,
    bool? skipGitRepoCheck,
    String? model,
    bool? hideToolCalls,
  }) {
    return CodexUserSettings(
      userId: userId ?? this.userId,
      approvalPolicy: approvalPolicy ?? this.approvalPolicy,
      sandboxMode: sandboxMode ?? this.sandboxMode,
      modelReasoningEffort: modelReasoningEffort ?? this.modelReasoningEffort,
      networkAccessEnabled: networkAccessEnabled ?? this.networkAccessEnabled,
      webSearchEnabled: webSearchEnabled ?? this.webSearchEnabled,
      skipGitRepoCheck: skipGitRepoCheck ?? this.skipGitRepoCheck,
      model: model ?? this.model,
      hideToolCalls: hideToolCalls ?? this.hideToolCalls,
    );
  }
}
