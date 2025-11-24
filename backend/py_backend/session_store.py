from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterator, List, Optional

from .config import CLAUDE_PROJECTS_DIR, CLAUDE_ROOT
from .database import db_connection
from .models import Session, SessionFileMetadata, SessionSummary


def _dt_to_str(dt: datetime) -> str:
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc).isoformat()


def _str_to_dt(value: str) -> datetime:
    return datetime.fromisoformat(value)


def _parse_iso_timestamp(value: Optional[str]) -> datetime:
    if not value:
        return datetime.now(timezone.utc)
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    try:
        return datetime.fromisoformat(value)
    except ValueError:
        return datetime.now(timezone.utc)


def _cwd_to_project_slug(cwd: str) -> str:
    normalized_path = Path(cwd).resolve()
    try:
        relative = normalized_path.relative_to(CLAUDE_PROJECTS_DIR)
    except ValueError:
        pass
    else:
        parts = relative.parts
        if parts:
            return parts[0]
    normalized = str(normalized_path)
    return re.sub(r"[^0-9A-Za-z]", "-", normalized)


def _session_file_path(cwd: str, session_id: str) -> Path:
    slug = _cwd_to_project_slug(cwd)
    return CLAUDE_PROJECTS_DIR / slug / f"{session_id}.jsonl"


