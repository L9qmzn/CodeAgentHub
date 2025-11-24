import fs from "fs";
import path from "path";

import { CODEX_SESSIONS_DIR } from "./config";
import { getDb } from "./database";
import { Session, SessionSummary } from "./models";

type AnyRecord = Record<string, any>;

interface CodexSessionMetadata {
  session_id: string;
  title: string;
  cwd: string;
  created_at: Date;
  updated_at: Date;
  file_path: string;
}

const fileCache = new Map<string, string>();

function parseTimestamp(value: unknown): Date | null {
  if (typeof value === "string") {
    const date = new Date(value);
    if (!Number.isNaN(date.getTime())) {
      return date;
    }
  }
  return null;
}

function deriveTitleFromText(text: string, fallback: string): string {
  const trimmed = text.trim();
  if (!trimmed) {
    return fallback;
  }
  if (trimmed.length <= 30) {
    return trimmed;
  }
  return `${trimmed.slice(0, 30)}...`;
}

function extractFirstUserText(content: unknown): string | null {
  if (!Array.isArray(content)) {
    return null;
  }

  for (const entry of content) {
    if (entry && typeof entry === "object" && typeof entry.text === "string") {
      return entry.text;
    }
  }

  return null;
}

function readFileLines(filePath: string): string[] {
  try {
    const data = fs.readFileSync(filePath, "utf-8");
    return data.split(/\r?\n/);
  } catch {
    return [];
  }
}

function extractMetadataFromFile(filePath: string): CodexSessionMetadata | null {
  const lines = readFileLines(filePath);
  if (!lines.length) {
    return null;
  }

  let sessionId: string | null = null;
  let cwd: string | null = null;
  let createdAt: Date | null = null;
  let updatedAt: Date | null = null;
  let firstUserText: string | null = null;

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

    const timestamp = parseTimestamp(record.timestamp);
    if (timestamp) {
      if (!createdAt || timestamp < createdAt) {
        createdAt = timestamp;
      }
      if (!updatedAt || timestamp > updatedAt) {
        updatedAt = timestamp;
      }
    }

    if (record.type === "session_meta" && record.payload) {
      const payload = record.payload as AnyRecord;
      if (!sessionId && typeof payload.id === "string") {
        sessionId = payload.id;
      }
      if (!cwd && typeof payload.cwd === "string") {
        cwd = payload.cwd;
      }
    }

    if (
      !firstUserText &&
      record.type === "response_item" &&
      record.payload &&
      typeof record.payload === "object" &&
      (record.payload as AnyRecord).role === "user"
    ) {
      const content = (record.payload as AnyRecord).content;
      const extracted = extractFirstUserText(content);
      if (extracted) {
        firstUserText = extracted;
      }
    }
  }

  if (!sessionId) {
    const match = path.basename(filePath).match(/[0-9a-fA-F-]{36}(?=\.jsonl$)/);
    sessionId = match ? match[0] : null;
  }

  if (!sessionId || !cwd) {
    return null;
  }

  const stats = fs.statSync(filePath);
  const fallbackCreated = new Date(stats.birthtimeMs || stats.mtimeMs);
  const fallbackUpdated = new Date(stats.mtimeMs);

  const title = firstUserText
    ? deriveTitleFromText(firstUserText, sessionId)
    : sessionId;

  return {
    session_id: sessionId,
    title,
    cwd,
    created_at: createdAt ?? fallbackCreated,
    updated_at: updatedAt ?? fallbackUpdated,
    file_path: filePath,
  };
}

function registerFile(sessionId: string, filePath: string): void {
  fileCache.set(sessionId, filePath);
}

function iterateSessionFiles(root: string): string[] {
  if (!fs.existsSync(root)) {
    return [];
  }

  const files: string[] = [];
  const stack: string[] = [root];

  while (stack.length) {
    const current = stack.pop();
    if (!current) {
      continue;
    }
    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(current, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const entry of entries) {
      const fullPath = path.join(current, entry.name);
      if (entry.isDirectory()) {
        stack.push(fullPath);
      } else if (entry.isFile() && entry.name.endsWith(".jsonl")) {
        files.push(fullPath);
      }
    }
  }

  return files;
}

