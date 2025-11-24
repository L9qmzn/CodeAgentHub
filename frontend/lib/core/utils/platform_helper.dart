import 'dart:io';
import 'package:flutter/material.dart';

/// 平台辅助工具类，用于处理不同平台的差异化逻辑
class PlatformHelper {
  /// 是否为桌面平台（Windows、macOS、Linux）
  static bool get isDesktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  /// 是否为移动平台（Android、iOS）
  static bool get isMobile => Platform.isAndroid || Platform.isIOS;

  /// 是否为Windows平台
  static bool get isWindows => Platform.isWindows;

  /// 是否为Android平台
  static bool get isAndroid => Platform.isAndroid;

  /// 获取适合当前平台的滚动物理效果
  /// 桌面端：BouncingScrollPhysics - 更流畅的回弹效果
  /// 移动端：默认平台滚动效果
  static ScrollPhysics getScrollPhysics() {
    if (isDesktop) {
      return const BouncingScrollPhysics();
    }
    return const AlwaysScrollableScrollPhysics();
  }

  /// 消息文本是否应该可选择
  /// 桌面端：true - 方便复制文本
  /// 移动端：false - 保持原有触摸交互
  static bool get shouldEnableTextSelection => isDesktop;

  /// 获取标签栏的滚动行为
  /// 桌面端：需要显式滚动条
  /// 移动端：使用默认滚动行为
  static bool get showTabBarScrollbar => isDesktop;
}
