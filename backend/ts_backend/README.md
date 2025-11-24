# TypeScript Backend

This folder contains an Express/TypeScript implementation of the Claude Agent backend.
It mirrors the FastAPI version under `cc_B` while sharing the same configuration file,
database, and session ingestion logic. In addition to Claude Code, it now exposes a
parallel set of Codex CLI endpoints (prefixed with `/codex`) backed by
`@openai/codex-sdk`.

## Prerequisites

- Node.js 18+ and npm.
- Access to the Claude Desktop session directory configured in `config.yaml`.
- Your environment must be able to run the Claude Desktop binaries (same requirement
  as the Python backend) and have whatever credentials Claude Desktop needs.
- (Optional) To use Codex endpoints, install the Codex CLI via
  `@openai/codex-sdk` and ensure `config.yaml` points `codex_dir` to
  `~/.codex/sessions` (or wherever Codex stores sessions). Set `codex_api_key`
  / `codex_cli_path` if you rely on custom locations.

## Setup

```bash
cd ts_backend
npm install
```

The TypeScript sources live in `src/` and compile to `dist/`. At runtime, the server
directly uses the official `@anthropic-ai/claude-agent-sdk` package for Claude Code
and `@openai/codex-sdk` for Codex CLI, so no Python bridge process is needed.

## Running

- Development (ts-node): `npm run dev`
- Production build: `npm run build && npm start`

Both commands read `../config.yaml`, initialize the same SQLite database, and expose
the HTTP APIs described in `APIdocs.md`. Authentication still uses HTTP Basic
Auth and the stored credentials from the config file, and both Claude/Codex routes
share the same credential check.

## Codex endpoints

- `GET /codex/sessions` / `GET /codex/sessions/{id}` list sessions imported from
  `~/.codex/sessions`, mirroring the Claude endpoints.
- `POST /codex/sessions/load` rescans the Codex session tree and populates
  `codex_sessions` in SQLite.
- `GET/PUT /codex/users/{user_id}/settings` persist per-user Codex defaults such as
  approval policy or sandbox mode (stored as JSON).
- `POST /codex/chat` streams Codex CLI events over SSE with the same event names
  (`session`, `token`, `message`, `done`, `error`) as the Claude endpoint, so front-ends
  can reuse their client logic.
- `dev_tests/codex_sdk_smoketest.mjs` 是最小化的 Codex SDK 测试脚本，可帮助排查 CLI/SKD 环境。
  例如：`node dev_tests/codex_sdk_smoketest.mjs ./ "List files" --approval=never --sandbox=workspace-write`.

## Notes

- The service persists sessions and user settings using `better-sqlite3`, sharing
  the existing `sessions.db` file by default.
- Session ingestion scans the Claude Desktop `projects/` directory as well as the
  Codex CLI session tree, so you can switch between backends without re-importing.
- The actual Claude Code runtime is handled through `@anthropic-ai/claude-agent-sdk`,
  and Codex CLI support is provided via `@openai/codex-sdk`, matching the same
  behavior and permissions as their respective upstream CLIs.
