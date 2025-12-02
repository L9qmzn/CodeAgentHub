import crypto from "crypto";
import express, { NextFunction, Request, Response } from "express";
import fs from "fs";
import path from "path";
import {
  query,
  type Options as ClaudeAgentOptions,
  type SDKMessage,
  type SDKUserMessage,
} from "@anthropic-ai/claude-agent-sdk";
import type { ThreadOptions } from "@openai/codex-sdk";

import {
  CLAUDE_ROOT,
  CODEX_API_KEY,
  CODEX_CLI_PATH,
  CODEX_SESSIONS_DIR,
  ENABLE_VERBOSE_LOGS,
  USER_CREDENTIALS,
  updateUserCredentials,
} from "./config";
import { initDb } from "./database";
import {
  bootstrapSessionsFromFiles,
  fetchSession,
  listSessionSummaries,
  listSessionSummariesAsync,
  persistSessionMetadata,
} from "./sessionStore";
import {
  bootstrapCodexSessionsFromFiles,
  fetchCodexSession,
  listCodexSessionSummaries,
  persistCodexSessionMetadata,
} from "./codexSessionStore";
import { AnyRecord, formatSse, logSdkMessage, serializeSdkMessage } from "./streaming";
import {
  ChangePasswordRequest,
  ChangeUsernameRequest,
  ChatRequest,
  CodexChatRequest,
  CodexUserSettings,
  CodexUserSettingsRequest,
  PermissionMode,
  Session,
  StopChatRequest,
  SystemPrompt,
  UserSettings,
  defaultCodexUserSettings,
  defaultSystemPrompt,
} from "./models";
import { fetchUserSettings, upsertUserSettings } from "./userSettingsStore";
import {
  fetchCodexUserSettings,
  upsertCodexUserSettings,
} from "./codexUserSettingsStore";
import { MessageStreamController } from "./messageQueue";

declare global {
  namespace Express {
    interface Request {
      userId?: string;
    }
  }
}

const VALID_PERMISSION_MODES: PermissionMode[] = [
  "default",
  "plan",
  "acceptEdits",
  "bypassPermissions",
];

const activeClaudeRuns = new Map<string, AbortController>();

type ActiveSession = {
  streamController: MessageStreamController;
  runId: string;
  abortController: AbortController;
  cwd: string;
  sessionId: string | null;
  connections: Set<Response>;
  permissionMode: PermissionMode;
  systemPrompt: SystemPrompt;
};

const activeSessions = new Map<string, ActiveSession>();

type CodexModule = typeof import("@openai/codex-sdk");
type CodexClientInstance = InstanceType<CodexModule["Codex"]>;
let codexClientPromise: Promise<CodexClientInstance> | null = null;

const dynamicImport = new Function("specifier", "return import(specifier);") as (
  specifier: string,
) => Promise<CodexModule>;

function generateRunId(): string {
  if (typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }
  return crypto.randomBytes(16).toString("hex");
}

async function getCodexClient(): Promise<CodexClientInstance> {
  if (!codexClientPromise) {
    codexClientPromise = dynamicImport("@openai/codex-sdk").then(({ Codex }) => {
      return new Codex({
        apiKey: CODEX_API_KEY || undefined,
        codexPathOverride: CODEX_CLI_PATH || undefined,
      });
    });
  }
  return codexClientPromise;
}

type SystemInitMessage = Extract<SDKMessage, { type: "system"; subtype: "init" }>;
type AssistantSdkMessage = Extract<SDKMessage, { type: "assistant" }>;
type ResultSdkMessage = Extract<SDKMessage, { type: "result" }>;

function safeCompare(a: string, b: string): boolean {
  const bufferA = Buffer.from(a);
  const bufferB = Buffer.from(b);
  if (bufferA.length !== bufferB.length) {
    return false;
  }
  return crypto.timingSafeEqual(bufferA, bufferB);
}

function decodeBasicAuth(header?: string): { username: string; password: string } | null {
  if (!header || !header.startsWith("Basic ")) {
    return null;
  }
  try {
    const decoded = Buffer.from(header.slice("Basic ".length), "base64").toString("utf-8");
    const index = decoded.indexOf(":");
    if (index === -1) {
      return null;
    }
    return {
      username: decoded.slice(0, index),
      password: decoded.slice(index + 1),
    };
  } catch {
    return null;
  }
}

function basicAuthMiddleware(req: Request, res: Response, next: NextFunction): void {
  const credentials = decodeBasicAuth(req.headers.authorization);
  if (!credentials) {
    res.setHeader("WWW-Authenticate", "Basic");
    res.status(401).json({ detail: "Unauthorized" });
    return;
  }

  const storedPassword = USER_CREDENTIALS[credentials.username];
  if (!storedPassword || !safeCompare(credentials.password, storedPassword)) {
    res.setHeader("WWW-Authenticate", "Basic");
    res.status(401).json({ detail: "Unauthorized" });
    return;
  }

  req.userId = credentials.username;
  next();
}

