@echo off
chcp 65001 >nul
title 重新编译原生模块

echo ========================================
echo   重新编译 better-sqlite3
echo ========================================
echo.
echo 当前目录: %~dp0
echo.
REM 检查 backend 目录是否存在
if not exist "%~dp0backend" (
    echo ❌ backend 目录不存在
    echo.
    echo 当前位置: %~dp0
    echo 期望位置: %~dp0backend
    echo.
    echo 这个脚本需要在应用根目录运行
    echo 请确保 backend 文件夹存在
    echo.
    pause
    exit /b 1
)
REM 切换到 backend 目录
cd /d "%~dp0backend"
if %ERRORLEVEL% neq 0 (
    echo ❌ 无法进入 backend 目录
    pause
    exit /b 1
)
REM 检查 node_modules 是否存在
if not exist "node_modules" (
    echo ❌ node_modules 目录不存在
    echo.
    echo 这是正常的，因为打包后的应用使用预编译的模块
    echo 如果遇到 better-sqlite3 错误，请：
    echo 1. 访问 https://nodejs.org/ 确保 Node.js 版本正确（推荐 v18 或 v20）
    echo 2. 运行 fix_all.bat 自动修复
    echo.
    pause
    exit /b 0
)
REM 检查 better-sqlite3 是否存在
if not exist "node_modules\better-sqlite3" (
    echo ⚠️  better-sqlite3 模块不存在
    echo.
    echo 尝试安装...
    call npm install better-sqlite3
    if %ERRORLEVEL% neq 0 (
        echo ❌ 安装失败
        pause
        exit /b 1
    )
)
echo 正在重新编译 better-sqlite3...
echo （这可能需要 1-2 分钟）
echo.

REM 方法1：使用 npm rebuild
call npm rebuild better-sqlite3

if %ERRORLEVEL% neq 0 (
    echo.
    echo ⚠️  方法1失败，尝试方法2...
    echo.

    REM 方法2：进入模块目录重新安装
    cd node_modules\better-sqlite3
    call npm install --ignore-scripts=false
    cd ..\..

    if %ERRORLEVEL% neq 0 (
        echo.
        echo ❌ 重新编译失败
        echo.
        echo 请确保已安装 Visual Studio Build Tools
        echo 或运行: npm install -g windows-build-tools
        pause
        exit /b 1
    )
)

echo.
echo ✅ 重新编译成功！
echo.
echo 现在可以启动后端了
echo.
pause
