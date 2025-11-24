import { getDb } from "./database";
import {
  CodexUserSettings,
  CodexUserSettingsRequest,
  defaultCodexUserSettings,
} from "./models";

function serializeSettings(
  settings: CodexUserSettingsRequest,
): string {
  return JSON.stringify(settings ?? {});
}

function deserializeSettings(raw: unknown): CodexUserSettingsRequest {
  if (typeof raw !== "string") {
    return {};
  }
  try {
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed === "object") {
      return parsed as CodexUserSettingsRequest;
    }
    return {};
  } catch {
    return {};
  }
}

export function fetchCodexUserSettings(userId: string): CodexUserSettings | null {
  const row = getDb()
    .prepare("SELECT settings_json FROM codex_user_settings WHERE user_id = ?")
    .get(userId) as { settings_json: string } | undefined;

  if (!row) {
    return null;
  }

  const settings = deserializeSettings(row.settings_json);
  return {
    user_id: userId,
    ...settings,
  };
}

export function upsertCodexUserSettings(params: {
  user_id: string;
  settings: CodexUserSettingsRequest;
}): CodexUserSettings {
  getDb()
    .prepare(
      `
      INSERT INTO codex_user_settings (user_id, settings_json)
      VALUES (@user_id, @settings_json)
      ON CONFLICT(user_id) DO UPDATE SET
        settings_json = excluded.settings_json
      `,
    )
    .run({
      user_id: params.user_id,
      settings_json: serializeSettings(params.settings),
    });

  return {
    user_id: params.user_id,
    ...params.settings,
  };
}
