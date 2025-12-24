import esbuild from 'esbuild';
import { copyFileSync, mkdirSync, existsSync, cpSync, rmSync, writeFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

async function buildRelease() {
  try {
    const releaseDir = join(__dirname, '../../release/backend');

    console.log('🧹 Cleaning release directory...');
    if (existsSync(releaseDir)) {
      rmSync(releaseDir, { recursive: true, force: true });
    }
    mkdirSync(releaseDir, { recursive: true });

    console.log('🚀 Bundling with esbuild...');
    await esbuild.build({
      entryPoints: ['src/index.ts'],
      bundle: true,
      platform: 'node',
      target: 'node18',
      format: 'cjs',
      outfile: join(releaseDir, 'backend.js'),
      external: [
        'better-sqlite3',
        '@anthropic-ai/claude-agent-sdk',
        '@openai/codex-sdk',
      ],
      minify: true,
      sourcemap: false,
      logLevel: 'info',
    });

    console.log('✅ Backend bundled!');

    // 复制 config.yaml
    console.log('📋 Copying config.yaml...');
    const configSource = join(__dirname, 'config.yaml');
    if (existsSync(configSource)) {
      copyFileSync(configSource, join(releaseDir, 'config.yaml'));
    }

    // 创建 package.json（只包含依赖声明，不包含编译好的模块）
    console.log('📦 Creating package.json...');
    const packageJson = {
      "name": "codeagenthub-backend",
      "version": "1.1.9",
      "private": true,
      "dependencies": {
        "better-sqlite3": "^11.7.0",
        "@anthropic-ai/claude-agent-sdk": "latest",
        "@openai/codex-sdk": "latest"
      },
      "engines": {
        "node": ">=18.0.0"
      }
    };
    writeFileSync(
      join(releaseDir, 'package.json'),
      JSON.stringify(packageJson, null, 2),
      'utf-8'
    );

    // 创建首次运行安装脚本
    console.log('📝 Creating install script...');
    const installScript = `@echo off
chcp 65001 >nul
echo ========================================
echo   首次运行 - 安装后端依赖
echo ========================================
echo.
echo 正在安装依赖（这可能需要几分钟）...
echo.

REM 检查 npm
where npm >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ❌ npm 未找到，请先安装 Node.js
    pause
    exit /b 1
)

echo Node.js 版本:
node --version
echo.

REM 安装依赖（会自动编译 better-sqlite3）
call npm install --production

if %ERRORLEVEL% neq 0 (
    echo.
    echo ❌ 安装失败
    pause
    exit /b 1
)

echo.
echo ✅ 依赖安装成功！
echo.
echo 您现在可以启动后端了
pause
`;
    writeFileSync(join(releaseDir, 'install_dependencies.bat'), installScript, 'utf-8');

    // 创建启动脚本（检查依赖是否安装）
    const startScript = `@echo off
chcp 65001 >nul

REM 检查是否已安装依赖
if not exist "node_modules\\better-sqlite3" (
    echo ========================================
    echo   检测到首次运行
    echo ========================================
    echo.
    echo 需要先安装依赖
    echo.
    choice /C YN /M "是否现在安装依赖"
    if errorlevel 2 (
        echo 已取消
        pause
        exit /b 1
    )
    call install_dependencies.bat
    if %ERRORLEVEL% neq 0 (
        pause
        exit /b 1
    )
)

echo Starting CodeAgentHub Backend...
node backend.js
`;
    writeFileSync(join(releaseDir, 'start-backend.bat'), startScript, 'utf-8');

    console.log('✅ Flexible build completed!');
    console.log('');
    console.log('📝 Note: Users will need to run install_dependencies.bat on first use');
    console.log('   This will compile better-sqlite3 for their Node.js version');

  } catch (error) {
    console.error('❌ Build failed:', error);
    process.exit(1);
  }
}

buildRelease();
