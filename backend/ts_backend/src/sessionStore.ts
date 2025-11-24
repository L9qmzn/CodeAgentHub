import fs from "fs";
import path from "path";

import { CLAUDE_PROJECTS_DIR, CLAUDE_ROOT } from "./config";
import { getDb } from "./database";
import { Session, SessionFileMetadata, SessionSummary } from "./models";

type AnyRecord = Record<string, unknown>;

function dtToStr(value: Date): string {
  return value.toISOString();
}

function strToDate(value: string): Date {
  return new Date(value);
}

function parseIsoTimestamp(raw?: string | null): Date | null {
  if (!raw) {
    return null;
  }
  try {
    const timestamp = new Date(raw);
    if (!Number.isNaN(timestamp.getTime())) {
      return timestamp;
    }
  } catch {
    // ignore parse errors
  }
  return null;
}

function readFileLines(filePath: string): string[] {
  try {
    const content = fs.readFileSync(filePath, "utf-8");
    return content.split(/\r?\n/);
  } catch {
    return [];
  }
}

function extractTimestampFromRecord(record: AnyRecord, depth = 0): Date | null {
  if (depth > 4) {
    return null;
  }
  const timestampKeys: (keyof AnyRecord)[] = ["timestamp", "created_at", "updated_at"];
  for (const key of timestampKeys) {
    const value = record[key];
    if (typeof value === "string") {
      const parsed = parseIsoTimestamp(value);
      if (parsed) {
        return parsed;
      }
    }
  }
  const nestedKeys: (keyof AnyRecord)[] = ["payload", "message", "data", "event"];
  for (const key of nestedKeys) {
    const nested = record[key];
    if (!nested) {
      continue;
    }
    if (Array.isArray(nested)) {
      for (const entry of nested) {
        if (entry && typeof entry === "object") {
          const parsed = extractTimestampFromRecord(entry as AnyRecord, depth + 1);
          if (parsed) {
            return parsed;
          }
        }
      }
      continue;
    }
    if (typeof nested === "object") {
      const parsed = extractTimestampFromRecord(nested as AnyRecord, depth + 1);
      if (parsed) {
        return parsed;
      }
    }
  }
  return null;
}

function fallbackTimestampsFromFile(filePath: string): { created: Date | null; updated: Date | null } {
  try {
    const stats = fs.statSync(filePath);
    const created = Number.isFinite(stats.birthtimeMs) && stats.birthtimeMs > 0 ? new Date(stats.birthtimeMs) : null;
    const updatedSource =
      (Number.isFinite(stats.mtimeMs) && stats.mtimeMs > 0
        ? stats.mtimeMs
        : Number.isFinite(stats.ctimeMs) && stats.ctimeMs > 0
          ? stats.ctimeMs
          : null);
    const updated = typeof updatedSource === "number" ? new Date(updatedSource) : null;
    return { created, updated };
  } catch {
    return { created: null, updated: null };
  }
}

function extractMessageText(message: AnyRecord): string | null {
  if (typeof message.text === "string" && message.text.trim()) {
    return message.text.trim();
  }
  const content = message.content;
  if (typeof content === "string" && content.trim()) {
    return content.trim();
  }
  if (Array.isArray(content)) {
    for (const entry of content) {
      if (!entry || typeof entry !== "object") {
        continue;
      }
      const entryRecord = entry as AnyRecord;
      if (typeof entryRecord.text === "string" && entryRecord.text.trim()) {
        return entryRecord.text.trim();
      }
    }
  }
  return null;
}

function cwdToProjectSlug(cwd: string): string {
  const normalized = path.resolve(cwd);
  return normalized.replace(/[^0-9A-Za-z]/g, "-");
}

function sessionFilePath(cwd: string, sessionId: string): string {
  const slug = cwdToProjectSlug(cwd);
  return path.join(CLAUDE_PROJECTS_DIR, slug, `${sessionId}.jsonl`);
}

