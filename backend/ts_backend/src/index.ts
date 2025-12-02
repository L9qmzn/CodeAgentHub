import os from "os";

// Patch child_process to hide console windows on Windows
// This prevents SDK-spawned executables (codex.exe, claude.exe) from showing CMD windows
if (process.platform === "win32") {
  const cp = require("child_process");
  const originalSpawn = cp.spawn;
  cp.spawn = function (command: string, args?: ReadonlyArray<string>, options?: any) {
    const opts = options || {};
    // Always hide windows for child processes on Windows
    opts.windowsHide = true;
    return originalSpawn.call(this, command, args, opts);
  };
}

import { createApp } from "./app";
import { CONFIG } from "./config";

function detectLocalIp(): string {
  const interfaces = os.networkInterfaces();
  for (const iface of Object.values(interfaces)) {
    if (!iface) {
      continue;
    }
    for (const info of iface) {
      if (info.family === "IPv4" && !info.internal) {
        return info.address;
      }
    }
  }
  return "127.0.0.1";
}

const app = createApp();

// 检查命令行参数中是否指定了端口
const args = process.argv.slice(2);
let cmdLinePort: number | undefined;
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--port" && i + 1 < args.length) {
    cmdLinePort = parseInt(args[i + 1], 10);
    break;
  }
}

// 检查环境变量中是否指定了端口
const envPort = process.env.PORT ? parseInt(process.env.PORT, 10) : undefined;

// 优先级：命令行参数 > 环境变量 > 配置文件 > 默认值 8207
const portValue = cmdLinePort ?? envPort ?? CONFIG.port ?? 8207;
const parsedPort = typeof portValue === "string" ? parseInt(portValue, 10) : Number(portValue);
const port = Number.isFinite(parsedPort) ? parsedPort : 8207;
const host = "0.0.0.0";

const server = app.listen(port, host, () => {
  const localIp = detectLocalIp();
  const url = `http://${localIp}:${port}`;

  // eslint-disable-next-line no-console
  console.log("================ Claude 服务启动参数 ================");
  const configEntries = Object.entries(CONFIG).sort(([a], [b]) => a.localeCompare(b));
  for (const [key, value] of configEntries) {
    // eslint-disable-next-line no-console
    console.log(`${key}: ${typeof value === "object" ? JSON.stringify(value) : value}`);
  }
  // eslint-disable-next-line no-console
  console.log(`resolved_port: ${port}`);
  // eslint-disable-next-line no-console
  console.log(`local_url: ${url}`);
  // eslint-disable-next-line no-console
  console.log("====================================================");
});

process.on("SIGINT", () => {
  server.close(() => process.exit(0));
});

process.on("SIGTERM", () => {
  server.close(() => process.exit(0));
});