function findSessionFile(sessionId: string): string | null {
  const cached = fileCache.get(sessionId);
  if (cached && fs.existsSync(cached)) {
    return cached;
  }

  const pattern = sessionId.toLowerCase();
  const files = iterateSessionFiles(CODEX_SESSIONS_DIR);
  for (const file of files) {
    if (file.toLowerCase().includes(pattern)) {
      fileCache.set(sessionId, file);
      return file;
    }
  }

  return null;
}

function loadCodexSessionMessagesFromFile(filePath: string): Record<string, unknown>[] {
  const lines = readFileLines(filePath);
  const messages: Record<string, unknown>[] = [];
  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line) {
      continue;
    }
    try {
      messages.push(JSON.parse(line));
    } catch {
      continue;
    }
  }
  return messages;
}

export function loadCodexSessionMessages(sessionId: string): Record<string, unknown>[] {
  const filePath = findSessionFile(sessionId);
  if (!filePath) {
    return [];
  }
  return loadCodexSessionMessagesFromFile(filePath);
}

function countCodexSessionMessages(sessionId: string): number {
  const filePath = findSessionFile(sessionId);
  if (!filePath) {
    return 0;
  }
  const lines = readFileLines(filePath);
  return lines.filter((line) => line.trim().length > 0).length;
}

export function persistCodexSessionMetadata(params: {
  session_id: string;
  title: string;
  cwd: string;
  created_at: Date;
  updated_at: Date;
}): void {
  getDb()
    .prepare(
      `
      INSERT INTO codex_sessions (session_id, title, cwd, created_at, updated_at)
      VALUES (@session_id, @title, @cwd, @created_at, @updated_at)
      ON CONFLICT(session_id) DO UPDATE SET
        title = excluded.title,
        cwd = excluded.cwd,
        created_at = CASE
          WHEN excluded.created_at < codex_sessions.created_at THEN excluded.created_at
          ELSE codex_sessions.created_at
        END,
        updated_at = CASE
          WHEN excluded.updated_at > codex_sessions.updated_at THEN excluded.updated_at
          ELSE codex_sessions.updated_at
        END
      `,
    )
    .run({
      session_id: params.session_id,
      title: params.title,
      cwd: params.cwd,
      created_at: params.created_at.toISOString(),
      updated_at: params.updated_at.toISOString(),
    });
}

export function fetchCodexSession(sessionId: string, includeMessages = true): Session | null {
  const row = getDb()
    .prepare(
      "SELECT session_id, title, cwd, created_at, updated_at FROM codex_sessions WHERE session_id = ?",
    )
    .get(sessionId) as
    | {
        session_id: string;
        title: string;
        cwd: string;
        created_at: string;
        updated_at: string;
      }
    | undefined;

  if (!row) {
    return null;
  }

  const messages = includeMessages ? loadCodexSessionMessages(row.session_id) : [];

  return {
    session_id: row.session_id,
    title: row.title,
    cwd: row.cwd,
    created_at: new Date(row.created_at),
    updated_at: new Date(row.updated_at),
    messages,
  };
}

export function listCodexSessionSummaries(): SessionSummary[] {
  const rows = getDb()
    .prepare("SELECT session_id, title, cwd, created_at, updated_at FROM codex_sessions ORDER BY updated_at DESC")
    .all() as {
    session_id: string;
    title: string;
    cwd: string;
    created_at: string;
    updated_at: string;
  }[];

  return rows.map((row) => ({
    session_id: row.session_id,
    title: row.title,
    cwd: row.cwd,
    created_at: new Date(row.created_at),
    updated_at: new Date(row.updated_at),
    message_count: countCodexSessionMessages(row.session_id),
  }));
}

export function bootstrapCodexSessionsFromFiles(dir?: string): { sessions: number } {
  const root = dir ? path.resolve(dir) : CODEX_SESSIONS_DIR;
  if (!fs.existsSync(root)) {
    throw new Error(`Codex sessions directory does not exist: ${root}`);
  }

  let loaded = 0;
  for (const file of iterateSessionFiles(root)) {
    const metadata = extractMetadataFromFile(file);
    if (!metadata) {
      continue;
    }
    registerFile(metadata.session_id, metadata.file_path);
    persistCodexSessionMetadata(metadata);
    loaded += 1;
  }

  return { sessions: loaded };
}
