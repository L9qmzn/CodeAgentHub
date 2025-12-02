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

  /// 检查 Node.js 是否已安装并在 PATH 中
  Future<bool> _checkNodeInstalled() async {
    try {
      final result = await Process.run('node', ['--version']);
      if (result.exitCode == 0) {
        final version = result.stdout.toString().trim();
        print('DEBUG BackendProcessService: Node.js found: $version');
        return true;
      }
    } catch (e) {
      print('DEBUG BackendProcessService: Node.js check failed: $e');
    }
    return false;
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
  /// [port] 后端端口，默认 8207
  /// 返回值：后端是否成功运行（包括复用已存在的后端）
  /// 注意：后端窗口始终隐藏，如需调试请使用 start_backend_debug.bat
  Future<bool> startBackend({int? port}) async {
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

      // 即使不是我们启动的，也记录 PID，以便用户选择关闭时能够关闭
      try {
        if (Platform.isWindows) {
          final result = await Process.run('powershell', [
            '-Command',
            '(Get-NetTCPConnection -LocalPort $targetPort -State Listen -ErrorAction SilentlyContinue).OwningProcess'
          ]);
          final output = result.stdout.toString().trim();
          if (output.isNotEmpty) {
            _backendPid = int.tryParse(output.split('\n').first.trim());
            print('DEBUG BackendProcessService: Reusing existing backend on port $targetPort with PID $_backendPid');
          }
        } else {
          final result = await Process.run('lsof', ['-ti', ':$targetPort']);
          final output = result.stdout.toString().trim();
          if (output.isNotEmpty) {
            _backendPid = int.tryParse(output.split('\n').first.trim());
            print('DEBUG BackendProcessService: Reusing existing backend on port $targetPort with PID $_backendPid');
          }
        }
      } catch (e) {
        print('WARN BackendProcessService: Failed to get PID of existing backend: $e');
      }

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

      // 如果是打包模式，检查 Node.js 是否安装
      if (await File(backendJsPath).exists()) {
        final nodeCheck = await _checkNodeInstalled();
        if (!nodeCheck) {
          print('ERROR BackendProcessService: Node.js not found in PATH');
          print('ERROR BackendProcessService: Please install Node.js from https://nodejs.org/');
          return false;
        }
      }

      String executable;
      List<String> arguments;
      String workingDir;

      // 使用 esbuild 打包的 backend.js
      if (await File(backendJsPath).exists()) {
        final backendDir = path.join(exeDir, 'backend');
        workingDir = backendDir;

        // 打包模式：使用预加载脚本隐藏所有子进程窗口
        executable = 'node';

        // 检查预加载脚本是否存在
        final preloadScript = path.join(backendDir, 'hide-windows-preload.js');
        if (Platform.isWindows && await File(preloadScript).exists()) {
          // Windows: 使用预加载脚本（使用绝对路径）
          arguments = ['--require', preloadScript, 'backend.js', '--port', '$targetPort'];
          print('DEBUG BackendProcessService: Using backend.js with Windows hide preload: $preloadScript');
        } else {
          // 非 Windows 或预加载脚本不存在
          arguments = ['backend.js', '--port', '$targetPort'];
          print('DEBUG BackendProcessService: Using backend.js without preload (script exists: ${await File(preloadScript).exists()})');
        }
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

        // 开发模式：窗口始终隐藏
        if (Platform.isWindows) {
          executable = 'cmd.exe';
          arguments = ['/c', 'set', 'PORT=$targetPort', '&&', 'npm', 'run', 'dev'];
          print('DEBUG BackendProcessService: Using npm run dev (hidden window)');
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

    // 如果 _backendPid 为 null，尝试通过端口查找 PID
    if (_backendPid == null) {
      print('DEBUG BackendProcessService: PID not recorded, trying to find by port $_currentPort');
      try {
        if (Platform.isWindows) {
          final result = await Process.run('powershell', [
            '-Command',
            '(Get-NetTCPConnection -LocalPort $_currentPort -State Listen -ErrorAction SilentlyContinue).OwningProcess'
          ]);
          final output = result.stdout.toString().trim();
          if (output.isNotEmpty) {
            _backendPid = int.tryParse(output.split('\n').first.trim());
            print('DEBUG BackendProcessService: Found backend PID: $_backendPid');
          }
        } else {
          final result = await Process.run('lsof', ['-ti', ':$_currentPort']);
          final output = result.stdout.toString().trim();
          if (output.isNotEmpty) {
            _backendPid = int.tryParse(output.split('\n').first.trim());
            print('DEBUG BackendProcessService: Found backend PID: $_backendPid');
          }
        }
      } catch (e) {
        print('WARN BackendProcessService: Failed to find backend PID: $e');
      }

      // 如果还是找不到 PID，放弃关闭
      if (_backendPid == null) {
        print('WARN BackendProcessService: Cannot find backend PID, skipping shutdown');
        _isBackendRunning = false;
        _backendProcess = null;
        return;
      }
    }

    try {
      print('DEBUG BackendProcessService: Stopping backend with PID $_backendPid...');

      if (Platform.isWindows) {
        // Windows: 关闭后端进程（node.exe 或 npm）
        print('DEBUG BackendProcessService: Killing backend process $_backendPid');
        final killResult = await Process.run('taskkill', ['/F', '/T', '/PID', '$_backendPid']);
        print('DEBUG BackendProcessService: taskkill stdout: ${killResult.stdout}');
        if (killResult.stderr.toString().isNotEmpty) {
          print('DEBUG BackendProcessService: taskkill stderr: ${killResult.stderr}');
        }
        print('DEBUG BackendProcessService: taskkill exit code: ${killResult.exitCode}');

        // 等待一小段时间确保进程完全关闭
        await Future.delayed(const Duration(milliseconds: 300));

        // 验证进程是否已关闭
        final checkResult = await Process.run('tasklist', ['/FI', 'PID eq $_backendPid']);
        final isStillRunning = checkResult.stdout.toString().contains('$_backendPid');
        if (isStillRunning) {
          print('WARN BackendProcessService: Process $_backendPid still running after taskkill');
        } else {
          print('DEBUG BackendProcessService: Process $_backendPid confirmed stopped');
        }
      } else {
        // macOS/Linux: 使用 kill 命令
        print('DEBUG BackendProcessService: Killing backend process $_backendPid');
        // 先尝试 SIGTERM (graceful shutdown)
        await Process.run('kill', ['$_backendPid']);

        // 等待 500ms
        await Future.delayed(const Duration(milliseconds: 500));

        // 检查是否还在运行，如果是则强制 SIGKILL
        final checkResult = await Process.run('ps', ['-p', '$_backendPid']);
        if (checkResult.exitCode == 0) {
          print('DEBUG BackendProcessService: Process still running, sending SIGKILL');
          await Process.run('kill', ['-9', '$_backendPid']);
        } else {
          print('DEBUG BackendProcessService: Process $_backendPid confirmed stopped');
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
