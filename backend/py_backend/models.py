from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Any, Dict, List, Optional, Literal

from pydantic import BaseModel, Field


class Session(BaseModel):
    session_id: str
    title: str
    cwd: str
    created_at: datetime
    updated_at: datetime
    messages: List[Dict[str, Any]] = Field(default_factory=list)


@dataclass
class SessionFileMetadata:
    session_id: str
    title: str
    cwd: str
    created_at: datetime
    updated_at: datetime
    parent_session_id: Optional[str] = None
    is_agent_run: bool = False


def _default_system_prompt() -> Dict[str, str]:
    return {"type": "preset", "preset": "claude_code"}


class ChatRequest(BaseModel):
    session_id: Optional[str] = None
    cwd: Optional[str] = None
    message: str
    permission_mode: Literal["default", "plan", "acceptEdits", "bypassPermissions"] = "default"
    system_prompt: str | Dict[str, Any] | None = Field(default_factory=_default_system_prompt)


class SessionSummary(BaseModel):
    session_id: str
    title: str
    cwd: str
    created_at: datetime
    updated_at: datetime
    message_count: int


class LoadSessionsRequest(BaseModel):
    claude_dir: Optional[str] = None


class UserSettingsRequest(BaseModel):
    permission_mode: Literal["default", "plan", "acceptEdits", "bypassPermissions"] = "default"
    system_prompt: str | Dict[str, Any] | None = Field(default_factory=_default_system_prompt)


class UserSettings(UserSettingsRequest):
    user_id: str
