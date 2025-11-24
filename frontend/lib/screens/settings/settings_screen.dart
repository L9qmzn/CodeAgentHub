import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/app_settings_service.dart';
import '../../services/notification_sound_service.dart';
import '../../services/config_service.dart';
import '../../models/user_settings.dart';
import '../../models/codex_user_settings.dart';
import '../../models/session_settings.dart';
import '../../repositories/project_repository.dart';
import '../../repositories/codex_repository.dart';
import '../session_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  final ProjectRepository claudeRepository;
  final CodexRepository codexRepository;
  final VoidCallback? onLogout;

  const SettingsScreen({
    super.key,
    required this.claudeRepository,
    required this.codexRepository,
    this.onLogout,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settingsService = AppSettingsService();
  final _soundService = NotificationSoundService();
  late bool _darkMode;
  late bool _notifications;
  late double _notificationVolume;
  late FontFamilyOption _fontFamily;
  late FontSizeOption _fontSize;
  late bool _hideToolCalls;
  late bool _includeProjectSettings; // 是否包含项目设置
  String _apiEndpoint = 'http://192.168.31.99:8207';

  // Claude settings
  ClaudeUserSettings? _claudeSettings;
  bool _loadingClaudeSettings = true;

  // Codex settings
  CodexUserSettings? _codexSettings;
  bool _loadingCodexSettings = true;

  @override
  void initState() {
    super.initState();
    // Load interface settings
    _darkMode = _settingsService.darkModeEnabled;
    _notifications = _settingsService.notificationsEnabled;
    _notificationVolume = _settingsService.notificationVolume;
    _fontFamily = _settingsService.fontFamily;
    _fontSize = _settingsService.fontSize;
    _hideToolCalls = _settingsService.hideToolCalls;

    // 初始化项目设置开关
    List<String> currentSources = _settingsService.defaultSessionSettings?.settingSources ?? ['user'];
    _includeProjectSettings = currentSources.contains('project');

    // Load global agent settings
    _loadGlobalSettings();
  }

  Future<void> _loadGlobalSettings() async {
    try {
      final authService = await AuthService.getInstance();
      final userId = authService.username ?? 'admin';

      // Load Claude settings
      setState(() => _loadingClaudeSettings = true);
      final claudeSettings = await widget.claudeRepository.getUserSettings(userId);
      setState(() {
        _claudeSettings = claudeSettings;
        _loadingClaudeSettings = false;
      });
      _settingsService.setClaudeSettings(claudeSettings);

      // Load Codex settings
      setState(() => _loadingCodexSettings = true);
      final codexSettings = await widget.codexRepository.getUserSettings(userId);
      setState(() {
        _codexSettings = codexSettings;
        _loadingCodexSettings = false;
      });
      _settingsService.setCodexSettings(codexSettings);
    } catch (e) {
      setState(() {
        _loadingClaudeSettings = false;
        _loadingCodexSettings = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('加载全局设置失败: $e'),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              top: 16,
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).size.height - 100,
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final errorColor = Theme.of(context).colorScheme.error;
    final dividerColor = Theme.of(context).dividerColor;
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ========== 界面设置 ==========
          _buildSectionTitle(context, '界面设置'),
          _buildSettingCard(context,
            child: Column(
              children: [
                SwitchListTile(
                  title: Text('深色模式', style: TextStyle(fontSize: 16, color: textPrimary)),
                  subtitle: Text('切换浅色/深色主题', style: TextStyle(fontSize: 13, color: appColors.textSecondary)),
                  value: _darkMode,
                  onChanged: (value) {
                    setState(() => _darkMode = value);
                    _settingsService.setDarkModeEnabled(value);
                  },
                  activeColor: primaryColor,
                ),
                Divider(height: 1, color: dividerColor),
                ListTile(
                  title: Text('字体', style: TextStyle(fontSize: 16, color: textPrimary)),
                  subtitle: Text(_fontFamily.label, style: TextStyle(fontSize: 13, color: appColors.textSecondary, fontFamily: _fontFamily.fontFamily)),
                  trailing: IconButton(icon: Icon(Icons.arrow_forward_ios, size: 16), onPressed: () => _showFontPicker()),
                ),
                Divider(height: 1, color: dividerColor),
                ListTile(
                  title: Text('字号', style: TextStyle(fontSize: 16, color: textPrimary)),
                  subtitle: Text(_fontSize.label, style: TextStyle(fontSize: 13, color: appColors.textSecondary)),
                  trailing: IconButton(icon: Icon(Icons.arrow_forward_ios, size: 16), onPressed: () => _showFontSizePicker()),
                ),
                Divider(height: 1, color: dividerColor),
                SwitchListTile(
                  title: Text('启用通知', style: TextStyle(fontSize: 16, color: textPrimary)),
                  subtitle: Text('后台标签页有新回复时显示通知', style: TextStyle(fontSize: 13, color: appColors.textSecondary)),
                  value: _notifications,
                  onChanged: (value) {
                    setState(() => _notifications = value);
                    _settingsService.setNotificationsEnabled(value);
                  },
                  activeColor: primaryColor,
                ),
                if (_notifications) ...[
                  Divider(height: 1, color: dividerColor),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text('通知音量', style: TextStyle(fontSize: 14, color: appColors.textSecondary))),
                            TextButton.icon(
                              onPressed: () {
                                _soundService.setVolume(_notificationVolume);
                                _soundService.playNotificationSound();
                              },
                              icon: Icon(Icons.volume_up, size: 18),
                              label: Text('测试'),
                              style: TextButton.styleFrom(foregroundColor: primaryColor),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Icon(Icons.volume_mute, size: 20, color: appColors.textTertiary),
                            Expanded(
                              child: Slider(
                                value: _notificationVolume,
                                min: 0.0,
                                max: 1.0,
                                divisions: 10,
                                label: '${(_notificationVolume * 100).round()}%',
                                activeColor: primaryColor,
                                onChanged: (value) {
                                  setState(() => _notificationVolume = value);
                                  _settingsService.setNotificationVolume(value);
                                },
                              ),
                            ),
                            Icon(Icons.volume_up, size: 20, color: appColors.textTertiary),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                Divider(height: 1, color: dividerColor),
                ListTile(
                  title: Text('API 地址', style: TextStyle(fontSize: 16, color: textPrimary)),
                  subtitle: Text(_apiEndpoint, style: TextStyle(fontSize: 13, color: appColors.textSecondary)),
                  trailing: Icon(Icons.edit, color: primaryColor),
                  onTap: () => _showApiEndpointDialog(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // ========== Claude Code 设置 ==========
          _buildSectionTitle(context, 'Claude Code 设置'),
          _loadingClaudeSettings
              ? _buildLoadingCard(context)
              : _buildSettingCard(context,
                  child: Column(
                    children: [
                      ListTile(
                        title: Text('默认权限模式', style: TextStyle(fontSize: 16, color: textPrimary)),
                        subtitle: Text(_getPermissionModeLabel(_claudeSettings?.permissionMode ?? 'default'), style: TextStyle(fontSize: 13, color: appColors.textSecondary)),
                        trailing: Icon(Icons.arrow_forward_ios, size: 16, color: appColors.textSecondary),
                        onTap: () => _showPermissionModePicker(),
                      ),
                      Divider(height: 1, color: dividerColor),
                      ListTile(
                        title: Text('系统提示', style: TextStyle(fontSize: 16, color: textPrimary)),
                        subtitle: Text(_claudeSettings?.systemPrompt.displayText ?? 'claude_code', style: TextStyle(fontSize: 13, color: appColors.textSecondary)),
                        trailing: Icon(Icons.arrow_forward_ios, size: 16, color: appColors.textSecondary),
                        onTap: () => _showSystemPromptDialog(),
                      ),
                      Divider(height: 1, color: dividerColor),
                      ListTile(
                        title: Text('模型选择', style: TextStyle(fontSize: 16, color: textPrimary)),
                        subtitle: Text(_getModelLabel(_claudeSettings?.advancedOptions?['model']), style: TextStyle(fontSize: 13, color: appColors.textSecondary)),
                        trailing: Icon(Icons.arrow_forward_ios, size: 16, color: appColors.textSecondary),
                        onTap: () => _showModelPicker(),
                      ),
                      Divider(height: 1, color: dividerColor),
                      ListTile(
                        title: Text('高级设置', style: TextStyle(fontSize: 16, color: textPrimary)),
                        subtitle: Text(_claudeSettings?.advancedOptions != null && _claudeSettings!.advancedOptions!.isNotEmpty ? '已配置 ${_claudeSettings!.advancedOptions!.length} 个参数' : '未配置', style: TextStyle(fontSize: 13, color: appColors.textSecondary)),
                        trailing: Icon(Icons.arrow_forward_ios, size: 16, color: appColors.textSecondary),
                        onTap: () => _showAdvancedOptionsDialog(),
                      ),
                      Divider(height: 1, color: dividerColor),
                      SwitchListTile(
                        title: Text('包含项目配置', style: TextStyle(fontSize: 16, color: textPrimary)),
                        subtitle: Text('新会话将读取项目目录中的 .claude/config 配置', style: TextStyle(fontSize: 13, color: appColors.textSecondary)),
                        value: _includeProjectSettings,
                        onChanged: (value) {
                          setState(() => _includeProjectSettings = value);
                          // 保存设置
                          final newSources = value ? ['user', 'project'] : ['user'];
                          final newSettings = SessionSettings(
                            sessionId: 'default',
                            cwd: '',
                            settingSources: newSources,
                          );
                          _settingsService.setDefaultSessionSettings(newSettings);
                        },
                        activeColor: primaryColor,
                      ),
                      Divider(height: 1, color: dividerColor),
                      SwitchListTile(
                        title: Text('全局隐藏工具调用', style: TextStyle(fontSize: 16, color: textPrimary)),
                        subtitle: Text('所有会话默认不显示工具调用', style: TextStyle(fontSize: 13, color: appColors.textSecondary)),
                        value: _hideToolCalls,
                        onChanged: (value) {
                          setState(() => _hideToolCalls = value);
                          _settingsService.setHideToolCalls(value);
                        },
                        activeColor: primaryColor,
                      ),
                    ],
                  ),
                ),

          const SizedBox(height: 32),

          // ========== Codex 设置 ==========
          _buildSectionTitle(context, 'Codex 设置'),
          _loadingCodexSettings
              ? _buildLoadingCard(context)
              : _buildSettingCard(context,
                  child: Column(
                    children: [
                      ListTile(
                        title: Text('审批策略', style: TextStyle(fontSize: 16, color: textPrimary)),
                        subtitle: Text(_getApprovalPolicyLabel(_codexSettings?.approvalPolicy ?? 'on-request'), style: TextStyle(fontSize: 13, color: appColors.textSecondary)),
                        trailing: Icon(Icons.arrow_forward_ios, size: 16, color: appColors.textSecondary),
                        onTap: () => _showApprovalPolicyPicker(),
                      ),
                      Divider(height: 1, color: dividerColor),
                      ListTile(
                        title: Text('沙箱模式', style: TextStyle(fontSize: 16, color: textPrimary)),
                        subtitle: Text(_getSandboxModeLabel(_codexSettings?.sandboxMode ?? 'read-only'), style: TextStyle(fontSize: 13, color: appColors.textSecondary)),
                        trailing: Icon(Icons.arrow_forward_ios, size: 16, color: appColors.textSecondary),
                        onTap: () => _showSandboxModePicker(),
                      ),
                      Divider(height: 1, color: dividerColor),
                      ListTile(
                        title: Text('模型推理强度', style: TextStyle(fontSize: 16, color: textPrimary)),
                        subtitle: Text(_getReasoningEffortLabel(_codexSettings?.modelReasoningEffort ?? 'medium'), style: TextStyle(fontSize: 13, color: appColors.textSecondary)),
                        trailing: Icon(Icons.arrow_forward_ios, size: 16, color: appColors.textSecondary),
                        onTap: () => _showReasoningEffortPicker(),
                      ),
                      Divider(height: 1, color: dividerColor),
                      SwitchListTile(
                        title: Text('网络访问', style: TextStyle(fontSize: 16, color: textPrimary)),
                        subtitle: Text('允许访问外部网络', style: TextStyle(fontSize: 13, color: appColors.textSecondary)),
                        value: _codexSettings?.networkAccessEnabled ?? false,
                        onChanged: (value) => _updateCodexSetting('network_access', value),
                        activeColor: primaryColor,
                      ),
                      Divider(height: 1, color: dividerColor),
                      SwitchListTile(
                        title: Text('网页搜索', style: TextStyle(fontSize: 16, color: textPrimary)),
                        subtitle: Text('启用网页搜索功能', style: TextStyle(fontSize: 13, color: appColors.textSecondary)),
                        value: _codexSettings?.webSearchEnabled ?? false,
                        onChanged: (value) => _updateCodexSetting('web_search', value),
                        activeColor: primaryColor,
                      ),
                      Divider(height: 1, color: dividerColor),
                      SwitchListTile(
                        title: Text('跳过 Git 检查', style: TextStyle(fontSize: 16, color: textPrimary)),
                        subtitle: Text('跳过 Git 仓库检查', style: TextStyle(fontSize: 13, color: appColors.textSecondary)),
                        value: _codexSettings?.skipGitRepoCheck ?? false,
                        onChanged: (value) => _updateCodexSetting('skip_git', value),
                        activeColor: primaryColor,
                      ),
                    ],
                  ),
                ),

          const SizedBox(height: 32),

          // ========== 关于 ==========
          _buildSectionTitle(context, '关于'),
          _buildSettingCard(context,
            child: Column(
              children: [
                ListTile(
                  title: Text('版本', style: TextStyle(fontSize: 16, color: textPrimary)),
                  trailing: Text('1.0.0', style: TextStyle(fontSize: 14, color: appColors.textSecondary)),
                ),
                Divider(height: 1, color: dividerColor),
                ListTile(
                  title: Text('隐私政策', style: TextStyle(fontSize: 16, color: appColors.textSecondary)),
                  subtitle: Text('功能开发中...', style: TextStyle(fontSize: 12, color: appColors.textTertiary, fontStyle: FontStyle.italic)),
                  trailing: Icon(Icons.arrow_forward_ios, size: 16, color: appColors.textTertiary),
                  onTap: null,
                ),
                Divider(height: 1, color: dividerColor),
                ListTile(
                  title: Text('服务条款', style: TextStyle(fontSize: 16, color: appColors.textSecondary)),
                  subtitle: Text('功能开发中...', style: TextStyle(fontSize: 12, color: appColors.textTertiary, fontStyle: FontStyle.italic)),
                  trailing: Icon(Icons.arrow_forward_ios, size: 16, color: appColors.textTertiary),
                  onTap: null,
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // ========== 账户 ==========
          _buildSectionTitle(context, '账户'),
          _buildSettingCard(context,
            child: ListTile(
              leading: Icon(Icons.logout, color: errorColor),
              title: Text('退出登录', style: TextStyle(fontSize: 16, color: errorColor, fontWeight: FontWeight.w500)),
              onTap: () => _handleLogout(),
            ),
          ),
        ],
      ),
    );
  }

  // Helper: Labels
  String _getPermissionModeLabel(String mode) {
    switch (mode) {
      case 'default': return '默认';
      case 'plan': return '规划模式';
      case 'acceptEdits': return '接受编辑';
      case 'bypassPermissions': return '跳过权限';
      default: return mode;
    }
  }

  String _getApprovalPolicyLabel(String policy) {
    switch (policy) {
      case 'never': return '从不';
      case 'on-request': return '请求时';
      case 'on-failure': return '失败时';
      case 'untrusted': return '不信任';
      default: return policy;
    }
  }

  String _getSandboxModeLabel(String mode) {
    switch (mode) {
      case 'read-only': return '只读';
      case 'workspace-write': return '工作区写入';
      case 'danger-full-access': return '完全访问';
      default: return mode;
    }
  }

  String _getReasoningEffortLabel(String effort) {
    switch (effort) {
      case 'low': return '低';
      case 'medium': return '中';
      case 'high': return '高';
      default: return effort;
    }
  }

  String _getModelLabel(String? model) {
    if (model == null || model.isEmpty) return 'Default';
    switch (model.toLowerCase()) {
      case 'opus': return 'Opus';
      case 'haiku': return 'Haiku';
      default: return model;
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final appColors = context.appColors;
        final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;
        final errorColor = Theme.of(context).colorScheme.error;
        final cardColor = Theme.of(context).cardColor;

        return AlertDialog(
          backgroundColor: cardColor,
          title: Text('确认退出', style: TextStyle(color: textPrimary)),
          content: Text('确定要退出登录吗？', style: TextStyle(color: appColors.textSecondary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('取消', style: TextStyle(color: appColors.textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('退出', style: TextStyle(color: errorColor)),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        final authService = await AuthService.getInstance();
        await authService.logout();

        if (mounted) {
          Navigator.pop(context);
          widget.onLogout?.call();
        }
      } catch (e) {
        if (mounted) {
          final errorColor = Theme.of(context).colorScheme.error;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('退出失败: $e'),
              backgroundColor: errorColor,
              behavior: SnackBarBehavior.floating,
              margin: EdgeInsets.only(
                top: 16,
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).size.height - 100,
              ),
            ),
          );
        }
      }
    }
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: context.appColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSettingCard(BuildContext context, {required Widget child}) {
    return Card(
      color: Theme.of(context).cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: child,
    );
  }

  Widget _buildLoadingCard(BuildContext context) {
    return Card(
      color: Theme.of(context).cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }

  void _showApiEndpointDialog() {
    final controller = TextEditingController(text: _apiEndpoint);
    showDialog(
      context: context,
      builder: (context) {
        final appColors = context.appColors;
        final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;
        final primaryColor = Theme.of(context).colorScheme.primary;
        final dividerColor = Theme.of(context).dividerColor;
        final cardColor = Theme.of(context).cardColor;

        return AlertDialog(
          backgroundColor: cardColor,
          title: Text('API 地址', style: TextStyle(color: textPrimary)),
          content: TextField(
            controller: controller,
            style: TextStyle(color: textPrimary),
            decoration: InputDecoration(
              hintText: '输入 API 地址',
              hintStyle: TextStyle(color: appColors.textTertiary),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: dividerColor), borderRadius: BorderRadius.circular(8)),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: primaryColor), borderRadius: BorderRadius.circular(8)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('取消', style: TextStyle(color: appColors.textSecondary)),
            ),
            TextButton(
              onPressed: () async {
                final newEndpoint = controller.text.trim();
                if (newEndpoint.isEmpty) {
                  Navigator.pop(context);
                  return;
                }

                setState(() => _apiEndpoint = newEndpoint);

                try {
                  final configService = await ConfigService.getInstance();
                  await configService.setApiBaseUrl(newEndpoint);

                  // 动态更新所有 ApiService 的 baseUrl
                  widget.claudeRepository.apiService.updateBaseUrl(newEndpoint);
                  widget.codexRepository.apiService.updateBaseUrl(newEndpoint);
                  print('DEBUG: API URL updated to $newEndpoint for all services');

                  Navigator.pop(context);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('API 地址已保存并生效'),
                        behavior: SnackBarBehavior.floating,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                } catch (e) {
                  Navigator.pop(context);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('保存失败: $e'),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: Colors.red,
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }
                }
              },
              child: Text('保存', style: TextStyle(color: primaryColor)),
            ),
          ],
        );
      },
    );
  }

  void _showFontPicker() {
    showDialog(
      context: context,
      builder: (context) {
        final appColors = context.appColors;
        final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;
        final primaryColor = Theme.of(context).colorScheme.primary;
        final cardColor = Theme.of(context).cardColor;

        return AlertDialog(
          backgroundColor: cardColor,
          title: Text('选择字体', style: TextStyle(color: textPrimary)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: FontFamilyOption.values.length,
              itemBuilder: (context, index) {
                final option = FontFamilyOption.values[index];
                final isSelected = _fontFamily == option;
                return ListTile(
                  title: Text(option.label, style: TextStyle(color: textPrimary, fontFamily: option.fontFamily, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                  subtitle: Text('这是示例文本 1234', style: TextStyle(color: appColors.textSecondary, fontFamily: option.fontFamily)),
                  trailing: isSelected ? Icon(Icons.check, color: primaryColor) : null,
                  onTap: () {
                    setState(() => _fontFamily = option);
                    _settingsService.setFontFamily(option);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('关闭', style: TextStyle(color: appColors.textSecondary)),
            ),
          ],
        );
      },
    );
  }

  void _showFontSizePicker() {
    showDialog(
      context: context,
      builder: (context) {
        final appColors = context.appColors;
        final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;
        final primaryColor = Theme.of(context).colorScheme.primary;
        final cardColor = Theme.of(context).cardColor;

        return AlertDialog(
          backgroundColor: cardColor,
          title: Text('选择字号', style: TextStyle(color: textPrimary)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: FontSizeOption.values.length,
              itemBuilder: (context, index) {
                final option = FontSizeOption.values[index];
                final isSelected = _fontSize == option;
                return ListTile(
                  title: Text(option.label, style: TextStyle(color: textPrimary, fontSize: 16 * option.scale, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                  subtitle: Text('这是示例文本 1234', style: TextStyle(color: appColors.textSecondary, fontSize: 14 * option.scale)),
                  trailing: isSelected ? Icon(Icons.check, color: primaryColor) : null,
                  onTap: () {
                    setState(() => _fontSize = option);
                    _settingsService.setFontSize(option);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('关闭', style: TextStyle(color: appColors.textSecondary)),
            ),
          ],
        );
      },
    );
  }

  void _showPermissionModePicker() {
    final modes = ['default', 'plan', 'acceptEdits', 'bypassPermissions'];
    showDialog(
      context: context,
      builder: (context) {
        final appColors = context.appColors;
        final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;
        final primaryColor = Theme.of(context).colorScheme.primary;
        final cardColor = Theme.of(context).cardColor;

        return AlertDialog(
          backgroundColor: cardColor,
          title: Text('选择权限模式', style: TextStyle(color: textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: modes.map((mode) {
              final isSelected = _claudeSettings?.permissionMode == mode;
              return ListTile(
                title: Text(_getPermissionModeLabel(mode), style: TextStyle(color: textPrimary, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                trailing: isSelected ? Icon(Icons.check, color: primaryColor) : null,
                onTap: () async {
                  await _updateClaudeSetting('permission_mode', mode);
                  if (mounted) Navigator.pop(context);
                },
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('关闭', style: TextStyle(color: appColors.textSecondary)),
            ),
          ],
        );
      },
    );
  }

  void _showSystemPromptDialog() {
    final controller = TextEditingController(
      text: _claudeSettings?.systemPrompt.type == 'custom' ? _claudeSettings?.systemPrompt.custom : '',
    );
    showDialog(
      context: context,
      builder: (context) {
        final appColors = context.appColors;
        final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;
        final primaryColor = Theme.of(context).colorScheme.primary;
        final dividerColor = Theme.of(context).dividerColor;
        final cardColor = Theme.of(context).cardColor;

        return AlertDialog(
          backgroundColor: cardColor,
          title: Text('系统提示', style: TextStyle(color: textPrimary)),
          content: TextField(
            controller: controller,
            style: TextStyle(color: textPrimary),
            maxLines: 5,
            decoration: InputDecoration(
              hintText: '输入自定义系统提示（留空使用默认）',
              hintStyle: TextStyle(color: appColors.textTertiary),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: dividerColor), borderRadius: BorderRadius.circular(8)),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: primaryColor), borderRadius: BorderRadius.circular(8)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('取消', style: TextStyle(color: appColors.textSecondary)),
            ),
            TextButton(
              onPressed: () async {
                final text = controller.text.trim();
                final prompt = text.isEmpty ? SystemPrompt.preset('claude_code') : SystemPrompt.custom(text);
                await _updateClaudeSetting('system_prompt', prompt);
                if (mounted) Navigator.pop(context);
              },
              child: Text('保存', style: TextStyle(color: primaryColor)),
            ),
          ],
        );
      },
    );
  }

  void _showApprovalPolicyPicker() {
    final policies = ['never', 'on-request', 'on-failure', 'untrusted'];
    showDialog(
      context: context,
      builder: (context) {
        final appColors = context.appColors;
        final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;
        final primaryColor = Theme.of(context).colorScheme.primary;
        final cardColor = Theme.of(context).cardColor;

        return AlertDialog(
          backgroundColor: cardColor,
          title: Text('选择审批策略', style: TextStyle(color: textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: policies.map((policy) {
              final isSelected = _codexSettings?.approvalPolicy == policy;
              return ListTile(
                title: Text(_getApprovalPolicyLabel(policy), style: TextStyle(color: textPrimary, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                trailing: isSelected ? Icon(Icons.check, color: primaryColor) : null,
                onTap: () async {
                  await _updateCodexSetting('approval_policy', policy);
                  if (mounted) Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _showSandboxModePicker() {
    final modes = ['read-only', 'workspace-write', 'danger-full-access'];
    showDialog(
      context: context,
      builder: (context) {
        final appColors = context.appColors;
        final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;
        final primaryColor = Theme.of(context).colorScheme.primary;
        final cardColor = Theme.of(context).cardColor;

        return AlertDialog(
          backgroundColor: cardColor,
          title: Text('选择沙箱模式', style: TextStyle(color: textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: modes.map((mode) {
              final isSelected = _codexSettings?.sandboxMode == mode;
              return ListTile(
                title: Text(_getSandboxModeLabel(mode), style: TextStyle(color: textPrimary, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                trailing: isSelected ? Icon(Icons.check, color: primaryColor) : null,
                onTap: () async {
                  await _updateCodexSetting('sandbox_mode', mode);
                  if (mounted) Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _showReasoningEffortPicker() {
    final efforts = ['low', 'medium', 'high'];
    showDialog(
      context: context,
      builder: (context) {
        final appColors = context.appColors;
        final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;
        final primaryColor = Theme.of(context).colorScheme.primary;
        final cardColor = Theme.of(context).cardColor;

        return AlertDialog(
          backgroundColor: cardColor,
          title: Text('选择推理强度', style: TextStyle(color: textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: efforts.map((effort) {
              final isSelected = _codexSettings?.modelReasoningEffort == effort;
              return ListTile(
                title: Text(_getReasoningEffortLabel(effort), style: TextStyle(color: textPrimary, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                trailing: isSelected ? Icon(Icons.check, color: primaryColor) : null,
                onTap: () async {
                  await _updateCodexSetting('reasoning_effort', effort);
                  if (mounted) Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _showModelPicker() {
    final models = [
      {'value': null, 'label': 'Default'},
      {'value': 'opus', 'label': 'Opus'},
      {'value': 'haiku', 'label': 'Haiku'},
    ];

    showDialog(
      context: context,
      builder: (context) {
        final appColors = context.appColors;
        final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;
        final primaryColor = Theme.of(context).colorScheme.primary;
        final cardColor = Theme.of(context).cardColor;

        final currentModel = _claudeSettings?.advancedOptions?['model'];

        return AlertDialog(
          backgroundColor: cardColor,
          title: Text('选择模型', style: TextStyle(color: textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: models.map((model) {
              final isSelected = (currentModel == null && model['value'] == null) ||
                                currentModel == model['value'];
              return ListTile(
                title: Text(
                  model['label'] as String,
                  style: TextStyle(
                    color: textPrimary,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                trailing: isSelected ? Icon(Icons.check, color: primaryColor) : null,
                onTap: () async {
                  // Update advanced options with model selection
                  final newAdvancedOptions = Map<String, dynamic>.from(
                    _claudeSettings?.advancedOptions ?? {}
                  );

                  if (model['value'] == null) {
                    // Default - remove model from advanced options
                    newAdvancedOptions.remove('model');
                  } else {
                    // Set model
                    newAdvancedOptions['model'] = model['value'];
                  }

                  await _updateClaudeSetting(
                    'advanced_options',
                    newAdvancedOptions.isEmpty ? null : newAdvancedOptions,
                  );
                  if (mounted) Navigator.pop(context);
                },
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('关闭', style: TextStyle(color: appColors.textSecondary)),
            ),
          ],
        );
      },
    );
  }

  void _showAdvancedOptionsDialog() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AdvancedOptionsEditor(
          initialOptions: _claudeSettings?.advancedOptions ?? {},
          onSave: (options) async {
            await _updateClaudeSetting('advanced_options', options.isEmpty ? null : options);
          },
        ),
      ),
    );
  }

  Future<void> _updateClaudeSetting(String key, dynamic value) async {
    if (_claudeSettings == null) return;

    try {
      ClaudeUserSettings updated;
      if (key == 'permission_mode') {
        updated = _claudeSettings!.copyWith(permissionMode: value as String);
      } else if (key == 'system_prompt') {
        updated = _claudeSettings!.copyWith(systemPrompt: value as SystemPrompt);
      } else if (key == 'advanced_options') {
        updated = _claudeSettings!.copyWith(advancedOptions: value as Map<String, dynamic>?);
      } else {
        return;
      }

      final authService = await AuthService.getInstance();
      final userId = authService.username ?? 'admin';

      await widget.claudeRepository.updateUserSettings(userId, updated);
      setState(() => _claudeSettings = updated);
      _settingsService.setClaudeSettings(updated);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Claude 设置已保存'),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              top: 16,
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).size.height - 100,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              top: 16,
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).size.height - 100,
            ),
          ),
        );
      }
    }
  }

  Future<void> _updateCodexSetting(String key, dynamic value) async {
    if (_codexSettings == null) return;

    try {
      CodexUserSettings updated;
      switch (key) {
        case 'approval_policy':
          updated = _codexSettings!.copyWith(approvalPolicy: value as String);
          break;
        case 'sandbox_mode':
          updated = _codexSettings!.copyWith(sandboxMode: value as String);
          break;
        case 'reasoning_effort':
          updated = _codexSettings!.copyWith(modelReasoningEffort: value as String);
          break;
        case 'network_access':
          updated = _codexSettings!.copyWith(networkAccessEnabled: value as bool);
          break;
        case 'web_search':
          updated = _codexSettings!.copyWith(webSearchEnabled: value as bool);
          break;
        case 'skip_git':
          updated = _codexSettings!.copyWith(skipGitRepoCheck: value as bool);
          break;
        default:
          return;
      }

      final authService = await AuthService.getInstance();
      final userId = authService.username ?? 'admin';

      await widget.codexRepository.updateUserSettings(userId, updated);
      setState(() => _codexSettings = updated);
      _settingsService.setCodexSettings(updated);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Codex 设置已保存'),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              top: 16,
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).size.height - 100,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              top: 16,
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).size.height - 100,
            ),
          ),
        );
      }
    }
  }

}

// 高级设置编辑器
class AdvancedOptionsEditor extends StatefulWidget {
  final Map<String, dynamic> initialOptions;
  final Function(Map<String, dynamic>) onSave;

  const AdvancedOptionsEditor({
    required this.initialOptions,
    required this.onSave,
  });

  @override
  State<AdvancedOptionsEditor> createState() => _AdvancedOptionsEditorState();
}

class _AdvancedOptionsEditorState extends State<AdvancedOptionsEditor> {
  late List<_OptionItem> _options;

  // 常用配置项的定义
  static const List<Map<String, String>> _commonOptions = [
    {'key': 'model', 'hint': 'claude-sonnet-4', 'description': '使用的模型名称'},
    {'key': 'max_turns', 'hint': '100', 'description': '最大对话轮数'},
    {'key': 'max_thinking_tokens', 'hint': '10000', 'description': '最大思考token数'},
    {'key': 'fallback_model', 'hint': 'claude-opus-4', 'description': '备用模型'},
    {'key': 'max_budget_usd', 'hint': '1.0', 'description': '最大预算（美元）'},
  ];

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  void _loadOptions() {
    _options = [];

    // 加载已保存的选项
    widget.initialOptions.forEach((key, value) {
      _options.add(_OptionItem(
        key: key,
        value: value.toString(),
        keyController: TextEditingController(text: key),
        valueController: TextEditingController(text: value.toString()),
      ));
    });

    // 如果没有任何选项，添加一些常用的空选项
    if (_options.isEmpty) {
      for (var option in _commonOptions.take(3)) {
        _options.add(_OptionItem(
          key: option['key']!,
          value: '',
          keyController: TextEditingController(text: option['key']),
          valueController: TextEditingController(),
        ));
      }
    }
  }

  void _addOption() {
    setState(() {
      _options.add(_OptionItem(
        key: '',
        value: '',
        keyController: TextEditingController(),
        valueController: TextEditingController(),
      ));
    });
  }

  void _removeOption(int index) {
    setState(() {
      _options[index].dispose();
      _options.removeAt(index);
    });
  }

  Map<String, dynamic> _buildOptionsMap() {
    final map = <String, dynamic>{};
    for (var option in _options) {
      final key = option.keyController.text.trim();
      final value = option.valueController.text.trim();

      if (key.isEmpty || value.isEmpty) continue;

      // 尝试解析值的类型
      if (value == 'true' || value == 'false') {
        map[key] = value == 'true';
      } else if (int.tryParse(value) != null) {
        map[key] = int.parse(value);
      } else if (double.tryParse(value) != null) {
        map[key] = double.parse(value);
      } else {
        map[key] = value;
      }
    }
    return map;
  }

  @override
  void dispose() {
    for (var option in _options) {
      option.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;
    final dividerColor = Theme.of(context).dividerColor;
    final primaryColor = Theme.of(context).primaryColor;
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('高级设置'),
        actions: [
          TextButton(
            onPressed: () async {
              final options = _buildOptionsMap();
              await widget.onSave(options);
              if (mounted) Navigator.pop(context);
            },
            child: Text('保存', style: TextStyle(color: primaryColor, fontSize: 16)),
          ),
        ],
      ),
      body: Column(
        children: [
          // 说明区域
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: appColors.codeBackground,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '配置说明',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '填写键值对来配置高级选项。留空的项不会被保存。',
                  style: TextStyle(color: appColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  '常用配置: model, max_turns, max_thinking_tokens',
                  style: TextStyle(
                    color: appColors.textSecondary,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          // 选项列表
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _options.length,
              itemBuilder: (context, index) {
                final option = _options[index];
                final commonOption = _commonOptions.firstWhere(
                  (o) => o['key'] == option.keyController.text,
                  orElse: () => {},
                );

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: option.keyController,
                                style: TextStyle(color: textPrimary, fontSize: 14),
                                decoration: InputDecoration(
                                  labelText: '配置项',
                                  labelStyle: TextStyle(color: appColors.textSecondary, fontSize: 12),
                                  hintText: '例如: model',
                                  hintStyle: TextStyle(color: appColors.textTertiary, fontSize: 12),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => _removeOption(index),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: option.valueController,
                          style: TextStyle(color: textPrimary, fontSize: 14),
                          decoration: InputDecoration(
                            labelText: '值',
                            labelStyle: TextStyle(color: appColors.textSecondary, fontSize: 12),
                            hintText: commonOption['hint'] ?? '输入值',
                            hintStyle: TextStyle(color: appColors.textTertiary, fontSize: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                        if (commonOption['description'] != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            commonOption['description']!,
                            style: TextStyle(
                              color: appColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // 添加按钮
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(
                top: BorderSide(color: dividerColor, width: 1),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _addOption,
                    icon: const Icon(Icons.add),
                    label: const Text('添加配置项'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryColor,
                      side: BorderSide(color: primaryColor),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionItem {
  String key;
  String value;
  final TextEditingController keyController;
  final TextEditingController valueController;

  _OptionItem({
    required this.key,
    required this.value,
    required this.keyController,
    required this.valueController,
  });

  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }
}