export function loadSessionMessagesFromJsonl(
  cwd: string,
  sessionId: string,
): Record<string, unknown>[] {
  const filePath = sessionFilePath(cwd, sessionId);
  if (!fs.existsSync(filePath)) {
    return [];
  }

  const messages: Record<string, unknown>[] = [];
  try {
    const content = fs.readFileSync(filePath, "utf-8");
    for (const rawLine of content.split(/\r?\n/)) {
      const line = rawLine.trim();
      if (!line) {
        continue;
      }
      try {
        messages.push(JSON.parse(line));
      } catch {
        // Skip malformed lines
      }
    }
  } catch {
    return [];
  }

  return messages;
}

export function countSessionMessages(cwd: string, sessionId: string): number {
  const filePath = sessionFilePath(cwd, sessionId);
  if (!fs.existsSync(filePath)) {
    return 0;
  }

  try {
    const content = fs.readFileSync(filePath, "utf-8");
    return content
      .split(/\r?\n/)
      .filter((line) => line.trim().length > 0).length;
  } catch {
    return 0;
  }
}

function isAgentSessionFile(filePath: string): boolean {
  const fileName = path.basename(filePath);
  return fileName.startsWith("agent-") && fileName.endsWith(".jsonl");
}

function* iterSessionFilesFromClaude(root: string): Generator<string> {
  const projectDir = path.join(root, "projects");
  if (!fs.existsSync(projectDir)) {
    return;
  }

  const projects = fs.readdirSync(projectDir, { withFileTypes: true });
  for (const project of projects) {
    if (!project.isDirectory()) {
      continue;
    }
    const projectPath = path.join(projectDir, project.name);
    const files = fs.readdirSync(projectPath, { withFileTypes: true });
    for (const file of files) {
      if (file.isFile() && file.name.endsWith(".jsonl")) {
        yield path.join(projectPath, file.name);
      }
    }
  }
}

