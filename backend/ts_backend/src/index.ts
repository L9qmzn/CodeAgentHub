import os from "os";

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

const portValue = CONFIG.port ?? 8207;
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
