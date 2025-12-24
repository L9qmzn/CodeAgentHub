import fs from "fs";
import os from "os";
import path from "path";
import YAML from "yaml";

export type UserCredentials = Record<string, string>;

export interface AppConfig {
  claude_dir: string;
  sessions_db: string;
  port?: number | string;
  users: UserCredentials;
  codex_dir?: string;
  codex_api_key?: string;
  codex_cli_path?: string;
  verbose_logs?: boolean;
}

// 动态获取应用根目录（backend.js 所在目录）
// 在打包后，__dirname 会被 esbuild 替换为构建时的路径
// 因此我们需要在运行时动态获取 backend.js 所在目录
function getBackendDir(): string {
  // 尝试多种方法获取运行时路径
  try {
    // 方法1: 使用 require.main.filename (CommonJS 环境)
    if (typeof require !== 'undefined' && require.main) {
      const mainPath = require.main.filename;
      if (mainPath) {
        return path.dirname(path.resolve(mainPath));
      }
    }
  } catch (e) {
    // ignore
  }

  try {
    // 方法2: 使用 import.meta.url (ESM 环境)
    if (typeof import.meta !== 'undefined' && import.meta.url) {
      const url = new URL(import.meta.url);
      let dirPath = path.dirname(url.pathname);
      // 修复 Windows 路径问题（去除开头的 /C:/ 或 /D:/ 等）
      if (process.platform === 'win32' && dirPath.match(/^\/[A-Z]:/)) {
        dirPath = dirPath.substring(1);
      }
      return dirPath;
    }
  } catch (e) {
    // ignore
  }

  try {
    // 方法3: 使用 process.cwd() 作为回退
    const cwd = process.cwd();
    // 如果当前目录包含 backend.js，则返回当前目录
    if (require('fs').existsSync(path.join(cwd, 'backend.js'))) {
      return cwd;
    }
  } catch (e) {
    // ignore
  }

  // 最后的回退：使用 __dirname（可能已被替换）
  return __dirname;
}

const APP_ROOT = getBackendDir();
const PROJECT_ROOT = APP_ROOT;
const CONFIG_PATH = path.join(APP_ROOT, "config.yaml");
const DEFAULT_USER_CREDENTIALS: UserCredentials = { admin: "642531" };

function iterCandidateClaudeDirs(): string[] {
  const home = os.homedir();
  const candidates: string[] = [];

  const envValues = [process.env.CLAUDE_DIR, process.env.CLAUDE_HOME];
  for (const value of envValues) {
    if (value) {
      candidates.push(path.resolve(value));
    }
  }

  candidates.push(path.join(home, ".claude"));

  const platform = process.platform;
  if (platform === "darwin") {
    candidates.push(path.join(home, "Library", "Application Support", "Claude"));
  } else if (platform === "win32") {
    const appdata = process.env.APPDATA;
    if (appdata) {
      candidates.push(path.join(appdata, "Claude"));
    }
    const localappdata = process.env.LOCALAPPDATA;
    if (localappdata) {
      candidates.push(path.join(localappdata, "Claude"));
    }
    candidates.push(path.join(home, "AppData", "Roaming", "Claude"));
    candidates.push(path.join(home, "AppData", "Local", "Claude"));
  } else {
    const xdgDataHome = process.env.XDG_DATA_HOME;
    if (xdgDataHome) {
      candidates.push(path.join(xdgDataHome, "claude"));
    }
  }

  return candidates;
}

function detectClaudeDir(): string {
  const fallback = path.join(os.homedir(), ".claude");
  const seen = new Set<string>();

  for (const candidate of iterCandidateClaudeDirs()) {
    const resolved = path.resolve(candidate);
    if (seen.has(resolved)) {
      continue;
    }
    seen.add(resolved);

    if (fs.existsSync(resolved) || fs.existsSync(path.join(resolved, "projects"))) {
      return resolved;
    }
  }

  return fallback;
}

function detectCodexSessionsDir(): string {
  const envOverride = process.env.CODEX_SESSIONS_DIR;
  if (envOverride) {
    return path.resolve(envOverride);
  }
  const fallback = path.join(os.homedir(), ".codex", "sessions");
  return fallback;
}

