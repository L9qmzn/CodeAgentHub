@echo off
chcp 65001 >nul
title CodeAgent Hub Backend (Debug)

echo ========================================
echo   CodeAgent Hub Backend 调试模式
echo ========================================
echo.
echo 正在启动后端服务...
echo 窗口将保持打开以显示日志
echo.
echo ========================================
echo.

REM 切换到 backend 目录
cd /d "%~dp0backend"

REM 检查 backend.js 是否存在
if not exist "backend.js" (
    echo ❌ 错误: backend.js 不存在
    echo.
    pause
    exit /b 1
)

REM 检查 Node.js
where node >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ❌ 错误: Node.js 未找到
    echo 请确保已安装 Node.js 并重启电脑
    echo.
    pause
    exit /b 1
)

echo ✓ Node.js 版本:
node --version
echo.
echo ✓ 当前目录:
cd
echo.
echo ✓ 文件列表:
dir /b
echo.
echo ========================================
echo   后端日志输出：
echo ========================================
echo.

REM 检查预加载脚本（用于隐藏 SDK 子进程窗口）
if exist "hide-windows-preload.js" (
    echo ✓ 使用预加载脚本（SDK 子进程窗口将被隐藏）
    echo.
    node --require ./hide-windows-preload.js backend.js --port 8207
) else (
    echo ⚠ 预加载脚本不存在（SDK 子进程窗口可能显示）
    echo.
    node backend.js --port 8207
)

echo.
echo ========================================
echo   后端已退出
echo ========================================
echo.
pause
