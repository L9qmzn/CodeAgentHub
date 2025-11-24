import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_theme.dart';
import '../models/session_settings.dart';
import 'settings/settings_screen.dart' show AdvancedOptionsEditor;

class SessionSettingsScreen extends StatefulWidget {
  final SessionSettings settings;
  final Function(SessionSettings) onSave;

  const SessionSettingsScreen({
    super.key,
    required this.settings,
    required this.onSave,
  });

  @override
  State<SessionSettingsScreen> createState() => _SessionSettingsScreenState();
}

class _SessionSettingsScreenState extends State<SessionSettingsScreen> {
  late PermissionMode _permissionMode;
  late TextEditingController _systemPromptController;
  late bool _includeProjectSettings;
  late SystemPromptMode _systemPromptMode;
  late String _systemPromptPreset;
  late bool _hideToolCalls;
  Map<String, dynamic>? _advancedOptions; // 对话级高级设置

  final List<String> _availablePresets = [
    'default',
    'advanced',
    'concise',
    'creative',
  ];

  @override
  void initState() {
    super.initState();
    _permissionMode = widget.settings.permissionMode;
    _systemPromptMode = widget.settings.systemPromptMode;
    _systemPromptPreset = widget.settings.systemPromptPreset ?? 'default';
    _systemPromptController = TextEditingController(
      text: widget.settings.systemPrompt ?? '',
    );
    _includeProjectSettings =
        widget.settings.settingSources.contains('project');
    _hideToolCalls = widget.settings.hideToolCalls;
    _advancedOptions = widget.settings.advancedOptions;
  }

  @override
  void dispose() {
    _systemPromptController.dispose();
    super.dispose();
  }

