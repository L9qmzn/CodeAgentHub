from __future__ import annotations

import json
from dataclasses import asdict, is_dataclass
from typing import Any, Dict, Optional

from claude_agent_sdk import (
    AssistantMessage,
    ResultMessage,
    SystemMessage,
    TextBlock,
    ThinkingBlock,
    ToolResultBlock,
    ToolUseBlock,
    UserMessage,
)

try:
    from claude_agent_sdk.types import StreamEvent as _StreamEventType
except ImportError:  # pragma: no cover - fallback for older SDKs
    _StreamEventType = None


def format_sse(event: str, data: dict) -> str:
    """
    把事件打成 SSE 格式:
      event: <event>
      data: <json>
    （空行分隔事件）
    """
    return f"event: {event}\ndata: {json.dumps(data, ensure_ascii=False)}\n\n"


def _jsonify(value: Any) -> Any:
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    if isinstance(value, dict):
        return {str(key): _jsonify(val) for key, val in value.items()}
    if isinstance(value, (list, tuple, set)):
        return [_jsonify(item) for item in value]
    if is_dataclass(value):
        return _jsonify(asdict(value))
    if hasattr(value, "__dict__"):
        data = {
            key: val for key, val in vars(value).items() if not key.startswith("_")
        }
        if data:
            return {key: _jsonify(val) for key, val in data.items()}
    return str(value)


def _serialize_content_block(block: Any) -> Dict[str, Any]:
    if isinstance(block, TextBlock):
        return {"type": "text", "text": block.text}
    if isinstance(block, ThinkingBlock):
        return {
            "type": "thinking",
            "thinking": block.thinking,
            "signature": block.signature,
        }
    if isinstance(block, ToolUseBlock):
        return {
            "type": "tool_use",
            "id": block.id,
            "name": block.name,
            "input": _jsonify(block.input),
        }
    if isinstance(block, ToolResultBlock):
        payload: Dict[str, Any] = {
            "type": "tool_result",
            "tool_use_id": block.tool_use_id,
            "is_error": block.is_error,
        }
        if block.content is not None:
            payload["content"] = _jsonify(block.content)
        return payload
    if isinstance(block, dict):
        return {str(key): _jsonify(val) for key, val in block.items()}

    serialized = _jsonify(block)
    if isinstance(serialized, dict):
        return serialized
    return {"type": "unknown", "value": serialized}


def _serialize_sdk_message(message: Any) -> Optional[Dict[str, Any]]:
    if isinstance(message, UserMessage):
        payload: Dict[str, Any] = {
            "type": "user",
        }
        if isinstance(message.content, list):
            payload["content"] = [
                _serialize_content_block(block) for block in message.content
            ]
        else:
            payload["content"] = message.content
        if message.parent_tool_use_id is not None:
            payload["parent_tool_use_id"] = message.parent_tool_use_id
        return payload

    if isinstance(message, SystemMessage):
        payload: Dict[str, Any] = {
            "type": "system",
            "subtype": message.subtype,
            "data": _jsonify(message.data),
        }
        session_id = message.data.get("session_id") if isinstance(message.data, dict) else None
        if isinstance(session_id, str):
            payload["session_id"] = session_id
        return payload

    if isinstance(message, AssistantMessage):
        payload: Dict[str, Any] = {
            "type": "assistant",
            "model": message.model,
            "content": [_serialize_content_block(block) for block in message.content],
        }
        if message.parent_tool_use_id is not None:
            payload["parent_tool_use_id"] = message.parent_tool_use_id
        return payload

    if isinstance(message, ResultMessage):
        payload: Dict[str, Any] = {
            "type": "result",
            "subtype": message.subtype,
            "duration_ms": message.duration_ms,
            "duration_api_ms": message.duration_api_ms,
            "is_error": message.is_error,
            "num_turns": message.num_turns,
            "session_id": message.session_id,
        }
        if message.total_cost_usd is not None:
            payload["total_cost_usd"] = message.total_cost_usd
        if message.usage is not None:
            payload["usage"] = _jsonify(message.usage)
        if message.result is not None:
            payload["result"] = message.result
        return payload

    if _StreamEventType is not None and isinstance(message, _StreamEventType):
        payload = {
            "type": "stream_event",
            "uuid": message.uuid,
            "session_id": message.session_id,
            "event": _jsonify(message.event),
        }
        if message.parent_tool_use_id is not None:
            payload["parent_tool_use_id"] = message.parent_tool_use_id
        return payload

    if isinstance(message, dict):
        return {str(key): _jsonify(val) for key, val in message.items()}

    return None


def _dump_sdk_message(message: Any) -> Optional[Dict[str, Any]]:
    payload = _serialize_sdk_message(message)
    if payload is not None:
        return payload

    serialized = _jsonify(message)
    if isinstance(serialized, dict):
        return serialized

    if serialized is not None:
        return {
            "type": type(message).__name__,
            "value": serialized,
        }

    return None


def _log_sdk_message(label: str, payload: Dict[str, Any]) -> None:
    try:
        serialized = json.dumps(payload, ensure_ascii=False, indent=2)
    except Exception:
        serialized = str(payload)
    print(f"[ClaudeSDK:{label}]\n{serialized}\n", flush=True)
