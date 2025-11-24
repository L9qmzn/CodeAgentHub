import '../services/config_service.dart';

/// 简单的应用日志工具
/// 根据 ConfigService 中的 debugLogEnabled 配置决定是否输出调试日志
class AppLogger {
  /// 输出调试日志
  ///
  /// 示例:
  /// ```dart
  /// await AppLogger.debug('ChatScreen', 'Loading messages for session $sessionId');
  /// ```
  ///
  /// 输出格式:
  /// ```
  /// flutter: DEBUG ChatScreen: Loading messages for session c77bc7d2-166d-4643-b6d7-d8f43adfed94
  /// ```
  static Future<void> debug(String tag, String message) async {
    final config = await ConfigService.getInstance();
    if (config.debugLogEnabled) {
      print('flutter: DEBUG $tag: $message');
    }
  }
}
