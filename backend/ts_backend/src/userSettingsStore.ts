import { getDb } from "./database";
import { SystemPrompt, UserSettings } from "./models";

function serializeSystemPrompt(value: SystemPrompt): string | null {
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value === "string") {
    return value;
  }
  try {
    return JSON.stringify(value);
  } catch (error) {
    throw new Error("system_prompt is not JSON serializable");
  }
}

function deserializeSystemPrompt(raw: unknown): SystemPrompt {
  if (raw === undefined || raw === null) {
    return null;
  }
  if (typeof raw !== "string") {
    return null;
  }
  try {
    return JSON.parse(raw);
  } catch {
    return raw;
  }
}

export function fetchUserSettings(userId: string): UserSettings | null {
  const row = getDb()
    .prepare("SELECT user_id, permission_mode, system_prompt FROM user_settings WHERE user_id = ?")
    .get(userId) as Record<string, unknown> | undefined;

  if (!row) {
    return null;
  }

  return {
    user_id: String(row.user_id),
    permission_mode: row.permission_mode as UserSettings["permission_mode"],
    system_prompt: deserializeSystemPrompt(row.system_prompt),
  };
}

export function upsertUserSettings(params: {
  user_id: string;
  permission_mode: UserSettings["permission_mode"];
  system_prompt: SystemPrompt;
}): UserSettings {
  const serializedPrompt = serializeSystemPrompt(params.system_prompt);

  getDb()
    .prepare(
      `
      INSERT INTO user_settings (user_id, permission_mode, system_prompt)
      VALUES (@user_id, @permission_mode, @system_prompt)
      ON CONFLICT(user_id) DO UPDATE SET
        permission_mode = excluded.permission_mode,
        system_prompt = excluded.system_prompt
      `,
    )
    .run({
      user_id: params.user_id,
      permission_mode: params.permission_mode,
      system_prompt: serializedPrompt,
    });

  return {
    user_id: params.user_id,
    permission_mode: params.permission_mode,
    system_prompt: params.system_prompt,
  };
}