function extractSessionMetadataFromFile(filePath: string): SessionFileMetadata | null {
  const lines = readFileLines(filePath);
  if (!lines.length) {
    return null;
  }

  let sessionId: string | null = null;
  let cwd: string | null = null;
  let parentSessionId: string | null | undefined = undefined;
  let explicitCreatedAt: Date | null = null;
  let explicitUpdatedAt: Date | null = null;
  let directTitle: string | null = null;
  let firstUserText: string | null = null;
  let earliestTimestamp: Date | null = null;
  let latestTimestamp: Date | null = null;

  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line) {
      continue;
    }
    let record: AnyRecord;
    try {
      record = JSON.parse(line);
    } catch {
      continue;
    }

    const timestamp = extractTimestampFromRecord(record);
    if (timestamp) {
      if (!earliestTimestamp || timestamp.getTime() < earliestTimestamp.getTime()) {
        earliestTimestamp = timestamp;
      }
      if (!latestTimestamp || timestamp.getTime() > latestTimestamp.getTime()) {
        latestTimestamp = timestamp;
      }
    }

    if (!sessionId) {
      if (typeof record.session_id === "string" && record.session_id) {
        sessionId = record.session_id;
      } else if (typeof record.sessionId === "string" && record.sessionId) {
        sessionId = record.sessionId;
      }
    }

    if (!cwd) {
      const cwdCandidate =
        (typeof record.cwd === "string" && record.cwd) ||
        (typeof record.project_path === "string" && record.project_path) ||
        (typeof record.projectPath === "string" && record.projectPath);
      if (cwdCandidate) {
        cwd = cwdCandidate;
      }
    }

    if (parentSessionId === undefined) {
      if ("parent_session_id" in record) {
        const value = (record as { parent_session_id?: unknown }).parent_session_id;
        parentSessionId = value === null ? null : typeof value === "string" ? value : undefined;
      } else if ("parentSessionId" in record) {
        const value = (record as { parentSessionId?: unknown }).parentSessionId;
        parentSessionId = value === null ? null : typeof value === "string" ? value : undefined;
      }
    }

    if (!directTitle && typeof record.title === "string" && record.title.trim()) {
      directTitle = record.title.trim();
    }

    if (!firstUserText && record.message && typeof record.message === "object") {
      const messageRecord = record.message as AnyRecord;
      if (messageRecord.role === "user") {
        const text = extractMessageText(messageRecord);
        if (text) {
          firstUserText = text;
        }
      }
    }

    if (!explicitCreatedAt) {
      const rawCreated =
        (typeof record.created_at === "string" && record.created_at) ||
        (typeof record.createdAt === "string" && record.createdAt);
      const parsed = rawCreated ? parseIsoTimestamp(rawCreated) : null;
      if (parsed) {
        explicitCreatedAt = parsed;
      }
    }

    if (!explicitUpdatedAt) {
      const rawUpdated =
        (typeof record.updated_at === "string" && record.updated_at) ||
        (typeof record.updatedAt === "string" && record.updatedAt);
      const parsed = rawUpdated ? parseIsoTimestamp(rawUpdated) : null;
      if (parsed) {
        explicitUpdatedAt = parsed;
      }
    }
  }

  if (!sessionId) {
    sessionId = path.parse(filePath).name;
  }
  if (!cwd) {
    return null;
  }

  const fileStatFallback = fallbackTimestampsFromFile(filePath);
  const createdAt = explicitCreatedAt ?? earliestTimestamp ?? fileStatFallback.created ?? new Date();
  const updatedAt =
    explicitUpdatedAt ?? latestTimestamp ?? fileStatFallback.updated ?? createdAt;

  const title = directTitle ?? firstUserText ?? sessionId;

  return {
    session_id: sessionId,
    title,
    cwd,
    created_at: createdAt,
    updated_at: updatedAt,
    parent_session_id: parentSessionId ?? undefined,
    is_agent_run: isAgentSessionFile(filePath),
  };
}

function* discoverSessionMetadataFromFiles(root: string): Generator<SessionFileMetadata> {
  for (const filePath of iterSessionFilesFromClaude(root)) {
    const metadata = extractSessionMetadataFromFile(filePath);
    if (metadata) {
      yield metadata;
    }
  }
}

export function fetchSession(sessionId: string, includeMessages = true): Session | null {
  const row = getDb()
    .prepare(
      "SELECT session_id, title, cwd, created_at, updated_at FROM sessions WHERE session_id = ?",
    )
    .get(sessionId) as Record<string, string> | undefined;

  if (!row) {
    return null;
  }

  let messages: Record<string, unknown>[] = [];
  if (includeMessages) {
    messages = loadSessionMessagesFromJsonl(row.cwd, row.session_id);
  }

  return {
    session_id: row.session_id,
    title: row.title,
    cwd: row.cwd,
    created_at: strToDate(row.created_at),
    updated_at: strToDate(row.updated_at),
    messages,
  };
}

export function listSessionSummaries(): SessionSummary[] {
  const rows = getDb()
    .prepare(
      "SELECT session_id, title, cwd, created_at, updated_at FROM sessions ORDER BY updated_at DESC",
    )
    .all() as Record<string, string>[];

  return rows.map((row) => ({
    session_id: row.session_id,
    title: row.title,
    cwd: row.cwd,
    created_at: strToDate(row.created_at),
    updated_at: strToDate(row.updated_at),
    message_count: countSessionMessages(row.cwd, row.session_id),
  }));
}

