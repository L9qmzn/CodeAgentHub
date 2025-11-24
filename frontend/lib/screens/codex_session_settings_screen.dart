import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_theme.dart';
import '../models/codex_user_settings.dart';
import '../repositories/api_codex_repository.dart';

class CodexSessionSettingsScreen extends StatefulWidget {
  final CodexUserSettings settings;
  final ApiCodexRepository repository;
  final Function(CodexUserSettings) onSave;
  final String? sessionId; // 会话 ID（用于显示）
  final String? cwd; // 工作目录（用于显示）

  const CodexSessionSettingsScreen({
    super.key,
    required this.settings,
    required this.repository,
    required this.onSave,
    this.sessionId,
    this.cwd,
  });

  @override
  State<CodexSessionSettingsScreen> createState() => _CodexSessionSettingsScreenState();
}

class _CodexSessionSettingsScreenState extends State<CodexSessionSettingsScreen> {
  late CodexUserSettings _currentSettings;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _currentSettings = widget.settings;
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      // Save to backend
      await widget.repository.updateUserSettings(
        _currentSettings.userId,
        _currentSettings,
      );

      // Call the onSave callback
      widget.onSave(_currentSettings);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('设置已保存'),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              top: 16,
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).size.height - 100,
            ),
          ),
        );
        Navigator.pop(context);
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
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
    final cardColor = Theme.of(context).cardColor;
    final dividerColor = Theme.of(context).dividerColor;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Codex 会话设置'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveSettings,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    '保存',
                    style: TextStyle(
                      color: primaryColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 会话信息部分
          if (widget.sessionId != null || widget.cwd != null) ...[
            _buildSessionInfoSection(cardColor, dividerColor, primaryColor, appColors),
            const SizedBox(height: 16),
          ],
          _buildSettingCard(
            title: '权限策略',
            subtitle: _getApprovalPolicyLabel(_currentSettings.approvalPolicy),
            icon: Icons.security,
            cardColor: cardColor,
            dividerColor: dividerColor,
            primaryColor: primaryColor,
            onTap: () => _showApprovalPolicyPicker(),
          ),
          const SizedBox(height: 12),
          _buildSettingCard(
            title: '沙箱模式',
            subtitle: _getSandboxModeLabel(_currentSettings.sandboxMode),
            icon: Icons.shield,
            cardColor: cardColor,
            dividerColor: dividerColor,
            primaryColor: primaryColor,
            onTap: () => _showSandboxModePicker(),
          ),
          const SizedBox(height: 12),
          _buildSettingCard(
            title: '模型推理努力',
            subtitle: _getModelReasoningEffortLabel(_currentSettings.modelReasoningEffort),
            icon: Icons.psychology,
            cardColor: cardColor,
            dividerColor: dividerColor,
            primaryColor: primaryColor,
            onTap: () => _showModelReasoningEffortPicker(),
          ),
          const SizedBox(height: 12),
          _buildSwitchCard(
            title: '网络访问',
            subtitle: '允许模型访问网络',
            icon: Icons.language,
            value: _currentSettings.networkAccessEnabled,
            cardColor: cardColor,
            dividerColor: dividerColor,
            primaryColor: primaryColor,
            onChanged: (value) {
              setState(() {
                _currentSettings = _currentSettings.copyWith(
                  networkAccessEnabled: value,
                );
              });
            },
          ),
          const SizedBox(height: 12),
          _buildSwitchCard(
            title: 'Web 搜索',
            subtitle: '允许模型进行网络搜索',
            icon: Icons.search,
            value: _currentSettings.webSearchEnabled,
            cardColor: cardColor,
            dividerColor: dividerColor,
            primaryColor: primaryColor,
            onChanged: (value) {
              setState(() {
                _currentSettings = _currentSettings.copyWith(
                  webSearchEnabled: value,
                );
              });
            },
          ),
          const SizedBox(height: 12),
          _buildSwitchCard(
            title: '跳过 Git 检查',
            subtitle: '跳过 Git 仓库检查',
            icon: Icons.commit,
            value: _currentSettings.skipGitRepoCheck,
            cardColor: cardColor,
            dividerColor: dividerColor,
            primaryColor: primaryColor,
            onChanged: (value) {
              setState(() {
                _currentSettings = _currentSettings.copyWith(
                  skipGitRepoCheck: value,
                );
              });
            },
          ),
          const SizedBox(height: 12),
          _buildSwitchCard(
            title: '隐藏工具调用',
            subtitle: '不显示工具调用和返回结果',
            icon: Icons.visibility_off,
            value: _currentSettings.hideToolCalls,
            cardColor: cardColor,
            dividerColor: dividerColor,
            primaryColor: primaryColor,
            onChanged: (value) {
              setState(() {
                _currentSettings = _currentSettings.copyWith(
                  hideToolCalls: value,
                );
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSettingCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color cardColor,
    required Color dividerColor,
    required Color primaryColor,
    required VoidCallback onTap,
  }) {
    final appColors = context.appColors;
    final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;
    return Card(
      color: cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: dividerColor),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: primaryColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: appColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: appColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required Color cardColor,
    required Color dividerColor,
    required Color primaryColor,
    required ValueChanged<bool> onChanged,
  }) {
    final appColors = context.appColors;
    final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;
    return Card(
      color: cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: primaryColor, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: appColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: primaryColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionInfoSection(Color cardColor, Color dividerColor, Color primaryColor, dynamic appColors) {
    final textPrimary = Theme.of(context).colorScheme.onSurface;
    final textSecondary = appColors.textSecondary;
    final textTertiary = appColors.textTertiary;

    return Card(
      color: cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: dividerColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '会话信息',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textSecondary,
              ),
            ),
          ),
          if (widget.sessionId != null) ...[
            ListTile(
              dense: true,
              title: Text(
                '会话 ID',
                style: TextStyle(
                  fontSize: 14,
                  color: textPrimary,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  widget.sessionId!,
                  style: TextStyle(
                    fontSize: 12,
                    color: textSecondary,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              trailing: IconButton(
                icon: Icon(
                  Icons.copy,
                  color: textTertiary,
                  size: 18,
                ),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: widget.sessionId!));
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
          ],
          if (widget.sessionId != null && widget.cwd != null)
            Divider(height: 1, color: dividerColor),
          if (widget.cwd != null) ...[
            ListTile(
              dense: true,
              title: Text(
                '工作目录',
                style: TextStyle(
                  fontSize: 14,
                  color: textPrimary,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  widget.cwd!,
                  style: TextStyle(
                    fontSize: 12,
                    color: textSecondary,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              trailing: Icon(
                Icons.lock_outline,
                color: textTertiary,
                size: 18,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getApprovalPolicyLabel(String policy) {
    switch (policy) {
      case 'never':
        return '从不请求批准';
      case 'on-request':
        return '工具使用时请求批准';
      case 'on-failure':
        return '失败时请求批准';
      case 'untrusted':
        return '不受信任时请求批准';
      default:
        return policy;
    }
  }

  String _getSandboxModeLabel(String mode) {
    switch (mode) {
      case 'read-only':
        return '只读';
      case 'workspace-write':
        return '工作区可写';
      case 'danger-full-access':
        return '完全访问（危险）';
      default:
        return mode;
    }
  }

  String _getModelReasoningEffortLabel(String effort) {
    switch (effort) {
      case 'low':
        return '低';
      case 'medium':
        return '中';
      case 'high':
        return '高';
      default:
        return effort;
    }
  }

  void _showApprovalPolicyPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => _buildPicker(
        title: '选择权限策略',
        options: [
          ('never', '从不请求批准'),
          ('on-request', '工具使用时请求批准'),
          ('on-failure', '失败时请求批准'),
          ('untrusted', '不受信任时请求批准'),
        ],
        currentValue: _currentSettings.approvalPolicy,
        onSelected: (value) {
          setState(() {
            _currentSettings = _currentSettings.copyWith(approvalPolicy: value);
          });
        },
      ),
    );
  }

  void _showSandboxModePicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => _buildPicker(
        title: '选择沙箱模式',
        options: [
          ('read-only', '只读'),
          ('workspace-write', '工作区可写'),
          ('danger-full-access', '完全访问（危险）'),
        ],
        currentValue: _currentSettings.sandboxMode,
        onSelected: (value) {
          setState(() {
            _currentSettings = _currentSettings.copyWith(sandboxMode: value);
          });
        },
      ),
    );
  }

  void _showModelReasoningEffortPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => _buildPicker(
        title: '选择模型推理努力',
        options: [
          ('low', '低'),
          ('medium', '中'),
          ('high', '高'),
        ],
        currentValue: _currentSettings.modelReasoningEffort,
        onSelected: (value) {
          setState(() {
            _currentSettings = _currentSettings.copyWith(modelReasoningEffort: value);
          });
        },
      ),
    );
  }

  Widget _buildPicker({
    required String title,
    required List<(String, String)> options,
    required String currentValue,
    required ValueChanged<String> onSelected,
  }) {
    final appColors = context.appColors;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          ...options.map((option) {
            final (value, label) = option;
            final isSelected = value == currentValue;
            return ListTile(
              title: Text(label),
              trailing: isSelected
                  ? Icon(Icons.check, color: primaryColor)
                  : null,
              selected: isSelected,
              onTap: () {
                onSelected(value);
                Navigator.pop(context);
              },
            );
          }),
        ],
      ),
    );
  }
}
