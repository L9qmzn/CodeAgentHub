import 'dart:io';

// 条件导入：仅在 Windows 平台使用 FFI 和注册表库
import 'dart:ffi' if (dart.library.html) 'dart:ffi';
import 'package:ffi/ffi.dart' if (dart.library.html) 'package:ffi/ffi.dart';
import 'package:win32_registry/win32_registry.dart' if (dart.library.html) 'package:win32_registry/win32_registry.dart';

// Windows Shell32 API 绑定（仅在 Windows 上使用）
typedef ShellExecuteNative = Int32 Function(
  IntPtr hwnd,
  Pointer<Utf16> lpOperation,
  Pointer<Utf16> lpFile,
  Pointer<Utf16> lpParameters,
  Pointer<Utf16> lpDirectory,
  Int32 nShowCmd,
);
typedef ShellExecuteDart = int Function(
  int hwnd,
  Pointer<Utf16> lpOperation,
  Pointer<Utf16> lpFile,
  Pointer<Utf16> lpParameters,
  Pointer<Utf16> lpDirectory,
  int nShowCmd,
);

/// Windows 注册表服务，用于管理右键菜单等功能
class WindowsRegistryService {
  static const String _menuName = 'CodeAgentHub';
  static const String _menuDisplayName = '使用 CodeAgent Hub 打开';

  // 注册表路径
  static const String _directoryShellPath = r'Directory\shell';
  static const String _directoryBackgroundShellPath = r'Directory\Background\shell';

  /// 检查右键菜单是否已注册
  static Future<bool> isContextMenuRegistered() async {
    if (!Platform.isWindows) return false;

    try {
      final key = Registry.openPath(
        RegistryHive.classesRoot,
        path: '$_directoryShellPath\\$_menuName',
      );
      key.close();
      print('DEBUG Registry: Context menu is registered');
      return true;
    } catch (e) {
      print('DEBUG Registry: Context menu NOT registered - $e');
      return false;
    }
  }

  /// 获取当前注册的 exe 路径
  static Future<String?> getRegisteredExePath() async {
    if (!Platform.isWindows) return null;

    try {
      final key = Registry.openPath(
        RegistryHive.classesRoot,
        path: '$_directoryShellPath\\$_menuName\\command',
      );

      final value = key.getValueAsString('');
      key.close();

      if (value != null) {
        // 从命令行提取 exe 路径: "C:\path\to\exe.exe" --path "%V"
        final match = RegExp(r'^"([^"]+)"').firstMatch(value);
        if (match != null) {
          final path = match.group(1);
          print('DEBUG Registry: Registered exe path: $path');
          return path;
        }
      }
      print('DEBUG Registry: No registered exe path found');
      return null;
    } catch (e) {
      print('DEBUG Registry: Error getting registered path - $e');
      return null;
    }
  }

  /// 获取当前应用的 exe 路径
  static String getCurrentExePath() {
    return Platform.resolvedExecutable;
  }

  /// 检查注册的路径是否与当前路径匹配
  static Future<bool> isPathCorrect() async {
    final registeredPath = await getRegisteredExePath();
    final currentPath = getCurrentExePath();

    print('DEBUG Registry: Checking path correctness');
    print('DEBUG Registry: - Registered: $registeredPath');
    print('DEBUG Registry: - Current: $currentPath');

    if (registeredPath == null) {
      print('DEBUG Registry: Path check failed - no registered path');
      return false;
    }

    final isCorrect = registeredPath.toLowerCase() == currentPath.toLowerCase();
    print('DEBUG Registry: Path is ${isCorrect ? "CORRECT" : "WRONG"}');
    return isCorrect;
  }