function ensureSameUser(req: Request, res: Response, userId: string): boolean {
  if (req.userId !== userId) {
    res.status(403).json({ detail: "Forbidden" });
    return false;
  }
  return true;
}

function normalizePermissionMode(value?: string): PermissionMode {
  if (!value) {
    return "default";
  }
  if (VALID_PERMISSION_MODES.includes(value as PermissionMode)) {
    return value as PermissionMode;
  }
  return "default";
}

function deriveSessionTitle(message: string): string {
  const fallback = "新会话";
  const trimmed = message.trim() || fallback;
  if (trimmed.length <= 30) {
    return trimmed;
  }
  return `${trimmed.slice(0, 30)}...`;
}

function isTextBlock(block: unknown): block is { type: string; text: string } {
  return Boolean(
    block &&
      typeof block === "object" &&
      (block as AnyRecord).type === "text" &&
      typeof (block as AnyRecord).text === "string",
  );
}

function buildCodexThreadOptions(body: CodexChatRequest, cwd: string): ThreadOptions {
  return {
    workingDirectory: cwd,
    approvalPolicy: body.approval_policy,
    sandboxMode: body.sandbox_mode,
    skipGitRepoCheck: body.skip_git_repo_check,
    model: body.model,
    modelReasoningEffort: body.model_reasoning_effort,
    networkAccessEnabled: body.network_access_enabled,
    webSearchEnabled: body.web_search_enabled,
  };
}

function buildClaudeOptionsFromRequest(params: {
  body: ChatRequest;
  cwd: string;
  permissionMode: PermissionMode;
  systemPrompt: SystemPrompt;
  abortController: AbortController;
}): ClaudeAgentOptions {
  const { body, cwd, permissionMode, systemPrompt, abortController } = params;
  const options: ClaudeAgentOptions = {
    resume: body.session_id ?? undefined,
    cwd,
    includePartialMessages: body.include_partial_messages ?? true,
    settingSources: body.setting_sources ?? ["user"],
    permissionMode,
    systemPrompt: (systemPrompt ?? undefined) as any,
    abortController,
  };

  if (body.additional_directories !== undefined) {
    options.additionalDirectories = body.additional_directories;
  }
  if (body.agents !== undefined) {
    options.agents = body.agents;
  }
  if (body.allowed_tools !== undefined) {
    options.allowedTools = body.allowed_tools;
  }
  if (body.disallowed_tools !== undefined) {
    options.disallowedTools = body.disallowed_tools;
  }
  if (body.env !== undefined) {
    options.env = body.env;
  }
  if (body.executable !== undefined) {
    options.executable = body.executable;
  }
  if (body.executable_args !== undefined) {
    options.executableArgs = body.executable_args;
  }
  if (body.extra_args !== undefined) {
    options.extraArgs = body.extra_args;
  }
  if (body.fallback_model !== undefined) {
    options.fallbackModel = body.fallback_model;
  }
  if (body.fork_session !== undefined) {
    options.forkSession = body.fork_session;
  }
  if (body.max_thinking_tokens !== undefined) {
    options.maxThinkingTokens = body.max_thinking_tokens;
  }
  if (body.max_turns !== undefined) {
    options.maxTurns = body.max_turns;
  }
  if (body.max_budget_usd !== undefined) {
    options.maxBudgetUsd = body.max_budget_usd;
  }
  if (body.mcp_servers !== undefined) {
    options.mcpServers = body.mcp_servers;
  }
  if (body.model !== undefined) {
    options.model = body.model;
  }
  if (body.path_to_claude_code_executable !== undefined) {
    options.pathToClaudeCodeExecutable = body.path_to_claude_code_executable;
  }
  if (body.allow_dangerously_skip_permissions !== undefined) {
    options.allowDangerouslySkipPermissions = body.allow_dangerously_skip_permissions;
  }
  if (body.permission_prompt_tool_name !== undefined) {
    options.permissionPromptToolName = body.permission_prompt_tool_name;
  }
  if (body.plugins !== undefined) {
    options.plugins = body.plugins;
  }
  if (body.resume_session_at !== undefined) {
    options.resumeSessionAt = body.resume_session_at;
  }
  if (body.strict_mcp_config !== undefined) {
    options.strictMcpConfig = body.strict_mcp_config;
  }
  if (body.continue !== undefined) {
    options.continue = body.continue;
  }

  return options;
}