  void _save() {
    final settingSources = ['user'];
    if (_includeProjectSettings) {
      settingSources.add('project');
    }

    final updated = SessionSettings(
      sessionId: widget.settings.sessionId,
      cwd: widget.settings.cwd,
      permissionMode: _permissionMode,
      systemPromptMode: _systemPromptMode,
      systemPromptPreset: _systemPromptMode == SystemPromptMode.preset ? _systemPromptPreset : null,
      systemPrompt: _systemPromptMode == SystemPromptMode.custom && _systemPromptController.text.trim().isNotEmpty
          ? _systemPromptController.text.trim()
          : null,
      settingSources: settingSources,
      hideToolCalls: _hideToolCalls,
      advancedOptions: _advancedOptions,
    );

    widget.onSave(updated);
    Navigator.pop(context);
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

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('会话设置'),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(
              '保存',
              style: TextStyle(
                color: primaryColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionTitle('会话信息', textSecondary),
          _buildInfoCard(
            cardColor: cardColor,
            dividerColor: dividerColor,
            child: Column(
              children: [
                // 会话 ID
                ListTile(
                  title: Text(
                    '会话 ID',
                    style: TextStyle(
                      fontSize: 16,
                      color: textPrimary,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      widget.settings.sessionId,
                      style: TextStyle(
                        fontSize: 13,
                        color: textSecondary,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  trailing: IconButton(
                    icon: Icon(
                      Icons.copy,
                      color: textTertiary,
                      size: 20,
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.settings.sessionId));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('已复制会话 ID'),
                          backgroundColor: primaryColor,
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                    tooltip: '复制',
                  ),
                ),
                Divider(height: 1, color: dividerColor),
                // 工作目录
                ListTile(
                  title: Text(
                    '工作目录',
                    style: TextStyle(
                      fontSize: 16,
                      color: textPrimary,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      widget.settings.cwd,
                      style: TextStyle(
                        fontSize: 13,
                        color: textSecondary,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  trailing: Icon(
                    Icons.lock_outline,
                    color: textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('权限模式', textSecondary),
          _buildInfoCard(
            cardColor: cardColor,
            dividerColor: dividerColor,
            child: Column(
              children: [
                _buildPermissionOption(
                  PermissionMode.defaultMode,
                  '默认',
                  '标准权限模式，需用户批准',
                  textPrimary,
                  textSecondary,
                  textTertiary,
                  primaryColor,
                ),
                Divider(height: 1, color: dividerColor),
                _buildPermissionOption(
                  PermissionMode.plan,
                  '计划模式',
                  '执行前先创建计划',
                  textPrimary,
                  textSecondary,
                  textTertiary,
                  primaryColor,
                ),
                Divider(height: 1, color: dividerColor),
                _buildPermissionOption(
                  PermissionMode.acceptEdits,
                  '接受编辑',
                  '自动接受文件编辑',
                  textPrimary,
                  textSecondary,
                  textTertiary,
                  primaryColor,
                ),
                Divider(height: 1, color: dividerColor),
                _buildPermissionOption(
                  PermissionMode.bypassPermissions,
                  '跳过权限',
                  '执行所有操作无需询问',
                  textPrimary,
                  textSecondary,
                  textTertiary,
                  primaryColor,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('系统提示词', textSecondary),
          _buildInfoCard(
            cardColor: cardColor,
            dividerColor: dividerColor,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Mode selector
                  Row(
                    children: [
                      Expanded(
                        child: _buildModeButton(
                          mode: SystemPromptMode.preset,
                          label: '预设',
                          icon: Icons.style,
                          backgroundColor: backgroundColor,
                          primaryColor: primaryColor,
                          dividerColor: dividerColor,
                          textSecondary: textSecondary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildModeButton(
                          mode: SystemPromptMode.custom,
                          label: '自定义',
                          icon: Icons.edit,
                          backgroundColor: backgroundColor,
                          primaryColor: primaryColor,
                          dividerColor: dividerColor,
                          textSecondary: textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Preset dropdown or custom text field
                  if (_systemPromptMode == SystemPromptMode.preset)
                    DropdownButtonFormField<String>(
                      value: _systemPromptPreset,
                      decoration: InputDecoration(
                        labelText: '选择预设',
                        labelStyle: TextStyle(color: textSecondary),
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: dividerColor),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: primaryColor),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      items: _availablePresets.map((preset) {
                        return DropdownMenuItem(
                          value: preset,
                          child: Text(
                            _getPresetDisplayName(preset),
                            style: TextStyle(color: textPrimary),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _systemPromptPreset = value);
                        }
                      },
                      dropdownColor: cardColor,
                    )
                  else
                    TextField(
                      controller: _systemPromptController,
                      style: TextStyle(color: textPrimary),
                      decoration: InputDecoration(
                        hintText: '输入自定义系统提示词（可选）',
                        hintStyle: TextStyle(color: textTertiary),
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: dividerColor),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: primaryColor),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      maxLines: 5,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('设置来源', textSecondary),
          _buildInfoCard(
            cardColor: cardColor,
            dividerColor: dividerColor,
            child: Column(
              children: [
                ListTile(
                  title: Text(
                    '用户设置',
                    style: TextStyle(
                      fontSize: 16,
                      color: textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    '必需 - 始终包含',
                    style: TextStyle(
                      fontSize: 13,
                      color: textSecondary,
                    ),
                  ),
                  trailing: Icon(
                    Icons.check_circle,
                    color: primaryColor,
                  ),
                ),
                Divider(height: 1, color: dividerColor),
                SwitchListTile(
                  title: Text(
                    '项目设置',
                    style: TextStyle(
                      fontSize: 16,
                      color: textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    '包含项目特定设置',
                    style: TextStyle(
                      fontSize: 13,
                      color: textSecondary,
                    ),
                  ),
                  value: _includeProjectSettings,
                  onChanged: (value) {
                    setState(() => _includeProjectSettings = value);
                  },
                  activeColor: primaryColor,
                ),
                Divider(height: 1, color: dividerColor),
                SwitchListTile(
                  title: Text(
                    '隐藏工具调用',
                    style: TextStyle(
                      fontSize: 16,
                      color: textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    '不显示工具调用和返回结果',
                    style: TextStyle(
                      fontSize: 13,
                      color: textSecondary,
                    ),
                  ),
                  value: _hideToolCalls,
                  onChanged: (value) {
                    setState(() => _hideToolCalls = value);
                  },
                  activeColor: primaryColor,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('高级设置（对话级）', textSecondary),
          _buildInfoCard(
            cardColor: cardColor,
            dividerColor: dividerColor,
            child: Column(
              children: [
                ListTile(
                  title: Text(
                    '模型选择',
                    style: TextStyle(
                      fontSize: 16,
                      color: textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    _getModelLabel(_advancedOptions?['model']),
                    style: TextStyle(
                      fontSize: 13,
                      color: textSecondary,
                    ),
                  ),
                  trailing: Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: textTertiary,
                  ),
                  onTap: () => _showModelPicker(textPrimary, textSecondary, primaryColor, cardColor),
                ),
                Divider(height: 1, color: dividerColor),
                ListTile(
                  title: Text(
                    '高级参数',
                    style: TextStyle(
                      fontSize: 16,
                      color: textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    _advancedOptions == null || _advancedOptions!.isEmpty
                        ? '使用全局设置'
                        : '已配置 ${_advancedOptions!.length} 个参数',
                    style: TextStyle(
                      fontSize: 13,
                      color: textSecondary,
                    ),
                  ),
                  trailing: Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: textTertiary,
                  ),
                  onTap: () => _showAdvancedOptionsDialog(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getModelLabel(String? model) {
    if (model == null || model.isEmpty) return 'Default';
    switch (model.toLowerCase()) {
      case 'opus': return 'Opus';
      case 'haiku': return 'Haiku';
      default: return model;
    }
  }

  void _showModelPicker(Color textPrimary, Color textSecondary, Color primaryColor, Color cardColor) {
    final models = [
      {'value': null, 'label': 'Default'},
      {'value': 'opus', 'label': 'Opus'},
      {'value': 'haiku', 'label': 'Haiku'},
    ];

    showDialog(
      context: context,
      builder: (context) {
        final currentModel = _advancedOptions?['model'];

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
                onTap: () {
                  setState(() {
                    // Update advanced options with model selection
                    final newAdvancedOptions = Map<String, dynamic>.from(
                      _advancedOptions ?? {}
                    );

                    if (model['value'] == null) {
                      // Default - remove model from advanced options
                      newAdvancedOptions.remove('model');
                    } else {
                      // Set model
                      newAdvancedOptions['model'] = model['value'];
                    }

                    _advancedOptions = newAdvancedOptions.isEmpty ? null : newAdvancedOptions;
                  });
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('关闭', style: TextStyle(color: textSecondary)),
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
          initialOptions: _advancedOptions ?? {},
          onSave: (options) {
            setState(() {
              _advancedOptions = options.isEmpty ? null : options;
            });
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, Color textSecondary) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required Widget child,
    required Color cardColor,
    required Color dividerColor,
  }) {
    return Card(
      color: cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: dividerColor),
      ),
      child: child,
    );
  }

  Widget _buildPermissionOption(
    PermissionMode mode,
    String title,
    String description,
    Color textPrimary,
    Color textSecondary,
    Color textTertiary,
    Color primaryColor,
  ) {
    final isSelected = _permissionMode == mode;
    return ListTile(
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          color: textPrimary,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        description,
        style: TextStyle(
          fontSize: 13,
          color: textSecondary,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check_circle, color: primaryColor)
          : Icon(Icons.circle_outlined, color: textTertiary),
      onTap: () {
        setState(() => _permissionMode = mode);
      },
    );
  }

  Widget _buildModeButton({
    required SystemPromptMode mode,
    required String label,
    required IconData icon,
    required Color backgroundColor,
    required Color primaryColor,
    required Color dividerColor,
    required Color textSecondary,
  }) {
    final isSelected = _systemPromptMode == mode;
    return Material(
      color: isSelected ? primaryColor : backgroundColor,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () {
          setState(() => _systemPromptMode = mode);
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? primaryColor : dividerColor,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? Colors.white : textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getPresetDisplayName(String preset) {
    switch (preset) {
      case 'default':
        return '默认 (Default)';
      case 'advanced':
        return '高级 (Advanced)';
      case 'concise':
        return '简洁 (Concise)';
      case 'creative':
        return '创意 (Creative)';
      default:
        return preset;
    }
  }
}
