import 'dart:io';
import 'dart:async';
import 'dart:convert';

/// 单实例服务 - 确保应用只运行一个实例
/// 如果已有实例运行，将参数传递给现有实例
class SingleInstanceService {
  static const int _port = 45678; // 本地通信端口
  static const String _host = '127.0.0.1';

  ServerSocket? _server;
  final _pathController = StreamController<String>.broadcast();

  /// 监听新路径请求的流
  Stream<String> get onNewPath => _pathController.stream;

  /// 尝试作为主实例启动
  /// 返回 true 表示成功成为主实例
  /// 返回 false 表示已有其他实例在运行
  Future<bool> tryBecomeMainInstance() async {
    try {
      // 尝试创建服务器
      _server = await ServerSocket.bind(_host, _port, shared: false);
      print('SingleInstance: Became main instance, listening on port $_port');

      // 监听连接
      _server!.listen(_handleConnection);

      return true;
    } on SocketException catch (e) {
      // 端口已被占用，说明已有实例在运行
      print('SingleInstance: Port $_port is already in use: $e');
      return false;
    }
  }

  /// 向已运行的实例发送路径参数
  Future<bool> sendPathToExistingInstance(String path) async {
    try {
      final socket = await Socket.connect(_host, _port);

      // 发送路径
      final message = json.encode({'type': 'open_path', 'path': path});
      socket.write(message);

      await socket.flush();
      await socket.close();

      print('SingleInstance: Sent path to existing instance: $path');
      return true;
    } catch (e) {
      print('SingleInstance: Failed to send path to existing instance: $e');
      return false;
    }
  }

  /// 处理来自其他实例的连接
  void _handleConnection(Socket socket) {
    print('SingleInstance: Received connection from another instance');

    final buffer = StringBuffer();

    socket.listen(
      (data) {
        buffer.write(utf8.decode(data));
      },
      onDone: () {
        try {
          final message = json.decode(buffer.toString());
          if (message['type'] == 'open_path' && message['path'] != null) {
            final path = message['path'] as String;
            print('SingleInstance: Received path: $path');
            _pathController.add(path);
          }
        } catch (e) {
          print('SingleInstance: Error parsing message: $e');
        }
        socket.close();
      },
      onError: (e) {
        print('SingleInstance: Socket error: $e');
        socket.close();
      },
    );
  }

  /// 关闭服务
  Future<void> dispose() async {
    await _server?.close();
    await _pathController.close();
  }
}
