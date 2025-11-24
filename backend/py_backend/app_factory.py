from __future__ import annotations

import secrets
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

from fastapi import Depends, FastAPI, HTTPException
from fastapi.responses import StreamingResponse
from fastapi.security import HTTPBasic, HTTPBasicCredentials

from claude_agent_sdk import (
    query,
    ClaudeAgentOptions,
    AssistantMessage,
    SystemMessage,
    ResultMessage,
    TextBlock,
)

from .config import CLAUDE_ROOT, USER_CREDENTIALS
from .database import init_db
from .models import (
    ChatRequest,
    LoadSessionsRequest,
    Session,
    SessionSummary,
    UserSettings,
    UserSettingsRequest,
)
from .session_store import (
    bootstrap_sessions_from_files,
    fetch_session,
    list_session_summaries,
    persist_session_metadata,
)
from .streaming import _dump_sdk_message, _log_sdk_message, format_sse
from .user_settings_store import fetch_user_settings, upsert_user_settings


_http_basic = HTTPBasic()


def _require_user(credentials: HTTPBasicCredentials = Depends(_http_basic)) -> str:
    username = credentials.username or ""
    password = credentials.password or ""
    stored_password = USER_CREDENTIALS.get(username)
    if not stored_password or not secrets.compare_digest(password, stored_password):
        raise HTTPException(
            status_code=401,
            detail="Unauthorized",
            headers={"WWW-Authenticate": "Basic"},
        )
    return username


def _extract_session_id_from_payload(payload: Any) -> Optional[str]:
    if not isinstance(payload, dict):
        return None

    stack: List[Dict[str, Any]] = [payload]
    seen: set[int] = set()

    while stack:
        current = stack.pop()
        current_id = id(current)
        if current_id in seen:
            continue
        seen.add(current_id)

        value = current.get("session_id") or current.get("sessionId")
        if isinstance(value, str) and value:
            return value

        for child in current.values():
            if isinstance(child, dict):
                stack.append(child)
            elif isinstance(child, list):
                for item in child:
                    if isinstance(item, dict):
                        stack.append(item)

    return None