  /// 注册右键菜单（需要管理员权限）
  static Future<RegistryResult> registerContextMenu() async {
    print('DEBUG Registry: registerContextMenu called');
    if (!Platform.isWindows) {
      return RegistryResult(
        success: false,
        message: '此功能仅支持 Windows 系统',
      );
    }

    final exePath = getCurrentExePath();
    print('DEBUG Registry: Will register with exe path: $exePath');

    try {
      // 注册文件夹右键菜单
      print('DEBUG Registry: Registering directory shell path...');
      await _registerMenuForPath(
        '$_directoryShellPath\\$_menuName',
        exePath,
      );

      // 注册文件夹空白处右键菜单
      print('DEBUG Registry: Registering directory background shell path...');
      await _registerMenuForPath(
        '$_directoryBackgroundShellPath\\$_menuName',
        exePath,
      );

      print('DEBUG Registry: Registration successful!');
      return RegistryResult(
        success: true,
        message: '右键菜单注册成功',
      );
    } catch (e) {
      // 检查是否是权限拒绝错误
      print('DEBUG Registry: Registration threw exception: $e');
      final errorStr = e.toString().toLowerCase();
      print('DEBUG Registry: Error string (lowercase): $errorStr');
      if (errorStr.contains('access') || errorStr.contains('denied') ||
          errorStr.contains('0x80070005') || errorStr.contains('permission')) {
        print('DEBUG Registry: Detected permission error, setting needsAdmin=true');
        return RegistryResult(
          success: false,
          message: '需要管理员权限才能注册右键菜单',
          needsAdmin: true,
        );
      }
      print('DEBUG Registry: Non-permission error');
      return RegistryResult(
        success: false,
        message: '注册失败: $e',
      );
    }
  }

  /// 更新右键菜单的 exe 路径
  static Future<RegistryResult> updateContextMenuPath() async {
    // 直接重新注册即可更新路径
    return registerContextMenu();
  }

