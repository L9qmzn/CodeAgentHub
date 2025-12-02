/**
 * Windows 窗口隐藏预加载脚本
 *
 * 在任何其他模块加载之前运行，确保所有子进程窗口都被隐藏
 * 使用方法：node --require ./hide-windows-preload.js backend.js
 */

if (process.platform === 'win32') {
  console.log('[WindowsHide] Installing child_process patch...');

  // 创建标记文件，证明预加载脚本被执行了
  try {
    const fs = require('fs');
    const path = require('path');
    const markerFile = path.join(__dirname, '.windows-hide-loaded');
    fs.writeFileSync(markerFile, new Date().toISOString(), 'utf-8');
  } catch (e) {
    // 忽略错误
  }

  // 方法1：直接修改 child_process 模块（在任何人 require 之前）
  const childProcess = require('child_process');
  const originalSpawn = childProcess.spawn;

  childProcess.spawn = function(command, args, options) {
    const opts = options || {};
    // 强制隐藏所有窗口
    opts.windowsHide = true;

    console.log(`[WindowsHide] Intercepted spawn: ${command} ${args ? args.join(' ') : ''}`);
    return originalSpawn.call(this, command, args, opts);
  };

  console.log('[WindowsHide] child_process.spawn patched (direct)');

  // 方法2：拦截后续的 require 调用
  const Module = require('module');
  const originalRequire = Module.prototype.require;

  Module.prototype.require = function(id) {
    const module = originalRequire.apply(this, arguments);

    // 如果是 child_process 模块，确保 spawn 被 patch
    if (id === 'child_process' && !module._windowsHidePatched) {
      console.log('[WindowsHide] Re-patching child_process for new require()');

      const originalModuleSpawn = module.spawn;
      module.spawn = function(command, args, options) {
        const opts = options || {};
        opts.windowsHide = true;
        console.log(`[WindowsHide] Intercepted spawn (require): ${command}`);
        return originalModuleSpawn.call(this, command, args, opts);
      };

      module._windowsHidePatched = true;
    }

    return module;
  };

  console.log('[WindowsHide] Patch installed successfully (both methods)');
}
