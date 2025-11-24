import type { SDKMessage } from "@anthropic-ai/claude-agent-sdk";

import { ENABLE_VERBOSE_LOGS } from "./config";

export type AnyRecord = Record<string, unknown>;

export function formatSse(event: string, data: AnyRecord): string {
  return `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function jsonify(value: unknown): unknown {
  if (
    value === null ||
    typeof value === "string" ||
    typeof value === "number" ||
    typeof value === "boolean"
  ) {
    return value;
  }
  if (Array.isArray(value)) {
    return value.map((item) => jsonify(item));
  }
  if (isPlainObject(value)) {
    const result: AnyRecord = {};
    for (const [key, val] of Object.entries(value)) {
      result[key] = jsonify(val);
    }
    return result;
  }
  if (value === undefined) {
    return null;
  }
  return String(value);
}

export function serializeSdkMessage(message: SDKMessage): AnyRecord | null {
  const payload = jsonify(message);
  if (isPlainObject(payload)) {
    return payload;
  }
  return null;
}

export function logSdkMessage(
  label: string,
  payload: AnyRecord | null,
  source = "ClaudeSDK",
): void {
  if (!ENABLE_VERBOSE_LOGS) {
    return;
  }
  try {
    // eslint-disable-next-line no-console
    console.log(
      `[${source}:${label}]\n${
        payload ? JSON.stringify(payload, null, 2) : "<empty>"
      }\n`,
    );
  } catch {
    // eslint-disable-next-line no-console
    console.log(`[${source}:${label}]\n${String(payload)}\n`);
  }
}
