import 'package:flutter/material.dart';

class AppTheme {
  /// 生成主题数据
  static ThemeData generate({
    required bool isDark,
    required String? fontFamily,
    double fontScale = 1.0,
  }) {
    final brightness = isDark ? Brightness.dark : Brightness.light;

    // 使用原来的暖色系主题色
    final primaryColor = isDark ? const Color(0xFFE8A87C) : const Color(0xFFE8A87C);

    // 根据深色模式选择背景色
    final backgroundColor = isDark ? const Color(0xFF121212) : const Color(0xFFFFFBF5);
    final cardColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFF8F0);
    final surfaceColor = isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF5EDE3);

    // 文字颜色
    final textPrimary = isDark ? const Color(0xFFE8E6E3) : const Color(0xFF2C2416);
    final textSecondary = isDark ? const Color(0xFFB0AEA8) : const Color(0xFF6B5D4F);
    final textTertiary = isDark ? const Color(0xFF787672) : const Color(0xFF9B8F80);

    // 分隔线颜色
    final dividerColor = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE8DED0);

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: primaryColor,
      onPrimary: Colors.white,
      secondary: primaryColor,
      onSecondary: Colors.white,
      surface: backgroundColor,
      onSurface: textPrimary,
      error: const Color(0xFFE57373),
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: backgroundColor,
      cardColor: cardColor,
      dividerColor: dividerColor,

      // AppBar主题
      appBarTheme: AppBarTheme(
        backgroundColor: backgroundColor,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          fontFamily: fontFamily,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),

      // Card主题
      cardTheme: CardTheme(
        color: cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: dividerColor),
        ),
      ),

      // 输入框主题
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: dividerColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: dividerColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
      ),

      // 按钮主题
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),

      // 文字主题（应用字号缩放）
      textTheme: TextTheme(
        bodyLarge: TextStyle(fontSize: 16 * fontScale, color: textPrimary, fontFamily: fontFamily),
        bodyMedium: TextStyle(fontSize: 14 * fontScale, color: textPrimary, fontFamily: fontFamily),
        bodySmall: TextStyle(fontSize: 12 * fontScale, color: textSecondary, fontFamily: fontFamily),
        titleLarge: TextStyle(fontSize: 22 * fontScale, fontWeight: FontWeight.bold, color: textPrimary, fontFamily: fontFamily),
        titleMedium: TextStyle(fontSize: 18 * fontScale, fontWeight: FontWeight.w600, color: textPrimary, fontFamily: fontFamily),
        titleSmall: TextStyle(fontSize: 14 * fontScale, fontWeight: FontWeight.w600, color: textPrimary, fontFamily: fontFamily),
      ),

      // 设置全局默认字体
      fontFamily: fontFamily,

      // Icon主题
      iconTheme: IconThemeData(color: textSecondary),

      // ListTile主题
      listTileTheme: ListTileThemeData(
        textColor: textPrimary,
        iconColor: textSecondary,
      ),

      // 其他扩展
      extensions: <ThemeExtension<dynamic>>[
        AppColorExtension(
          claudeBubble: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF5EDE3),
          userBubble: isDark ? const Color(0xFF3A2A1A) : const Color(0xFFFFEFD5),
          codeBackground: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F0E8),
          toolBackground: isDark ? const Color(0xFF2A2520) : const Color(0xFFFFF4E5),
          textSecondary: textSecondary,
          textTertiary: textTertiary,
        ),
      ],
    );
  }
}

/// 自定义颜色扩展
class AppColorExtension extends ThemeExtension<AppColorExtension> {
  final Color claudeBubble;
  final Color userBubble;
  final Color codeBackground;
  final Color toolBackground;
  final Color textSecondary;
  final Color textTertiary;

  AppColorExtension({
    required this.claudeBubble,
    required this.userBubble,
    required this.codeBackground,
    required this.toolBackground,
    required this.textSecondary,
    required this.textTertiary,
  });

  @override
  ThemeExtension<AppColorExtension> copyWith({
    Color? claudeBubble,
    Color? userBubble,
    Color? codeBackground,
    Color? toolBackground,
    Color? textSecondary,
    Color? textTertiary,
  }) {
    return AppColorExtension(
      claudeBubble: claudeBubble ?? this.claudeBubble,
      userBubble: userBubble ?? this.userBubble,
      codeBackground: codeBackground ?? this.codeBackground,
      toolBackground: toolBackground ?? this.toolBackground,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
    );
  }

  @override
  ThemeExtension<AppColorExtension> lerp(
    ThemeExtension<AppColorExtension>? other,
    double t,
  ) {
    if (other is! AppColorExtension) return this;
    return AppColorExtension(
      claudeBubble: Color.lerp(claudeBubble, other.claudeBubble, t)!,
      userBubble: Color.lerp(userBubble, other.userBubble, t)!,
      codeBackground: Color.lerp(codeBackground, other.codeBackground, t)!,
      toolBackground: Color.lerp(toolBackground, other.toolBackground, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
    );
  }
}

/// 帮助函数获取自定义颜色
extension AppColorExtensionGetter on BuildContext {
  AppColorExtension get appColors => Theme.of(this).extension<AppColorExtension>()!;
}
