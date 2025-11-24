from __future__ import annotations

import json
from typing import Any, Optional

from .database import db_connection
from .models import UserSettings


def _serialize_system_prompt(value: Any) -> Optional[str]:
    if value is None:
        return None
    try:
        return json.dumps(value, ensure_ascii=False)
    except (TypeError, ValueError) as exc:  # pragma: no cover - invalid payloads
        raise ValueError("system_prompt is not JSON serializable") from exc


def _deserialize_system_prompt(raw: Optional[str]) -> Any:
    if raw is None:
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return raw


def fetch_user_settings(user_id: str) -> Optional[UserSettings]:
    with db_connection() as conn:
        row = conn.execute(
            "SELECT user_id, permission_mode, system_prompt FROM user_settings WHERE user_id = ?",
            (user_id,),
        ).fetchone()

    if row is None:
        return None

    return UserSettings(
        user_id=row["user_id"],
        permission_mode=row["permission_mode"],
        system_prompt=_deserialize_system_prompt(row["system_prompt"]),
    )


def upsert_user_settings(
    *, user_id: str, permission_mode: str, system_prompt: Any
) -> UserSettings:
    serialized_prompt = _serialize_system_prompt(system_prompt)

    with db_connection() as conn:
        conn.execute(
            """
            INSERT INTO user_settings (user_id, permission_mode, system_prompt)
            VALUES (?, ?, ?)
            ON CONFLICT(user_id) DO UPDATE SET
                permission_mode = excluded.permission_mode,
                system_prompt = excluded.system_prompt
            """,
            (user_id, permission_mode, serialized_prompt),
        )

    return UserSettings(
        user_id=user_id,
        permission_mode=permission_mode,
        system_prompt=system_prompt,
    )