function emitCodexAgentChunk(
  itemId: string,
  text: string,
  assistantChunks: string[],
  writeEvent: (event: string, payload: AnyRecord) => void,
  sessionId: string | null,
  progressMap: Map<string, string>,
): void {
  const previous = progressMap.get(itemId) ?? "";
  const chunk = text.slice(previous.length);
  if (chunk) {
    assistantChunks.push(chunk);
    writeEvent("token", {
      session_id: sessionId,
      text: chunk,
    });
  }
  progressMap.set(itemId, text);
}

function extractSessionIdFromPayload(payload: unknown): string | null {
  if (!payload || typeof payload !== "object") {
    return null;
  }

  const stack: AnyRecord[] = [payload as AnyRecord];
  const seen = new Set<AnyRecord>();

  while (stack.length > 0) {
    const current = stack.pop();
    if (!current || seen.has(current)) {
      continue;
    }
    seen.add(current);

    const value =
      (typeof current.session_id === "string" && current.session_id) ||
      (typeof current.sessionId === "string" && current.sessionId);
    if (value) {
      return value;
    }

    for (const child of Object.values(current)) {
      if (child && typeof child === "object") {
        if (Array.isArray(child)) {
          for (const item of child) {
            if (item && typeof item === "object") {
              stack.push(item as AnyRecord);
            }
          }
        } else {
          stack.push(child as AnyRecord);
        }
      }
    }
  }

  return null;
}

function isSystemInitMessage(message: SDKMessage): message is SystemInitMessage {
  return message.type === "system" && (message as { subtype?: string }).subtype === "init";
}

function isAssistantMessage(message: SDKMessage): message is AssistantSdkMessage {
  return message.type === "assistant";
}

function isResultMessage(message: SDKMessage): message is ResultSdkMessage {
  return message.type === "result";
}

function ensureDirectory(pathValue: string): void {
  const stats = fs.statSync(pathValue, { throwIfNoEntry: false });
  if (!stats || !stats.isDirectory()) {
    throw new Error(`cwd does not exist or is not a directory: ${pathValue}`);
  }
}

