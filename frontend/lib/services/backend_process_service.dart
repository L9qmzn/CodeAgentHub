import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;

/// 后端进程管理服务（桌面平台：Windows/macOS/Linux）
/// 负责在应用启动时自动启动后端，应用退出时自动关闭后端
/// 支持多个前端实例共享一个后端，支持自定义端口（默认 8207）
class BackendProcessService {
  static BackendProcessService? _instance;
  Process? _backendProcess;
  bool _isBackendRunning = false;
  final int _backendPort = 8207; // 默认端口
  int _currentPort = 8207; // 当前使用的端口
  int? _backendPid; // 记录我们启动的后端进程 PID

  BackendProcessService._();

  static BackendProcessService getInstance() {
    _instance ??= BackendProcessService._();
    return _instance!;
  }

  /// 检查指定端口是否有我们的后端在运行
  Future<bool> _isOurBackendRunning(int port) async {
    try {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/health'),
      ).timeout(const Duration(seconds: 2));

      // 返回 200 或 401 都说明是我们的后端（401 是认证失败，但后端存在）
      if (response.statusCode == 200 || response.statusCode == 401) {
        print('DEBUG BackendProcessService: Our backend is already running on port $port');
        return true;
      }
    } catch (e) {
      print('DEBUG BackendProcessService: No backend detected on port $port: $e');
    }
    return false;
  }

  /// 启动后端进程（桌面平台：Windows/macOS/Linux）
  /// [showWindow] 是否显示后端窗口（仅开发模式有效，仅 Windows 支持）
  /// [port] 后端端口，默认 8207
  /// 返回值：后端是否成功运行（包括复用已存在的后端）
  Future<bool> startBackend({bool showWindow = false, int? port}) async {
    // 仅桌面平台支持
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      print('WARN BackendProcessService: Backend auto-start only supported on desktop platforms');
      return false;
    }

    // 使用传入的端口或默认端口
    final targetPort = port ?? _backendPort;
    if (_isBackendRunning) {
      print('DEBUG BackendProcessService: Backend already running (by this instance)');
      return true;
    }

    // 先检查端口上是否已有我们的后端
    if (await _isOurBackendRunning(targetPort)) {
      _isBackendRunning = true;
      _currentPort = targetPort;
      _backendPid = null; // 不是我们启动的，不记录 PID
      print('DEBUG BackendProcessService: Reusing existing backend on port $targetPort (not owned)');
      return true;
    }

    // 没有后端在运行，尝试启动
    try {
      final exePath = Platform.resolvedExecutable;
      final exeDir = path.dirname(exePath);

      // 检查 esbuild 打包的 backend.js
      final backendJsPath = path.join(exeDir, 'backend', 'backend.js');

      print('DEBUG BackendProcessService: Current exe: $exePath');
      print('DEBUG BackendProcessService: Backend JS path: $backendJsPath');

      String executable;
      List<String> arguments;
      String workingDir;

      // 使用 esbuild 打包的 backend.js
      if (await File(backendJsPath).exists()) {
        final backendDir = path.join(exeDir, 'backend');
        executable = 'node';
        arguments = ['backend.js', '--port', '$targetPort'];
        workingDir = backendDir;
        print('DEBUG BackendProcessService: Using esbuild-bundled backend.js');
      } else {
        // 开发模式：使用 npm run dev
        // 目标路径：backend/ts_backend
        // 需要返回到项目根目录（CodeAgentHub）
        final backendProjectDir = path.join(exeDir, '..', '..', '..', '..', '..', '..', 'backend', 'ts_backend');
        final normalizedDir = path.normalize(backendProjectDir);

        if (!await Directory(normalizedDir).exists()) {
          print('ERROR BackendProcessService: Backend development directory not found: $normalizedDir');
          return false;
        }

        workingDir = normalizedDir;

        if (Platform.isWindows) {
          executable = 'cmd.exe';
          if (showWindow) {
            // 显示窗口：在新窗口中启动，方便查看日志
            arguments = ['/c', 'start', '"CodeAgentHub Backend"', 'cmd', '/k', 'set', 'PORT=$targetPort', '&&', 'npm', 'run', 'dev'];
            print('DEBUG BackendProcessService: Using npm run dev (visible window)');
          } else {
            // 隐藏窗口：使用 CREATE_NO_WINDOW 标志（通过 detached 模式实现）
            arguments = ['/c', 'set', 'PORT=$targetPort', '&&', 'npm', 'run', 'dev'];
            print('DEBUG BackendProcessService: Using npm run dev (hidden)');
          }
        } else {
          // macOS/Linux: 使用 sh
          executable = '/bin/sh';
          arguments = ['-c', 'PORT=$targetPort npm run dev'];
          print('DEBUG BackendProcessService: Using npm run dev (Unix)');
        }
        print('DEBUG BackendProcessService: Backend directory: $normalizedDir');
      }

      // 启动后端
      print('DEBUG BackendProcessService: Starting backend on port $targetPort...');

      // 判断启动模式：
      // - cmd.exe (开发模式 npm run dev): 使用 detached
      // - node (esbuild 打包): 使用 detached (不显示窗口)
      final isDevMode = executable == 'cmd.exe';
      final isNodeBundle = executable == 'node';

      _backendProcess = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDir,
        mode: (isDevMode || isNodeBundle) ? ProcessStartMode.detached : ProcessStartMode.detachedWithStdio,
      );

      _isBackendRunning = true;
      print('DEBUG BackendProcessService: Backend launcher started with PID: ${_backendProcess!.pid}');

      // 只有 exe 打包模式才监听输出（cmd 和 node 都使用 detached，无法监听）
      if (!isDevMode && !isNodeBundle) {
        // 监听输出
        _backendProcess!.stdout.listen((data) {
          final output = String.fromCharCodes(data);
          if (output.trim().isNotEmpty) {
            print('Backend stdout: $output');
          }
        }, onError: (error) => print('Backend stdout error: $error'));

        _backendProcess!.stderr.listen((data) {
          final output = String.fromCharCodes(data);
          if (output.trim().isNotEmpty) {
            print('Backend stderr: $output');
          }
        }, onError: (error) => print('Backend stderr error: $error'));

        // 监听进程退出
        _backendProcess!.exitCode.then((exitCode) {
          print('DEBUG BackendProcessService: Backend exited with code $exitCode');
          _isBackendRunning = false;
        }).catchError((error) {
          print('DEBUG BackendProcessService: Backend exit error: $error');
          _isBackendRunning = false;
        });
      }

      // 等待后端启动完成（轮询检查，最多 10 秒）
      print('DEBUG BackendProcessService: Waiting for backend to initialize...');
      const maxWaitTime = Duration(seconds: 10);
      const checkInterval = Duration(milliseconds: 500);
      final startTime = DateTime.now();

      while (DateTime.now().difference(startTime) < maxWaitTime) {
        if (await _isOurBackendRunning(targetPort)) {
          final elapsed = DateTime.now().difference(startTime).inMilliseconds;

          // 记录当前端口
          _currentPort = targetPort;

          // 查找实际的后端进程 PID（通过端口）
          try {
            if (Platform.isWindows) {
              final result = await Process.run('powershell', [
                '-Command',
                '(Get-NetTCPConnection -LocalPort $targetPort -State Listen -ErrorAction SilentlyContinue).OwningProcess'
              ]);
              final output = result.stdout.toString().trim();
              if (output.isNotEmpty) {
                _backendPid = int.tryParse(output.split('\n').first.trim());
                print('DEBUG BackendProcessService: Tracked backend PID: $_backendPid');
              }
            } else {
              // macOS/Linux: 使用 lsof 查找监听端口的进程
              final result = await Process.run('lsof', ['-ti', ':$targetPort']);
              final output = result.stdout.toString().trim();
              if (output.isNotEmpty) {
                _backendPid = int.tryParse(output.split('\n').first.trim());
                print('DEBUG BackendProcessService: Tracked backend PID: $_backendPid');
              }
            }
          } catch (e) {
            print('WARN BackendProcessService: Failed to get backend PID: $e');
          }

          print('DEBUG BackendProcessService: Backend started successfully in ${elapsed}ms on port $targetPort');
          return true;
        }
        await Future.delayed(checkInterval);
      }

      // 超时仍未启动
      print('ERROR BackendProcessService: Backend failed to start within 10 seconds');
      print('ERROR BackendProcessService: Port may be occupied by another program');
      _isBackendRunning = false;
      return false;
    } catch (e) {
      print('ERROR BackendProcessService: Failed to start backend: $e');
      _isBackendRunning = false;
      return false;
    }
  }

  /// 停止后端进程（只关闭我们启动的后端，桌面平台）
  Future<void> stopBackend() async {
    // 仅桌面平台支持
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      print('WARN BackendProcessService: Backend management only supported on desktop platforms');
      return;
    }

    if (!_isBackendRunning) {
      print('DEBUG BackendProcessService: Backend not running');
      return;
    }

    // 如果后端不是我们启动的（_backendPid 为 null），则不关闭
    if (_backendPid == null) {
      print('DEBUG BackendProcessService: Backend is not owned by this instance, skipping shutdown');
      _isBackendRunning = false;
      _backendProcess = null;
      return;
    }

    try {
      print('DEBUG BackendProcessService: Stopping backend with PID $_backendPid...');

      if (Platform.isWindows) {
        // Windows: 只关闭我们记录的 PID
        print('DEBUG BackendProcessService: Killing our backend process $_backendPid');
        final killResult = await Process.run('taskkill', ['/F', '/PID', '$_backendPid']);
        print('DEBUG BackendProcessService: taskkill result: ${killResult.stdout}');

        // 同时尝试杀掉启动器进程树（如果使用了 cmd.exe）
        if (_backendProcess != null) {
          print('DEBUG BackendProcessService: Also killing launcher process ${_backendProcess!.pid}');
          await Process.run('taskkill', ['/F', '/T', '/PID', '${_backendProcess!.pid}']);
        }
      } else {
        // macOS/Linux: 使用 kill 命令
        print('DEBUG BackendProcessService: Killing our backend process $_backendPid');
        final killResult = await Process.run('kill', ['$_backendPid']);
        print('DEBUG BackendProcessService: kill result: ${killResult.stdout}');

        // 同时尝试杀掉启动器进程（如果使用了 sh）
        if (_backendProcess != null) {
          print('DEBUG BackendProcessService: Also killing launcher process ${_backendProcess!.pid}');
          await Process.run('kill', ['${_backendProcess!.pid}']);
        }
      }

      _isBackendRunning = false;
      _backendProcess = null;
      _backendPid = null;
      print('DEBUG BackendProcessService: Backend stopped');
    } catch (e) {
      print('ERROR BackendProcessService: Failed to stop backend: $e');
    }
  }

  /// 检查后端是否正在运行
  bool get isRunning => _isBackendRunning;

  /// 获取后端端口
  int get backendPort => _currentPort;

  /// 获取后端 URL
  String get backendUrl => 'http://127.0.0.1:$_currentPort';
}
