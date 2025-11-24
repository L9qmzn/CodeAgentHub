import type { Options as ClaudeAgentOptions } from "@anthropic-ai/claude-agent-sdk";
import type {
  ApprovalMode,
  ModelReasoningEffort,
  SandboxMode,
} from "@openai/codex-sdk";

export type PermissionMode = "default" | "plan" | "acceptEdits" | "bypassPermissions";

export type SystemPrompt = string | Record<string, unknown> | null;

export interface ClaudeChatOptionsPayload {
  additional_directories?: ClaudeAgentOptions["additionalDirectories"];
  agents?: ClaudeAgentOptions["agents"];
  allowed_tools?: ClaudeAgentOptions["allowedTools"];
  continue?: ClaudeAgentOptions["continue"];
  disallowed_tools?: ClaudeAgentOptions["disallowedTools"];
  env?: ClaudeAgentOptions["env"];
  executable?: ClaudeAgentOptions["executable"];
  executable_args?: ClaudeAgentOptions["executableArgs"];
  extra_args?: ClaudeAgentOptions["extraArgs"];
  fallback_model?: ClaudeAgentOptions["fallbackModel"];
  fork_session?: ClaudeAgentOptions["forkSession"];
  include_partial_messages?: ClaudeAgentOptions["includePartialMessages"];
  max_thinking_tokens?: ClaudeAgentOptions["maxThinkingTokens"];
  max_turns?: ClaudeAgentOptions["maxTurns"];
  max_budget_usd?: ClaudeAgentOptions["maxBudgetUsd"];
  mcp_servers?: ClaudeAgentOptions["mcpServers"];
  model?: ClaudeAgentOptions["model"];
  path_to_claude_code_executable?: ClaudeAgentOptions["pathToClaudeCodeExecutable"];
  allow_dangerously_skip_permissions?: ClaudeAgentOptions["allowDangerouslySkipPermissions"];
  permission_prompt_tool_name?: ClaudeAgentOptions["permissionPromptToolName"];
  plugins?: ClaudeAgentOptions["plugins"];
  resume_session_at?: ClaudeAgentOptions["resumeSessionAt"];
  setting_sources?: ClaudeAgentOptions["settingSources"];
  strict_mcp_config?: ClaudeAgentOptions["strictMcpConfig"];
}

export interface Session {
  session_id: string;
  title: string;
  cwd: string;
  created_at: Date;
  updated_at: Date;
  messages: Record<string, unknown>[];
}

export interface SessionSummary {
  session_id: string;
  title: string;
  cwd: string;
  created_at: Date;
  updated_at: Date;
  message_count: number;
}

// Message content can be a string or an array of content blocks
export type MessageContent = string | Array<{
  type: "text";
  text: string;
} | {
  type: "image";
  source: {
    type: "base64";
    media_type: "image/jpeg" | "image/png" | "image/gif" | "image/webp";
    data: string;
  };
}>;

export interface ChatRequest extends ClaudeChatOptionsPayload {
  session_id?: string;
  cwd?: string;
  message: MessageContent;
  permission_mode?: PermissionMode;
  system_prompt?: SystemPrompt;
}

export interface StopChatRequest {
  run_id: string;
}

export interface CodexChatRequest {
  session_id?: string;
  cwd?: string;
  message: string;
  approval_policy?: ApprovalMode;
  sandbox_mode?: SandboxMode;
  skip_git_repo_check?: boolean;
  model?: string;
  model_reasoning_effort?: ModelReasoningEffort;
  network_access_enabled?: boolean;
  web_search_enabled?: boolean;
}

export interface LoadSessionsRequest {
  claude_dir?: string;
}

export interface UserSettingsRequest {
  permission_mode: PermissionMode;
  system_prompt?: SystemPrompt;
}

export interface UserSettings extends UserSettingsRequest {
  user_id: string;
}

export interface CodexUserSettingsRequest {
  approval_policy?: ApprovalMode;
  sandbox_mode?: SandboxMode;
  model?: string;
  model_reasoning_effort?: ModelReasoningEffort;
  network_access_enabled?: boolean;
  web_search_enabled?: boolean;
  skip_git_repo_check?: boolean;
}

export interface CodexUserSettings extends CodexUserSettingsRequest {
  user_id: string;
}

export interface SessionFileMetadata {
  session_id: string;
  title: string;
  cwd: string;
  created_at: Date;
  updated_at: Date;
  parent_session_id?: string | null;
  is_agent_run: boolean;
}

export function defaultSystemPrompt(): Record<string, string> {
  return { type: "preset", preset: "claude_code" };
}

export function defaultCodexUserSettings(userId: string): CodexUserSettings {
  return {
    user_id: userId,
    approval_policy: "on-request",
    sandbox_mode: "read-only",
    model_reasoning_effort: "medium",
    network_access_enabled: false,
    web_search_enabled: false,
    skip_git_repo_check: false,
  };
}
