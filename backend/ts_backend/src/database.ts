import fs from "fs";
import path from "path";
import Database from "better-sqlite3";

import { DB_PATH } from "./config";

let database: Database.Database | null = null;

function ensureDatabase(): Database.Database {
  if (!database) {
    fs.mkdirSync(path.dirname(DB_PATH), { recursive: true });
    database = new Database(DB_PATH);
    database.pragma("foreign_keys = ON");
  }
  return database;
}

export function initDb(): void {
  const db = ensureDatabase();
  db.prepare(
    `
    CREATE TABLE IF NOT EXISTS sessions (
      session_id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      cwd TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    `,
  ).run();

  db.prepare(
    `
    CREATE TABLE IF NOT EXISTS agent_sessions (
      agent_id TEXT PRIMARY KEY,
      parent_session_id TEXT,
      title TEXT NOT NULL,
      cwd TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY(parent_session_id) REFERENCES sessions(session_id) ON DELETE SET NULL
    )
    `,
  ).run();

  db.prepare(
    `
    CREATE TABLE IF NOT EXISTS user_settings (
      user_id TEXT PRIMARY KEY,
      permission_mode TEXT NOT NULL,
      system_prompt TEXT
    )
    `,
  ).run();

  db.prepare(
    `
    CREATE TABLE IF NOT EXISTS codex_sessions (
      session_id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      cwd TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    `,
  ).run();

  db.prepare(
    `
    CREATE TABLE IF NOT EXISTS codex_user_settings (
      user_id TEXT PRIMARY KEY,
      settings_json TEXT
    )
    `,
  ).run();
}

export function getDb(): Database.Database {
  return ensureDatabase();
}
