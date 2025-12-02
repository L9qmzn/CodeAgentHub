@echo off
chcp 65001 >nul
title 重新编译原生模块

echo ========================================
echo   重新编译 better-sqlite3
echo ========================================
echo.
echo 当前目录: %~dp0
echo.

REM 切换到 backend 目录
cd /d "%~dp0backend"

REM 检查 npm
where npm >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ❌ npm 未找到
    echo 请确保已安装 Node.js 并重启电脑
    pause
    exit /b 1
)

echo Node.js 版本:
node --version
echo.

echo npm 版本:
npm --version
echo.

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
