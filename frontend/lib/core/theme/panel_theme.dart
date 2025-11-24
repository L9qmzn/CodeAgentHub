import 'package:flutter/material.dart';

/// 面板类型
enum PanelType {
  left,   // 左侧面板（主面板）
  right,  // 右侧面板（分屏时的副面板）
  single, // 单面板模式（非分屏）
}

/// 面板主题数据
class PanelThemeData {
  final PanelType panelType;
  final Color? backgroundColorOverride; // 背景色覆盖

  const PanelThemeData({
    this.panelType = PanelType.single,
    this.backgroundColorOverride,
  });

  /// 获取调整后的背景色
  Color getBackgroundColor(BuildContext context) {
    if (backgroundColorOverride != null) {
      return backgroundColorOverride!;
    }
    return Theme.of(context).scaffoldBackgroundColor;
  }

  /// 获取调整后的卡片颜色
  Color getCardColor(BuildContext context) {
    final baseColor = Theme.of(context).cardColor;
    if (backgroundColorOverride != null) {
      // 如果有背景色覆盖，卡片颜色也做相应调整
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Color.alphaBlend(
        isDark
            ? Colors.white.withOpacity(0.02)
            : Colors.black.withOpacity(0.02),
        baseColor,
      );
    }
    return baseColor;
  }
}

/// 面板主题 InheritedWidget
class PanelTheme extends InheritedWidget {
  final PanelThemeData data;

  const PanelTheme({
    super.key,
    required this.data,
    required super.child,
  });

  static PanelThemeData of(BuildContext context) {
    final widget = context.dependOnInheritedWidgetOfExactType<PanelTheme>();
    return widget?.data ?? const PanelThemeData();
  }

  /// 便捷方法：获取背景色
  static Color backgroundColor(BuildContext context) {
    return of(context).getBackgroundColor(context);
  }

  /// 便捷方法：获取卡片颜色
  static Color cardColor(BuildContext context) {
    return of(context).getCardColor(context);
  }

  /// 便捷方法：判断是否是右侧面板
  static bool isRightPanel(BuildContext context) {
    return of(context).panelType == PanelType.right;
  }

  @override
  bool updateShouldNotify(PanelTheme oldWidget) {
    return data.panelType != oldWidget.data.panelType ||
           data.backgroundColorOverride != oldWidget.data.backgroundColorOverride;
  }
}