  /// 移除右键菜单
  static Future<RegistryResult> unregisterContextMenu() async {
    if (!Platform.isWindows) {
      return RegistryResult(
        success: false,
        message: '此功能仅支持 Windows 系统',
      );
    }

    try {
      // 删除文件夹右键菜单
      _deleteMenuKey('$_directoryShellPath\\$_menuName');

      // 删除文件夹空白处右键菜单
      _deleteMenuKey('$_directoryBackgroundShellPath\\$_menuName');

      return RegistryResult(
        success: true,
        message: '右键菜单已移除',
      );
    } catch (e) {
      // 检查是否是权限拒绝错误
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('access') || errorStr.contains('denied') ||
          errorStr.contains('0x80070005') || errorStr.contains('permission')) {
        return RegistryResult(
          success: false,
          message: '需要管理员权限才能移除右键菜单',
          needsAdmin: true,
        );
      }
      return RegistryResult(
        success: false,
        message: '移除失败: $e',
      );
    }
  }

  /// 使用管理员权限重新启动应用（触发 UAC 对话框）
  /// 成功返回 true，用户取消或失败返回 false
  static Future<bool> restartAsAdmin({String? arguments}) async {
    if (!Platform.isWindows) return false;

    try {
      final shell32 = DynamicLibrary.open('shell32.dll');
      final shellExecute = shell32.lookupFunction<ShellExecuteNative, ShellExecuteDart>('ShellExecuteW');

      final exePath = getCurrentExePath();
      final lpOperation = 'runas'.toNativeUtf16();
      final lpFile = exePath.toNativeUtf16();
      final lpParameters = (arguments ?? '--register-context-menu').toNativeUtf16();
      final lpDirectory = ''.toNativeUtf16();

      // SW_SHOWNORMAL = 1
      final result = shellExecute(0, lpOperation, lpFile, lpParameters, lpDirectory, 1);

      // 释放内存
      calloc.free(lpOperation);
      calloc.free(lpFile);
      calloc.free(lpParameters);
      calloc.free(lpDirectory);

      // 返回值 > 32 表示成功
      return result > 32;
    } catch (e) {
      print('Error launching as admin: $e');
      return false;
    }
  }

  /// 检查并自动注册/更新右键菜单
  /// 返回操作结果，如果需要管理员权限会提示用户
  static Future<RegistryCheckResult> checkAndRegister() async {
    print('DEBUG Registry: ========== checkAndRegister START ==========');

    if (!Platform.isWindows) {
      print('DEBUG Registry: Not Windows platform, skipping');
      return RegistryCheckResult(
        status: RegistryStatus.notSupported,
        message: '此功能仅支持 Windows 系统',
      );
    }

    final isRegistered = await isContextMenuRegistered();
    print('DEBUG Registry: isRegistered = $isRegistered');

    if (!isRegistered) {
      // 未注册，尝试注册
      print('DEBUG Registry: Not registered, attempting to register...');
      final result = await registerContextMenu();
      print('DEBUG Registry: Register result - success: ${result.success}, needsAdmin: ${result.needsAdmin}, message: ${result.message}');
      if (result.success) {
        return RegistryCheckResult(
          status: RegistryStatus.registered,
          message: '已自动注册右键菜单',
        );
      } else if (result.needsAdmin) {
        print('DEBUG Registry: Returning needsAdmin status');
        return RegistryCheckResult(
          status: RegistryStatus.needsAdmin,
          message: '首次运行需要管理员权限来注册右键菜单',
        );
      } else {
        return RegistryCheckResult(
          status: RegistryStatus.failed,
          message: result.message,
        );
      }
    }

    // 已注册，检查路径是否正确
    print('DEBUG Registry: Already registered, checking if path is correct...');
    final isPathValid = await isPathCorrect();
    print('DEBUG Registry: isPathValid = $isPathValid');

    if (!isPathValid) {
      // 路径不正确，尝试更新
      print('DEBUG Registry: Path is WRONG, attempting to update...');
      final result = await updateContextMenuPath();
      print('DEBUG Registry: Update result - success: ${result.success}, needsAdmin: ${result.needsAdmin}, message: ${result.message}');
      if (result.success) {
        return RegistryCheckResult(
          status: RegistryStatus.updated,
          message: '已更新右键菜单路径',
        );
      } else if (result.needsAdmin) {
        print('DEBUG Registry: Returning needsAdmin status for path update');
        return RegistryCheckResult(
          status: RegistryStatus.needsAdmin,
          message: '需要管理员权限来更新右键菜单路径',
        );
      } else {
        return RegistryCheckResult(
          status: RegistryStatus.failed,
          message: result.message,
        );
      }
    }

    // 一切正常
    print('DEBUG Registry: Everything OK, already correctly registered');
    print('DEBUG Registry: ========== checkAndRegister END ==========');
    return RegistryCheckResult(
      status: RegistryStatus.alreadyRegistered,
      message: '右键菜单已正确注册',
    );
  }

  static Future<void> _registerMenuForPath(String registryPath, String exePath) async {
    // 创建主键
    final shellKey = Registry.openPath(
      RegistryHive.classesRoot,
      path: registryPath,
      desiredAccessRights: AccessRights.allAccess,
    );

    // 设置显示名称
    shellKey.createValue(const RegistryValue(
      '',
      RegistryValueType.string,
      _menuDisplayName,
    ));

    // 设置图标
    shellKey.createValue(RegistryValue(
      'Icon',
      RegistryValueType.string,
      '$exePath,0',
    ));

    shellKey.close();

    // 创建 command 子键
    final commandKey = Registry.openPath(
      RegistryHive.classesRoot,
      path: '$registryPath\\command',
      desiredAccessRights: AccessRights.allAccess,
    );

    // 设置命令
    commandKey.createValue(RegistryValue(
      '',
      RegistryValueType.string,
      '"$exePath" --path "%V"',
    ));

    commandKey.close();
  }

  static void _deleteMenuKey(String registryPath) {
    try {
      // 先删除 command 子键
      Registry.openPath(
        RegistryHive.classesRoot,
        path: registryPath,
        desiredAccessRights: AccessRights.allAccess,
      ).deleteKey('command');
    } catch (e) {
      // 忽略不存在的键
    }

    try {
      // 删除主键
      final parentPath = registryPath.substring(0, registryPath.lastIndexOf('\\'));
      final keyName = registryPath.substring(registryPath.lastIndexOf('\\') + 1);

      Registry.openPath(
        RegistryHive.classesRoot,
        path: parentPath,
        desiredAccessRights: AccessRights.allAccess,
      ).deleteKey(keyName);
    } catch (e) {
      // 忽略不存在的键
    }
  }
}

/// 注册表操作结果
class RegistryResult {
  final bool success;
  final String message;
  final bool needsAdmin;

  RegistryResult({
    required this.success,
    required this.message,
    this.needsAdmin = false,
  });
}

/// 注册表检查状态
enum RegistryStatus {
  notSupported,      // 不支持（非 Windows）
  registered,        // 刚刚注册成功
  updated,           // 刚刚更新成功
  alreadyRegistered, // 已经正确注册
  needsAdmin,        // 需要管理员权限
  failed,            // 失败
}

/// 注册表检查结果
class RegistryCheckResult {
  final RegistryStatus status;
  final String message;

  RegistryCheckResult({
    required this.status,
    required this.message,
  });
}
