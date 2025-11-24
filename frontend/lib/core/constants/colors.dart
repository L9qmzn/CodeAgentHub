import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// AppColors - 用于向后兼容的静态颜色
/// 推荐使用 Theme.of(context) 或 context.appColors 获取主题相关的颜色
class AppColors {
  // 默认fallback颜色（浅色模式）- 保持原来的暖色系
  static const Color background = Color(0xFFFFFBF5);
  static const Color primary = Color(0xFFE8A87C);
  static const Color primaryLight = Color(0xFFF5D4B8);
  static const Color secondary = Color(0xFFD4A574);

  static const Color claudeBubble = Color(0xFFF5EDE3);
  static const Color userBubble = Color(0xFFFFEFD5);

  static const Color textPrimary = Color(0xFF2C2416);
  static const Color textSecondary = Color(0xFF6B5D4F);
  static const Color textTertiary = Color(0xFF9B8F80);

  static const Color cardBackground = Color(0xFFFFF8F0);
  static const Color divider = Color(0xFFE8DED0);

  static const Color success = Color(0xFF8BC34A);
  static const Color error = Color(0xFFE57373);
  static const Color warning = Color(0xFFFFB74D);

  static const Color codeBackground = Color(0xFFF5F0E8);
  static const Color toolBackground = Color(0xFFFFF4E5);
}