def create_app() -> FastAPI:
    init_db()
    bootstrap_sessions_from_files()

    app = FastAPI(title="Claude Agent SDK Chat Backend (Streaming + Sessions + CWD)")

    @app.get("/sessions", response_model=List[SessionSummary])
    async def list_sessions_route(
        _current_user: str = Depends(_require_user),
    ) -> List[SessionSummary]:
        """
        列出当前进程里所有已知会话（包含 cwd）
        """
        return list_session_summaries()

    @app.get("/sessions/{session_id}", response_model=Session)
    async def get_session_route(
        session_id: str, _current_user: str = Depends(_require_user)
    ) -> Session:
        """
        返回某个会话的详细信息（包含 cwd 和历史消息）
        """
        sess = fetch_session(session_id)
        if not sess:
            raise HTTPException(status_code=404, detail="Session not found")
        return sess

    @app.post("/sessions/load")
    async def load_sessions_route(
        body: LoadSessionsRequest, _current_user: str = Depends(_require_user)
    ):
        try:
            stats = bootstrap_sessions_from_files(body.claude_dir)
        except FileNotFoundError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

        resolved_root = (
            Path(body.claude_dir).expanduser() if body.claude_dir else CLAUDE_ROOT
        )

        return {
            "claude_dir": str(resolved_root),
            "sessions_loaded": stats["sessions"],
            "agent_runs_loaded": stats["agent_runs"],
        }

    @app.get("/users/{user_id}/settings", response_model=UserSettings)
    async def get_user_settings_route(
        user_id: str, current_user: str = Depends(_require_user)
    ) -> UserSettings:
        if current_user != user_id:
            raise HTTPException(status_code=403, detail="Forbidden")
        settings = fetch_user_settings(user_id)
        if settings is None:
            return UserSettings(user_id=user_id)
        return settings

    @app.put("/users/{user_id}/settings", response_model=UserSettings)
    async def upsert_user_settings_route(
        user_id: str,
        body: UserSettingsRequest,
        current_user: str = Depends(_require_user),
    ) -> UserSettings:
        if current_user != user_id:
            raise HTTPException(status_code=403, detail="Forbidden")
        return upsert_user_settings(
            user_id=user_id,
            permission_mode=body.permission_mode,
            system_prompt=body.system_prompt,
        )

    @app.post("/chat")
    async def chat_route(
        body: ChatRequest,
        _current_user: str = Depends(_require_user),
    ):
        """
        核心流式聊天接口，返回 SSE 流
        """

        now = datetime.now(timezone.utc)
        is_new_session = body.session_id is None

        existing_session: Optional[Session] = None
        final_cwd: str

        if is_new_session:
            if not body.cwd:
                raise HTTPException(
                    status_code=400,
                    detail="cwd is required when starting a new session",
                )
            if not Path(body.cwd).is_dir():
                raise HTTPException(
                    status_code=400,
                    detail=f"cwd does not exist or is not a directory: {body.cwd}",
                )
            final_cwd = str(Path(body.cwd).resolve())
        else:
            assert body.session_id is not None
            existing_session = fetch_session(body.session_id, include_messages=False)
            if not existing_session:
                raise HTTPException(status_code=404, detail="Session not found")

            if body.cwd and Path(body.cwd).resolve() != Path(
                existing_session.cwd
            ).resolve():
                raise HTTPException(
                    status_code=400,
                    detail="cwd mismatch for existing session",
                )
            final_cwd = existing_session.cwd

        async def event_stream():
            session_id: Optional[str] = body.session_id
            assistant_chunks: List[str] = []
            user_message_text = body.message
            new_session_title = user_message_text.strip() or "新会话"
            if len(new_session_title) > 30:
                new_session_title = new_session_title[:30] + "..."

            try:
                options = ClaudeAgentOptions(
                    resume=body.session_id,
                    cwd=final_cwd,
                    include_partial_messages=True,
                    setting_sources=["user"],
                    permission_mode=body.permission_mode,
                    system_prompt=body.system_prompt,
                )

                async for message in query(prompt=user_message_text, options=options):
                    raw_payload = _dump_sdk_message(message)
                    if raw_payload is not None:
                        _log_sdk_message(type(message).__name__, raw_payload)
                    else:
                        _log_sdk_message(
                            type(message).__name__,
                            {"__repr__": repr(message)},
                        )

                    if isinstance(message, SystemMessage):
                        if message.subtype == "init":
                            if session_id is None:
                                session_id = message.data.get("session_id")
                                if session_id is not None and is_new_session:
                                    persist_session_metadata(
                                        session_id=session_id,
                                        title=new_session_title,
                                        cwd=final_cwd,
                                        created_at=now,
                                        updated_at=now,
                                    )
                                yield format_sse(
                                    "session",
                                    {
                                        "session_id": session_id,
                                        "cwd": final_cwd,
                                        "is_new": True,
                                    },
                                )
                            else:
                                yield format_sse(
                                    "session",
                                    {
                                        "session_id": session_id,
                                        "cwd": final_cwd,
                                        "is_new": False,
                                    },
                                )

                    if isinstance(message, AssistantMessage):
                        for block in message.content:
                            if isinstance(block, TextBlock):
                                chunk = block.text
                                if not chunk:
                                    continue
                                assistant_chunks.append(chunk)
                                yield format_sse(
                                    "token",
                                    {
                                        "session_id": session_id,
                                        "text": chunk,
                                    },
                                )

                    if isinstance(message, ResultMessage):
                        if session_id is None:
                            session_id = message.session_id
                            yield format_sse(
                                "session",
                                {
                                    "session_id": session_id,
                                    "cwd": final_cwd,
                                    "is_new": is_new_session,
                                },
                            )

                        if message.result is not None and not assistant_chunks:
                            assistant_chunks.append(message.result)

                    if raw_payload is not None:
                        payload_session_id = (
                            _extract_session_id_from_payload(raw_payload) or session_id
                        )
                        if session_id is None and payload_session_id is not None:
                            session_id = payload_session_id
                        yield format_sse(
                            "message",
                            {
                                "session_id": payload_session_id,
                                "payload": raw_payload,
                            },
                        )

                if session_id is None:
                    raise RuntimeError("Claude did not return session_id")

                full_assistant_text = "".join(assistant_chunks)

                if existing_session is None:
                    title = new_session_title
                else:
                    title = existing_session.title

                persist_session_metadata(
                    session_id=session_id,
                    title=title,
                    cwd=final_cwd,
                    created_at=now,
                    updated_at=now,
                )

                yield format_sse(
                    "done",
                    {
                        "session_id": session_id,
                        "cwd": final_cwd,
                        "length": len(full_assistant_text),
                    },
                )

            except Exception as exc:
                yield format_sse(
                    "error",
                    {
                        "message": str(exc),
                    },
                )

        return StreamingResponse(
            event_stream(),
            media_type="text/event-stream",
            headers={
                "Cache-Control": "no-cache",
                "X-Accel-Buffering": "no",
            },
        )

    return app
