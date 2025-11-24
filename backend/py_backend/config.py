from __future__ import annotations

import os
import platform
from pathlib import Path
from typing import Any, Dict

import yaml

PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent  # CodeAgentHub root
CONFIG_PATH = PROJECT_ROOT / "config.yaml"
DEFAULT_USER_CREDENTIALS = {"admin": "642531"}


def _iter_candidate_claude_dirs():
    home = Path.home()

    env_values = [
        os.environ.get("CLAUDE_DIR"),
        os.environ.get("CLAUDE_HOME"),
    ]
    for value in env_values:
        if value:
            yield Path(value).expanduser()

    yield home / ".claude"

    system = platform.system().lower()
    if system == "darwin":
        yield home / "Library" / "Application Support" / "Claude"
    elif system == "windows":
        appdata = os.environ.get("APPDATA")
        if appdata:
            yield Path(appdata) / "Claude"
        localappdata = os.environ.get("LOCALAPPDATA")
        if localappdata:
            yield Path(localappdata) / "Claude"
        yield home / "AppData" / "Roaming" / "Claude"
        yield home / "AppData" / "Local" / "Claude"
    else:
        xdg_data_home = os.environ.get("XDG_DATA_HOME")
        if xdg_data_home:
            yield Path(xdg_data_home) / "claude"


def _detect_claude_dir() -> Path:
    fallback = (Path.home() / ".claude").expanduser()
    seen = set()

    for candidate in _iter_candidate_claude_dirs():
        resolved = candidate.expanduser()
        if resolved in seen:
            continue
        seen.add(resolved)

        if resolved.exists() or (resolved / "projects").exists():
            return resolved

    return fallback


def load_app_config() -> Dict[str, Any]:
    defaults = {
        "claude_dir": "",
        "sessions_db": str(PROJECT_ROOT / "sessions.db"),
        "users": DEFAULT_USER_CREDENTIALS.copy(),
    }

    try:
        with CONFIG_PATH.open("r", encoding="utf-8") as handler:
            data = yaml.safe_load(handler) or {}
    except FileNotFoundError:
        data = {}
    except yaml.YAMLError:
        data = {}

    if not isinstance(data, dict):
        data = {}

    config = defaults.copy()
    for key, value in data.items():
        if not isinstance(key, str):
            continue
        if key == "users" and isinstance(value, dict):
            sanitized: Dict[str, str] = {}
            for username, password in value.items():
                if not isinstance(username, str):
                    continue
                normalized = username.strip()
                if not normalized:
                    continue

                password_str: str | None = None
                if isinstance(password, str):
                    password_str = password
                elif isinstance(password, (int, float, bool)):
                    password_str = str(password)

                if password_str is not None:
                    sanitized[normalized] = password_str
            if sanitized:
                config["users"] = sanitized
            continue
        if isinstance(value, str) and value.strip():
            config[key] = value.strip()

    if not config.get("claude_dir"):
        config["claude_dir"] = str(_detect_claude_dir())

    return config


CONFIG = load_app_config()
CLAUDE_ROOT = Path(CONFIG["claude_dir"]).expanduser()
CLAUDE_PROJECTS_DIR = CLAUDE_ROOT / "projects"
_db_path = Path(CONFIG["sessions_db"])
if not _db_path.is_absolute():
    _db_path = (CONFIG_PATH.parent / _db_path).resolve()
DB_PATH = _db_path
USER_CREDENTIALS = CONFIG["users"]