export function createApp(): express.Express {
  initDb();
  try {
    bootstrapSessionsFromFiles();
  } catch (error) {
    // eslint-disable-next-line no-console
    console.warn("Failed to bootstrap sessions:", error);
  }
  try {
    bootstrapCodexSessionsFromFiles();
  } catch (error) {
    // eslint-disable-next-line no-console
    console.warn("Failed to bootstrap Codex sessions:", error);
  }

  const app = express();
  app.use(express.json({ limit: "5mb" }));
  app.use((req, res, next) => {
    if (!ENABLE_VERBOSE_LOGS) {
      next();
      return;
    }
    const start = Date.now();
    const { method } = req;
    const url = req.originalUrl || req.url;
    const clientIp = req.ip || req.socket.remoteAddress || "unknown";
    res.on("finish", () => {
      const duration = Date.now() - start;
      const status = res.statusCode;
      const length = res.getHeader("content-length");
      // eslint-disable-next-line no-console
      console.log(
        `[HTTP] ${method ?? "UNKNOWN"} ${url} - ${status} (${duration}ms) from ${clientIp}${
          length ? ` len=${length}` : ""
        }`,
      );
    });
    next();
  });

  // 健康检查端点 - 不需要认证，用于检测后端是否在运行
  app.get("/health", (_req, res) => {
    res.status(200).json({ status: "ok", timestamp: new Date().toISOString() });
  });

  app.use(basicAuthMiddleware);

  app.get("/sessions", async (_req, res) => {
    try {
      const summaries = await listSessionSummariesAsync();
      res.json(summaries);
    } catch (error) {
      res.status(500).json({ detail: error instanceof Error ? error.message : String(error) });
    }
  });

  app.get("/sessions/:sessionId", (req, res) => {
    const session = fetchSession(req.params.sessionId, true);
    if (!session) {
      res.status(404).json({ detail: "Session not found" });
      return;
    }
    res.json(session);
  });

  app.post("/sessions/load", (req, res) => {
    const body = req.body as { claude_dir?: string } | undefined;
    try {
      const stats = bootstrapSessionsFromFiles(body?.claude_dir);
      const resolvedRoot = body?.claude_dir ? path.resolve(body.claude_dir) : CLAUDE_ROOT;
      res.json({
        claude_dir: resolvedRoot,
        sessions_loaded: stats.sessions,
        agent_runs_loaded: stats.agent_runs,
      });
    } catch (error) {
      res.status(400).json({ detail: error instanceof Error ? error.message : String(error) });
    }
  });

  app.get("/users/:userId/settings", (req, res) => {
    const { userId } = req.params;
    if (!ensureSameUser(req, res, userId)) {
      return;
    }
    const settings = fetchUserSettings(userId);
    if (!settings) {
      const defaults: UserSettings = {
        user_id: userId,
        permission_mode: "default",
        system_prompt: defaultSystemPrompt(),
      };
      res.json(defaults);
      return;
    }
    res.json(settings);
  });

  app.put("/users/:userId/settings", (req, res) => {
    const { userId } = req.params;
    if (!ensureSameUser(req, res, userId)) {
      return;
    }
    const body = req.body as UserSettings | undefined;
    const permissionMode = normalizePermissionMode(body?.permission_mode);
    const hasSystemPromptField =
      !!body && Object.prototype.hasOwnProperty.call(body, "system_prompt");
    const systemPrompt = hasSystemPromptField ? body?.system_prompt ?? null : defaultSystemPrompt();

    const settings = upsertUserSettings({
      user_id: userId,
      permission_mode: permissionMode,
      system_prompt: systemPrompt,
    });

    res.json(settings);
  });

  app.post("/users/:userId/change-password", (req, res) => {
    const { userId } = req.params;
    if (!ensureSameUser(req, res, userId)) {
      return;
    }

    const body = req.body as ChangePasswordRequest | undefined;
    const { old_password, new_password } = body ?? {};

    if (!old_password || !new_password) {
      res.status(400).json({ detail: "old_password and new_password are required" });
      return;
    }

    const storedPassword = USER_CREDENTIALS[userId];
    if (!storedPassword) {
      res.status(404).json({ detail: "User not found" });
      return;
    }

    if (!safeCompare(old_password, storedPassword)) {
      res.status(401).json({ detail: "Invalid old password" });
      return;
    }

    try {
      updateUserCredentials(userId, userId, new_password);
      res.json({
        success: true,
        message: "Password changed successfully",
        user_id: userId,
      });
    } catch (error) {
      res.status(500).json({
        detail: `Failed to update config file: ${error instanceof Error ? error.message : String(error)}`,
      });
    }
  });

  app.post("/users/:userId/change-username", (req, res) => {
    const { userId } = req.params;
    if (!ensureSameUser(req, res, userId)) {
      return;
    }

    const body = req.body as ChangeUsernameRequest | undefined;
    const newUsername = body?.new_username?.trim();

    if (!newUsername) {
      res.status(400).json({ detail: "new_username is required" });
      return;
    }

    if (newUsername === userId) {
      res.status(400).json({ detail: "New username must be different from current username" });
      return;
    }

    const storedPassword = USER_CREDENTIALS[userId];
    if (!storedPassword) {
      res.status(404).json({ detail: "User not found" });
      return;
    }

    if (USER_CREDENTIALS[newUsername]) {
      res.status(409).json({ detail: "Username already exists" });
      return;
    }

    try {
      updateUserCredentials(userId, newUsername, storedPassword);
      res.json({
        success: true,
        message: "Username changed successfully",
        old_username: userId,
        new_username: newUsername,
      });
    } catch (error) {
      res.status(500).json({
        detail: `Failed to update config file: ${error instanceof Error ? error.message : String(error)}`,
      });
    }
  });

  app.get("/codex/sessions", (_req, res) => {
    res.json(listCodexSessionSummaries());
  });

  app.get("/codex/sessions/:sessionId", (req, res) => {
    const session = fetchCodexSession(req.params.sessionId, true);
    if (!session) {
      res.status(404).json({ detail: "Session not found" });
      return;
    }
    res.json(session);
  });

  app.post("/codex/sessions/load", (req, res) => {
    const body = req.body as { codex_dir?: string } | undefined;
    try {
      const stats = bootstrapCodexSessionsFromFiles(body?.codex_dir);
      const resolvedRoot = body?.codex_dir ? path.resolve(body.codex_dir) : CODEX_SESSIONS_DIR;
      res.json({
        codex_dir: resolvedRoot,
        sessions_loaded: stats.sessions,
      });
    } catch (error) {
      res.status(400).json({ detail: error instanceof Error ? error.message : String(error) });
    }
  });

  app.get("/codex/users/:userId/settings", (req, res) => {
    const { userId } = req.params;
    if (!ensureSameUser(req, res, userId)) {
      return;
    }
    const settings = fetchCodexUserSettings(userId);
    if (!settings) {
      res.json(defaultCodexUserSettings(userId));
      return;
    }
    res.json(settings);
  });

  app.put("/codex/users/:userId/settings", (req, res) => {
    const { userId } = req.params;
    if (!ensureSameUser(req, res, userId)) {
      return;
    }
    const body = (req.body ?? {}) as CodexUserSettingsRequest;
    const sanitized: CodexUserSettingsRequest = {
      approval_policy: body.approval_policy,
      sandbox_mode: body.sandbox_mode,
      model: body.model,
      model_reasoning_effort: body.model_reasoning_effort,
      network_access_enabled: body.network_access_enabled,
      web_search_enabled: body.web_search_enabled,
      skip_git_repo_check: body.skip_git_repo_check,
    };

    const settings: CodexUserSettings = upsertCodexUserSettings({
      user_id: userId,
      settings: sanitized,
    });

    res.json(settings);
  });

  app.post("/chat", (req, res) => {
    const body = req.body as ChatRequest | undefined;
    if (!body || !body.message) {
      res.status(400).json({ detail: "message is required" });
      return;
    }

    // Validate message format
    if (typeof body.message === "string") {
      if (!body.message.trim()) {
        res.status(400).json({ detail: "message cannot be empty" });
        return;
      }
    } else if (Array.isArray(body.message)) {
      if (body.message.length === 0) {
        res.status(400).json({ detail: "message cannot be empty" });
        return;
      }
    } else {
      res.status(400).json({ detail: "message must be a string or array" });
      return;
    }

    const permissionMode = normalizePermissionMode(body.permission_mode);
    const hasSystemPrompt =
      body && Object.prototype.hasOwnProperty.call(body, "system_prompt");
    const systemPrompt = hasSystemPrompt ? body.system_prompt ?? null : defaultSystemPrompt();
    const now = new Date();

    // Extract text for session title
    const userMessageText = typeof body.message === "string"
      ? body.message
      : body.message.find(block => block.type === "text")?.text || "New session with image";

    // Determine session key for tracking active sessions
    const sessionKey = body.session_id || `temp_${generateRunId()}`;

    // Check if there's already an active session for this session_id
    const activeSession = body.session_id ? activeSessions.get(body.session_id) : null;

    if (activeSession) {
      // Session is already running - inject message into the active stream!
      // eslint-disable-next-line no-console
      console.log(`[Claude] Session ${body.session_id} is active, injecting new message into stream`);

      res.setHeader("Content-Type", "text/event-stream");
      res.setHeader("Cache-Control", "no-cache");
      res.setHeader("Connection", "keep-alive");
      res.setHeader("X-Claude-Run-Id", activeSession.runId);
      if (typeof res.flushHeaders === "function") {
        res.flushHeaders();
      }

      // Add this connection to the session's connections
      activeSession.connections.add(res);

      // Clean up when this connection closes
      const cleanup = () => {
        activeSession.connections.delete(res);
      };
      req.on("aborted", cleanup);
      res.on("close", cleanup);

      // Push the new message into the stream
      const userMessage: SDKUserMessage = {
        type: "user",
        message: {
          role: "user",
          content: body.message as any,
        },
        parent_tool_use_id: null,
        session_id: activeSession.sessionId || "",
      };

      try {
        activeSession.streamController.push(userMessage);
        // eslint-disable-next-line no-console
        console.log(`[Claude] Message pushed to stream for session ${body.session_id}`);

        // Note: We cannot cancel the timeout here because we don't have access to it
        // The timeout will be managed by the main async function
      } catch (error) {
        res.status(400).json({
          detail: error instanceof Error ? error.message : String(error)
        });
        return;
      }

      return;
    }

    // No active session - validate and prepare to start a new one
    const isNewSession = !body.session_id;
    let existingSession: Session | null = null;
    let finalCwd: string;

    if (isNewSession) {
      if (!body.cwd) {
        res.status(400).json({ detail: "cwd is required when starting a new session" });
        return;
      }
      const resolvedCwd = path.resolve(body.cwd);
      try {
        ensureDirectory(resolvedCwd);
      } catch (error) {
        res.status(400).json({ detail: error instanceof Error ? error.message : String(error) });
        return;
      }
      finalCwd = resolvedCwd;
    } else {
      existingSession = fetchSession(body.session_id!, false);
      if (!existingSession) {
        res.status(404).json({ detail: "Session not found" });
        return;
      }
      if (body.cwd && path.resolve(body.cwd) !== path.resolve(existingSession.cwd)) {
        res.status(400).json({ detail: "cwd mismatch for existing session" });
        return;
      }
      finalCwd = existingSession.cwd;
    }

    // Set up SSE response
    const runId = generateRunId();
    res.setHeader("Content-Type", "text/event-stream");
    res.setHeader("Cache-Control", "no-cache");
    res.setHeader("Connection", "keep-alive");
    res.setHeader("X-Claude-Run-Id", runId);
    if (typeof res.flushHeaders === "function") {
      res.flushHeaders();
    }

    // Create message stream controller
    const streamController = new MessageStreamController();
    const abortController = new AbortController();
    let sessionId: string | null = body.session_id ?? null;
    const newSessionTitle = deriveSessionTitle(userMessageText);
    const isNewSessionFlag = isNewSession;

    const newActiveSession: ActiveSession = {
      streamController,
      runId,
      abortController,
      cwd: finalCwd,
      sessionId,
      connections: new Set([res]),
      permissionMode,
      systemPrompt,
    };

    // Register active session - use a temporary key first if no session_id yet
    const tempKey = body.session_id || runId;
    activeSessions.set(tempKey, newActiveSession);
    activeClaudeRuns.set(runId, abortController);

    // Clean up when connections close
    const cleanup = () => {
      newActiveSession.connections.delete(res);
    };
    req.on("aborted", cleanup);
    res.on("close", cleanup);

    // Broadcast event to all connections
    const broadcastEvent = (event: string, payload: AnyRecord) => {
      const data = formatSse(event, payload);
      for (const connection of newActiveSession.connections) {
        if (!connection.writableEnded) {
          try {
            connection.write(data);
          } catch (error) {
            // eslint-disable-next-line no-console
            console.warn(`[SSE] failed to write ${event}:`, error);
          }
        }
      }
    };

    const options = buildClaudeOptionsFromRequest({
      body,
      cwd: finalCwd,
      permissionMode,
      systemPrompt,
      abortController,
    });

    // eslint-disable-next-line no-console
    console.log(`[Claude] starting run ${runId} for cwd=${finalCwd}`);
    broadcastEvent("run", { run_id: runId });

    // Push first message to stream
    const firstMessage: SDKUserMessage = {
      type: "user",
      message: {
        role: "user",
        content: body.message as any,
      },
      parent_tool_use_id: null,
      session_id: sessionId || "",
    };
    streamController.push(firstMessage);

    // Timeout to end stream if no new messages
    let endStreamTimeout: NodeJS.Timeout | null = null;
    const scheduleStreamEnd = () => {
      if (endStreamTimeout) {
        clearTimeout(endStreamTimeout);
      }
      // Wait 3 seconds after result, if no new messages arrive, end the stream
      endStreamTimeout = setTimeout(() => {
        if (!streamController.isEnded()) {
          // eslint-disable-next-line no-console
          console.log(`[Claude] No new messages for 3s, ending stream for session ${sessionId}`);
          streamController.end();
        }
      }, 3000);
    };

    // Start the query with async iterable stream
    (async () => {
      const assistantChunks: string[] = [];
      try {
        const stream = query({
          prompt: streamController.stream(),
          options,
        });

        // eslint-disable-next-line no-restricted-syntax
        for await (const message of stream) {
          const rawPayload = serializeSdkMessage(message);
          if (rawPayload) {
            logSdkMessage(message.type, rawPayload, "ClaudeSDK");
          }

          if (isSystemInitMessage(message)) {
            if (!sessionId) {
              sessionId = message.session_id;
              newActiveSession.sessionId = sessionId;

              // Update session registration with real session ID
              if (tempKey !== sessionId) {
                activeSessions.delete(tempKey);
                activeSessions.set(sessionId, newActiveSession);
              }

              if (sessionId && isNewSessionFlag) {
                persistSessionMetadata({
                  session_id: sessionId,
                  title: newSessionTitle,
                  cwd: finalCwd,
                  created_at: now,
                  updated_at: now,
                });
              }
              broadcastEvent("session", {
                session_id: sessionId,
                cwd: finalCwd,
                is_new: true,
              });
            } else {
              broadcastEvent("session", {
                session_id: sessionId,
                cwd: finalCwd,
                is_new: false,
              });
            }
          }

          if (isAssistantMessage(message)) {
            const blocks = Array.isArray(message.message?.content)
              ? message.message.content
              : [];
            for (const block of blocks) {
              if (isTextBlock(block)) {
                const chunk = block.text;
                if (chunk) {
                  assistantChunks.push(chunk);

                  // Simulate token-level streaming by splitting text into words
                  // This enables mid-stream message injection
                  const words = chunk.split(/(\s+)/); // Split on whitespace, keeping delimiters
                  for (const word of words) {
                    if (word) {
                      broadcastEvent("token", {
                        session_id: sessionId,
                        text: word,
                      });
                    }
                  }
                }
              }
            }
          }

          if (isResultMessage(message)) {
            if (!sessionId) {
              sessionId = message.session_id;
              newActiveSession.sessionId = sessionId;

              if (sessionId) {
                activeSessions.set(sessionId, newActiveSession);
              }

              broadcastEvent("session", {
                session_id: sessionId,
                cwd: finalCwd,
                is_new: isNewSessionFlag,
              });
            }
            if (
              "result" in message &&
              typeof message.result === "string" &&
              message.result
            ) {
              if (assistantChunks.length === 0) {
                assistantChunks.push(message.result);
              }

              // Simulate token-level streaming by splitting result text into words
              // This enables clients to detect progress and send interrupting messages
              const words = message.result.split(/(\s+)/);
              for (const word of words) {
                if (word) {
                  broadcastEvent("token", {
                    session_id: sessionId,
                    text: word,
                  });
                }
              }
            }

            // Result message received - schedule stream end if no new messages arrive
            if (streamController.pendingCount === 0) {
              // eslint-disable-next-line no-console
              console.log(`[Claude] Result received, scheduling stream end for session ${sessionId}`);
              scheduleStreamEnd();
            }
          }

          if (rawPayload) {
            const payloadSessionId = extractSessionIdFromPayload(rawPayload) ?? sessionId;
            if (!sessionId && payloadSessionId) {
              sessionId = payloadSessionId;
              newActiveSession.sessionId = sessionId;
              if (sessionId) {
                activeSessions.set(sessionId, newActiveSession);
              }
            }
            broadcastEvent("message", {
              session_id: payloadSessionId,
              payload: rawPayload,
            });
          }
        }

        if (!sessionId) {
          throw new Error("Claude did not return session_id");
        }

        const title = existingSession ? existingSession.title : newSessionTitle;
        persistSessionMetadata({
          session_id: sessionId,
          title,
          cwd: finalCwd,
          created_at: now,
          updated_at: now,
        });

        broadcastEvent("done", {
          run_id: runId,
          session_id: sessionId,
          cwd: finalCwd,
          length: assistantChunks.join("").length,
        });
      } catch (error) {
        const isAborted =
          (error instanceof Error && error.name === "AbortError") ||
          (error instanceof Error && error.message.toLowerCase().includes("abort"));
        if (isAborted) {
          broadcastEvent("stopped", {
            run_id: runId,
            session_id: sessionId,
          });
        } else {
          broadcastEvent("error", {
            run_id: runId,
            message: error instanceof Error ? error.message : String(error),
          });
        }
      } finally {
        // Cancel timeout and end the stream controller
        if (endStreamTimeout) {
          clearTimeout(endStreamTimeout);
        }
        streamController.end();

        // Clean up
        activeClaudeRuns.delete(runId);
        activeSessions.delete(tempKey);
        if (sessionId && sessionId !== tempKey) {
          activeSessions.delete(sessionId);
        }

        // Close all connections
        for (const connection of newActiveSession.connections) {
          if (!connection.writableEnded) {
            connection.end();
          }
        }
      }
    })();
  });

  app.post("/chat/stop", (req, res) => {
    const body = (req.body ?? {}) as StopChatRequest;
    const runId = typeof body?.run_id === "string" ? body.run_id.trim() : "";
    if (!runId) {
      res.status(400).json({ detail: "run_id is required" });
      return;
    }
    const controller = activeClaudeRuns.get(runId);
    if (!controller) {
      res.status(404).json({ detail: "Run not found or already completed" });
      return;
    }
    activeClaudeRuns.delete(runId);
    controller.abort();
    res.json({ run_id: runId, stopping: true });
  });

  app.post("/codex/chat", (req, res) => {
    const body = req.body as CodexChatRequest | undefined;
    if (!body || typeof body.message !== "string" || !body.message.trim()) {
      res.status(400).json({ detail: "message is required" });
      return;
    }

    const now = new Date();
    const isNewSession = !body.session_id;

    let existingSession: Session | null = null;
    let finalCwd: string;

    if (isNewSession) {
      if (!body.cwd) {
        res.status(400).json({ detail: "cwd is required when starting a new session" });
        return;
      }
      const resolvedCwd = path.resolve(body.cwd);
      try {
        ensureDirectory(resolvedCwd);
      } catch (error) {
        res.status(400).json({ detail: error instanceof Error ? error.message : String(error) });
        return;
      }
      finalCwd = resolvedCwd;
    } else {
      existingSession = fetchCodexSession(body.session_id!, false);
      if (!existingSession) {
        res.status(404).json({ detail: "Session not found" });
        return;
      }
      if (body.cwd && path.resolve(body.cwd) !== path.resolve(existingSession.cwd)) {
        res.status(400).json({ detail: "cwd mismatch for existing session" });
        return;
      }
      finalCwd = existingSession.cwd;
    }

    res.setHeader("Content-Type", "text/event-stream");
    res.setHeader("Cache-Control", "no-cache");
    res.setHeader("Connection", "keep-alive");
    if (typeof res.flushHeaders === "function") {
      res.flushHeaders();
    }

    const userSettings =
      req.userId !== undefined ? fetchCodexUserSettings(req.userId) : null;
    const mergedRequest: CodexChatRequest = {
      ...body,
      approval_policy: body.approval_policy ?? userSettings?.approval_policy,
      sandbox_mode: body.sandbox_mode ?? userSettings?.sandbox_mode,
      skip_git_repo_check: body.skip_git_repo_check ?? userSettings?.skip_git_repo_check,
      model: body.model ?? userSettings?.model,
      model_reasoning_effort: body.model_reasoning_effort ?? userSettings?.model_reasoning_effort,
      network_access_enabled: body.network_access_enabled ?? userSettings?.network_access_enabled,
      web_search_enabled: body.web_search_enabled ?? userSettings?.web_search_enabled,
    };

    const userMessageText = body.message;
    const newSessionTitle = deriveSessionTitle(userMessageText);
    const assistantChunks: string[] = [];
    const agentMessageProgress = new Map<string, string>();
    let sessionId: string | null = body.session_id ?? null;
    const isNewSessionFlag = isNewSession;

    const writeEvent = (event: string, payload: AnyRecord) => {
      res.write(formatSse(event, payload));
    };

    const threadOptions = buildCodexThreadOptions(mergedRequest, finalCwd);

    let streamClosed = false;
    res.on("close", () => {
      streamClosed = true;
    });

    (async () => {
      try {
        const codex = await getCodexClient();
        const thread = isNewSession
          ? codex.startThread(threadOptions)
          : codex.resumeThread(sessionId!, threadOptions);
        const resolveThreadId = () => {
          const id = thread.id;
          return typeof id === "string" && id ? id : null;
        };

        if (!isNewSession && sessionId) {
          writeEvent("session", {
            session_id: sessionId,
            cwd: finalCwd,
            is_new: false,
          });
        }

        const { events } = await thread.runStreamed(userMessageText);

        // eslint-disable-next-line no-restricted-syntax
        for await (const event of events) {
          if (streamClosed) {
            break;
          }

          logSdkMessage(event.type, event as AnyRecord, "CodexSDK");

          if (event.type === "thread.started") {
            if (!sessionId) {
              sessionId = event.thread_id;
              if (sessionId && isNewSessionFlag) {
                persistCodexSessionMetadata({
                  session_id: sessionId,
                  title: newSessionTitle,
                  cwd: finalCwd,
                  created_at: now,
                  updated_at: now,
                });
              }
            }
            writeEvent("session", {
              session_id: sessionId,
              cwd: finalCwd,
              is_new: isNewSessionFlag,
            });
          }

          if (event.type === "turn.failed") {
            throw new Error(event.error?.message ?? "Codex turn failed");
          }

          if (event.type === "error") {
            throw new Error(event.message ?? "Codex stream error");
          }

          if (event.type === "item.updated" || event.type === "item.completed") {
            const item = event.item as AnyRecord | undefined;
            if (item && item.type === "agent_message" && typeof item.id === "string") {
              if (typeof item.text === "string") {
                emitCodexAgentChunk(
                  item.id,
                  item.text,
                  assistantChunks,
                  writeEvent,
                  sessionId,
                  agentMessageProgress,
                );
              }
              if (event.type === "item.completed") {
                agentMessageProgress.delete(item.id);
              }
            }
          }

          writeEvent("message", {
            session_id: sessionId,
            payload: event,
          });
        }

        if (!sessionId) {
          sessionId = resolveThreadId();
          if (sessionId) {
            if (isNewSessionFlag) {
              persistCodexSessionMetadata({
                session_id: sessionId,
                title: newSessionTitle,
                cwd: finalCwd,
                created_at: now,
                updated_at: now,
              });
            }
            writeEvent("session", {
              session_id: sessionId,
              cwd: finalCwd,
              is_new: isNewSessionFlag,
            });
          } else {
            throw new Error("Codex did not return session_id");
          }
        }

        const title = existingSession ? existingSession.title : newSessionTitle;
        const createdAt = existingSession ? existingSession.created_at : now;

        persistCodexSessionMetadata({
          session_id: sessionId,
          title,
          cwd: finalCwd,
          created_at: createdAt,
          updated_at: now,
        });

        writeEvent("done", {
          session_id: sessionId,
          cwd: finalCwd,
          length: assistantChunks.join("").length,
        });
      } catch (error) {
        writeEvent("error", {
          message: error instanceof Error ? error.message : String(error),
        });
      } finally {
        res.end();
      }
    })();
  });

  return app;
}