def load_session_messages_from_jsonl(cwd: str, session_id: str) -> List[Dict[str, Any]]:
    path = _session_file_path(cwd, session_id)
    if not path.exists():
        return []

    messages: List[Dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handler:
        for line in handler:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue

            messages.append(record)

    return messages


def count_session_messages(cwd: str, session_id: str) -> int:
    path = _session_file_path(cwd, session_id)
    if not path.exists():
        return 0

    count = 0
    with path.open("r", encoding="utf-8") as handler:
        for line in handler:
            if line.strip():
                count += 1
    return count


def _is_agent_session_file(path: Path) -> bool:
    filename = path.name
    return filename.startswith("agent-") and filename.endswith(".jsonl")


def _iter_session_records(cwd: str, session_id: str) -> Iterator[Dict[str, Any]]:
    path = _session_file_path(cwd, session_id)
    if not path.exists():
        return iter(())

    def generator() -> Iterator[Dict[str, Any]]:
        with path.open("r", encoding="utf-8") as handler:
            for line in handler:
                line = line.strip()
                if not line:
                    continue
                try:
                    yield json.loads(line)
                except json.JSONDecodeError:
                    continue

    return generator()


def _iter_session_files_from_claude(root: Path) -> Iterator[Path]:
    project_dir = root / "projects"
    if not project_dir.exists():
        return iter(())

    def generator() -> Iterator[Path]:
        for project in project_dir.iterdir():
            if not project.is_dir():
                continue
            for file in project.glob("*.jsonl"):
                if file.is_file():
                    yield file

    return generator()


def _extract_session_metadata_from_file(path: Path) -> Optional[SessionFileMetadata]:
    try:
        with path.open("r", encoding="utf-8") as handler:
            first_line = handler.readline()
            if not first_line:
                return None
            data = json.loads(first_line)
    except (OSError, json.JSONDecodeError, UnicodeDecodeError):
        return None

    session_id = data.get("session_id")
    if not session_id:
        session_id = path.stem

    cwd = data.get("cwd") or data.get("project_path")
    if not cwd:
        return None

    created_at = _parse_iso_timestamp(data.get("created_at"))
    updated_at = _parse_iso_timestamp(data.get("updated_at"))
    title = data.get("title") or data.get("message", {}).get("text") or session_id
    parent_session_id = data.get("parent_session_id")
    is_agent_run = _is_agent_session_file(path)

    return SessionFileMetadata(
        session_id=session_id,
        title=title,
        cwd=cwd,
        created_at=created_at,
        updated_at=updated_at,
        parent_session_id=parent_session_id,
        is_agent_run=is_agent_run,
    )


def _discover_session_metadata_from_files(root: Path) -> Iterator[SessionFileMetadata]:
    for path in _iter_session_files_from_claude(root):
        metadata = _extract_session_metadata_from_file(path)
        if metadata:
            yield metadata


def fetch_session(session_id: str, include_messages: bool = True) -> Optional[Session]:
    with db_connection() as conn:
        row = conn.execute(
            "SELECT session_id, title, cwd, created_at, updated_at FROM sessions WHERE session_id = ?",
            (session_id,),
        ).fetchone()

    if not row:
        return None

    messages: List[Dict[str, Any]] = []
    if include_messages:
        messages = load_session_messages_from_jsonl(row["cwd"], row["session_id"])

    return Session(
        session_id=row["session_id"],
        title=row["title"],
        cwd=row["cwd"],
        created_at=_str_to_dt(row["created_at"]),
        updated_at=_str_to_dt(row["updated_at"]),
        messages=messages,
    )


def list_session_summaries() -> List[SessionSummary]:
    results: List[SessionSummary] = []
    with db_connection() as conn:
        rows = conn.execute(
            "SELECT session_id, title, cwd, created_at, updated_at FROM sessions ORDER BY updated_at DESC"
        ).fetchall()

    for row in rows:
        message_count = count_session_messages(row["cwd"], row["session_id"])
        results.append(
            SessionSummary(
                session_id=row["session_id"],
                title=row["title"],
                cwd=row["cwd"],
                created_at=_str_to_dt(row["created_at"]),
                updated_at=_str_to_dt(row["updated_at"]),
                message_count=message_count,
            )
        )

    return results


def persist_session_metadata(
    *, session_id: str, title: str, cwd: str, created_at: datetime, updated_at: datetime
) -> None:
    with db_connection() as conn:
        conn.execute(
            """
            INSERT INTO sessions (session_id, title, cwd, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?)
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
            """,
            (
                session_id,
                title,
                cwd,
                _dt_to_str(created_at),
                _dt_to_str(updated_at),
            ),
        )


def persist_agent_session_metadata(
    *,
    agent_id: str,
    parent_session_id: Optional[str],
    title: str,
    cwd: str,
    created_at: datetime,
    updated_at: datetime,
) -> None:
    with db_connection() as conn:
        conn.execute(
            """
            INSERT INTO agent_sessions (agent_id, parent_session_id, title, cwd, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
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
            """,
            (
                agent_id,
                parent_session_id,
                title,
                cwd,
                _dt_to_str(created_at),
                _dt_to_str(updated_at),
            ),
        )


def bootstrap_sessions_from_files(claude_dir: Optional[str] = None) -> Dict[str, int]:
    root = Path(claude_dir).expanduser() if claude_dir else CLAUDE_ROOT
    if not root.exists():
        raise FileNotFoundError(f"Claude directory does not exist: {root}")

    stats = {"sessions": 0, "agent_runs": 0}

    primary_sessions: List[SessionFileMetadata] = []
    agent_sessions: List[SessionFileMetadata] = []

    for metadata in _discover_session_metadata_from_files(root):
        if metadata.is_agent_run:
            agent_sessions.append(metadata)
        else:
            primary_sessions.append(metadata)

    existing_session_ids: set[str] = set()
    with db_connection() as conn:
        rows = conn.execute("SELECT session_id FROM sessions").fetchall()
        existing_session_ids.update(row["session_id"] for row in rows)

    for metadata in primary_sessions:
        persist_session_metadata(
            session_id=metadata.session_id,
            title=metadata.title,
            cwd=metadata.cwd,
            created_at=metadata.created_at,
            updated_at=metadata.updated_at,
        )
        stats["sessions"] += 1
        existing_session_ids.add(metadata.session_id)

    for metadata in agent_sessions:
        parent_session_id = (
            metadata.parent_session_id
            if metadata.parent_session_id in existing_session_ids
            else None
        )
        persist_agent_session_metadata(
            agent_id=metadata.session_id,
            parent_session_id=parent_session_id,
            title=metadata.title,
            cwd=metadata.cwd,
            created_at=metadata.created_at,
            updated_at=metadata.updated_at,
        )
        stats["agent_runs"] += 1

    return stats