export function persistSessionMetadata(params: {
  session_id: string;
  title: string;
  cwd: string;
  created_at: Date;
  updated_at: Date;
}): void {
  getDb()
    .prepare(
      `
      INSERT INTO sessions (session_id, title, cwd, created_at, updated_at)
      VALUES (@session_id, @title, @cwd, @created_at, @updated_at)
      ON CONFLICT(session_id) DO UPDATE SET
        title = excluded.title,
        cwd = excluded.cwd,
        created_at = CASE
          WHEN excluded.created_at < sessions.created_at THEN excluded.created_at
          ELSE sessions.created_at
        END,
        updated_at = CASE
          WHEN excluded.updated_at > sessions.updated_at THEN excluded.updated_at
          ELSE sessions.updated_at
        END
      `,
    )
    .run({
      session_id: params.session_id,
      title: params.title,
      cwd: params.cwd,
      created_at: dtToStr(params.created_at),
      updated_at: dtToStr(params.updated_at),
    });
}

export function persistAgentSessionMetadata(params: {
  agent_id: string;
  parent_session_id?: string | null;
  title: string;
  cwd: string;
  created_at: Date;
  updated_at: Date;
}): void {
  getDb()
    .prepare(
      `
      INSERT INTO agent_sessions (agent_id, parent_session_id, title, cwd, created_at, updated_at)
      VALUES (@agent_id, @parent_session_id, @title, @cwd, @created_at, @updated_at)
      ON CONFLICT(agent_id) DO UPDATE SET
        parent_session_id = COALESCE(excluded.parent_session_id, agent_sessions.parent_session_id),
        title = excluded.title,
        cwd = excluded.cwd,
        created_at = CASE
          WHEN agent_sessions.created_at IS NULL THEN excluded.created_at
          WHEN excluded.created_at < agent_sessions.created_at THEN excluded.created_at
          ELSE agent_sessions.created_at
        END,
        updated_at = CASE
          WHEN agent_sessions.updated_at IS NULL THEN excluded.updated_at
          WHEN excluded.updated_at > agent_sessions.updated_at THEN excluded.updated_at
          ELSE agent_sessions.updated_at
        END
      `,
    )
    .run({
      agent_id: params.agent_id,
      parent_session_id: params.parent_session_id ?? null,
      title: params.title,
      cwd: params.cwd,
      created_at: dtToStr(params.created_at),
      updated_at: dtToStr(params.updated_at),
    });
}

export function bootstrapSessionsFromFiles(claudeDir?: string): { sessions: number; agent_runs: number } {
  const root = claudeDir ? path.resolve(claudeDir) : CLAUDE_ROOT;
  if (!fs.existsSync(root)) {
    throw new Error(`Claude directory does not exist: ${root}`);
  }

  const stats = { sessions: 0, agent_runs: 0 };

  const primarySessions: SessionFileMetadata[] = [];
  const agentSessions: SessionFileMetadata[] = [];

  for (const metadata of discoverSessionMetadataFromFiles(root)) {
    if (metadata.is_agent_run) {
      agentSessions.push(metadata);
    } else {
      primarySessions.push(metadata);
    }
  }

  const existingSessionIds = new Set<string>();
  const rows = getDb().prepare("SELECT session_id FROM sessions").all() as Record<string, string>[];
  for (const row of rows) {
    existingSessionIds.add(row.session_id);
  }

  for (const metadata of primarySessions) {
    persistSessionMetadata({
      session_id: metadata.session_id,
      title: metadata.title,
      cwd: metadata.cwd,
      created_at: metadata.created_at,
      updated_at: metadata.updated_at,
    });
    stats.sessions += 1;
    existingSessionIds.add(metadata.session_id);
  }

  for (const metadata of agentSessions) {
    const parentSessionId =
      metadata.parent_session_id && existingSessionIds.has(metadata.parent_session_id)
        ? metadata.parent_session_id
        : null;
    persistAgentSessionMetadata({
      agent_id: metadata.session_id,
      parent_session_id: parentSessionId,
      title: metadata.title,
      cwd: metadata.cwd,
      created_at: metadata.created_at,
      updated_at: metadata.updated_at,
    });
    stats.agent_runs += 1;
  }

  return stats;
}
