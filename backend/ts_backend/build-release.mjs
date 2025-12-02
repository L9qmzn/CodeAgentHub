import esbuild from 'esbuild';
import { copyFileSync, mkdirSync, existsSync, cpSync, rmSync } from 'fs';
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

    // 复制 Windows 窗口隐藏预加载脚本
    console.log('🪟 Copying Windows hide preload script...');
    const preloadSource = join(__dirname, 'hide-windows-preload.js');
    if (existsSync(preloadSource)) {
      copyFileSync(preloadSource, join(releaseDir, 'hide-windows-preload.js'));
      console.log('  ✓ hide-windows-preload.js');
    }

    // 复制 better-sqlite3 及其依赖，以及 SDK 包
    console.log('📦 Copying native modules and SDK packages...');
    const modules = [
      'better-sqlite3',
      'bindings',
      'file-uri-to-path',
      '@anthropic-ai',
      '@openai'
    ];
    for (const mod of modules) {
      const modSource = join(__dirname, 'node_modules', mod);
      const modDest = join(releaseDir, 'node_modules', mod);
      if (existsSync(modSource)) {
        cpSync(modSource, modDest, { recursive: true });
        console.log(`  ✓ ${mod}`);
      }
    }

    // 创建启动脚本
    console.log('📝 Creating start script...');
    const startScript = `@echo off
REM CodeAgentHub Backend Launcher
echo Starting CodeAgentHub Backend...
node backend.js
`;
    const startScriptPath = join(releaseDir, 'start-backend.bat');
    const fs = await import('fs/promises');
    await fs.writeFile(startScriptPath, startScript, 'utf-8');


  } catch (error) {
    console.error('❌ Build failed:', error);
    process.exit(1);
  }
}

buildRelease();