export function loadAppConfig(): AppConfig {
  const defaults: AppConfig = {
    claude_dir: "",
    sessions_db: path.join(PROJECT_ROOT, "sessions.db"),
    users: { ...DEFAULT_USER_CREDENTIALS },
    codex_dir: "",
    codex_api_key: "",
    codex_cli_path: "",
    verbose_logs: true,
  };

  let loaded: unknown = {};
  let configExists = false;

  try {
    if (fs.existsSync(CONFIG_PATH)) {
      const content = fs.readFileSync(CONFIG_PATH, "utf-8");
      loaded = YAML.parse(content) ?? {};
      configExists = true;
    }
  } catch (error) {
    configExists = false;
  }

  // 如果配置文件不存在，自动生成默认配置文件
  if (!configExists) {
    console.log(`配置文件不存在，正在生成默认配置: ${CONFIG_PATH}`);
    try {
      const defaultConfig: AppConfig = { ...defaults };
      defaultConfig.claude_dir = detectClaudeDir();
      defaultConfig.codex_dir = detectCodexSessionsDir();

      const yamlContent = YAML.stringify({
        claude_dir: defaultConfig.claude_dir || undefined,
        sessions_db: defaultConfig.sessions_db,
        port: defaultConfig.port || undefined,
        users: defaultConfig.users,
        codex_dir: defaultConfig.codex_dir || undefined,
        codex_api_key: defaultConfig.codex_api_key || undefined,
        codex_cli_path: defaultConfig.codex_cli_path || undefined,
        verbose_logs: defaultConfig.verbose_logs,
      });

      fs.writeFileSync(CONFIG_PATH, yamlContent, "utf-8");
      console.log(`✓ 默认配置文件已创建: ${CONFIG_PATH}`);
      console.log(`  默认用户名: admin`);
      console.log(`  默认密码: 642531`);
      loaded = defaultConfig;
    } catch (error) {
      console.error(`创建配置文件失败:`, error);
      console.log(`使用内存中的默认配置`);
    }
  }

  const config: AppConfig = { ...defaults };
  if (typeof loaded === "object" && loaded !== null) {
    for (const [key, value] of Object.entries(loaded)) {
      if (key === "users" && value && typeof value === "object") {
        const sanitized: UserCredentials = {};
        for (const [username, password] of Object.entries(value as Record<string, unknown>)) {
          if (typeof username === "string") {
            const normalized = username.trim();
            if (normalized) {
              // Accept both string and number passwords (YAML can parse numbers without quotes as numbers)
              if (typeof password === "string") {
                sanitized[normalized] = password;
              } else if (typeof password === "number") {
                // Convert number to string (e.g., 123 -> "123")
                sanitized[normalized] = String(password);
              }
            }
          }
        }
        if (Object.keys(sanitized).length > 0) {
          config.users = sanitized;
        }
        continue;
      }

      if (typeof key === "string" && key === "verbose_logs") {
        if (typeof value === "boolean") {
          config.verbose_logs = value;
        } else if (typeof value === "string") {
          const normalized = value.trim().toLowerCase();
          if (["true", "1", "yes", "on"].includes(normalized)) {
            config.verbose_logs = true;
          } else if (["false", "0", "no", "off"].includes(normalized)) {
            config.verbose_logs = false;
          }
        } else if (typeof value === "number") {
          config.verbose_logs = value !== 0;
        }
        continue;
      }

      if (typeof key === "string" && typeof value === "string" && value.trim()) {
        const trimmed = value.trim();
        if (key === "claude_dir") {
          config.claude_dir = trimmed;
        } else if (key === "sessions_db") {
          config.sessions_db = trimmed;
        } else if (key === "port") {
          config.port = trimmed;
        } else if (key === "codex_dir") {
          config.codex_dir = trimmed;
        } else if (key === "codex_api_key") {
          config.codex_api_key = trimmed;
        } else if (key === "codex_cli_path") {
          config.codex_cli_path = trimmed;
        }
      } else if (typeof key === "string" && typeof value === "number" && key === "port") {
        config.port = value;
      }
    }
  }

  if (!config.claude_dir) {
    config.claude_dir = detectClaudeDir();
  }

  if (!config.codex_dir) {
    config.codex_dir = detectCodexSessionsDir();
  }

  return config;
}

export const CONFIG = loadAppConfig();
export const CLAUDE_ROOT = path.resolve(CONFIG.claude_dir);
export const CLAUDE_PROJECTS_DIR = path.join(CLAUDE_ROOT, "projects");
export const CODEX_SESSIONS_DIR = path.resolve(CONFIG.codex_dir || detectCodexSessionsDir());
export const ENABLE_VERBOSE_LOGS = CONFIG.verbose_logs !== false;

const sessionsDb = CONFIG.sessions_db;
const dbPath = path.isAbsolute(sessionsDb)
  ? sessionsDb
  : path.resolve(path.dirname(CONFIG_PATH), sessionsDb);

export const DB_PATH = dbPath;
export const USER_CREDENTIALS = CONFIG.users;
export const CODEX_API_KEY = CONFIG.codex_api_key || process.env.CODEX_API_KEY || "";
export const CODEX_CLI_PATH = CONFIG.codex_cli_path || process.env.CODEX_CLI_PATH || "";

/**
 * Update user credentials in config.yaml and reload in memory
 */
export function updateUserCredentials(
  oldUsername: string,
  newUsername: string,
  newPassword: string,
): void {
  // Read current config
  let currentConfig: AppConfig = CONFIG;
  try {
    const content = fs.readFileSync(CONFIG_PATH, "utf-8");
    const parsed = YAML.parse(content);
    if (parsed && typeof parsed === "object") {
      currentConfig = { ...CONFIG, ...parsed };
    }
  } catch (error) {
    // If can't read, use current CONFIG
  }

  // Update users
  const updatedUsers: UserCredentials = { ...currentConfig.users };

  // Remove old username
  delete updatedUsers[oldUsername];

  // Add new username with new password
  updatedUsers[newUsername] = newPassword;

  // Update config object
  currentConfig.users = updatedUsers;

  // Write back to file
  const yamlContent = YAML.stringify({
    claude_dir: currentConfig.claude_dir || undefined,
    sessions_db: currentConfig.sessions_db,
    port: currentConfig.port,
    users: updatedUsers,
    codex_dir: currentConfig.codex_dir || undefined,
    codex_api_key: currentConfig.codex_api_key || undefined,
    codex_cli_path: currentConfig.codex_cli_path || undefined,
    verbose_logs: currentConfig.verbose_logs,
  });

  fs.writeFileSync(CONFIG_PATH, yamlContent, "utf-8");

  // Update in-memory credentials - must clear old keys first
  // Delete old username if it's different from new username
  if (oldUsername !== newUsername) {
    delete USER_CREDENTIALS[oldUsername];
  }

  // Set new username and password
  USER_CREDENTIALS[newUsername] = newPassword;
}
