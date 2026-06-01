# Hook Events Reference

**Summary**: Data sheet of Claude Code hook events, when they fire, whether they can block, and the JSON I/O schema.

**Sources**: https://code.claude.com/docs/en/hooks, https://code.claude.com/docs/en/hooks-guide

**Last updated**: 2026-05-24

---

## Core lifecycle events

| Event                | When it fires                                      | Can block? |
| -------------------- | -------------------------------------------------- | ---------- |
| `SessionStart`       | Session begins or resumes                          | No         |
| `Setup`              | `--init-only` or `--init / --maintenance` in `-p`  | No         |
| `UserPromptSubmit`   | Before Claude processes user prompt                | Yes        |
| `UserPromptExpansion`| Before slash command expands                       | Yes        |
| `PreToolUse`         | Before tool call executes                          | Yes        |
| `PermissionRequest`  | Permission dialog appears                          | Yes        |
| `PermissionDenied`   | Tool call denied by auto-mode classifier           | No         |
| `PostToolUse`        | After tool call succeeds                           | No         |
| `PostToolUseFailure` | After tool call fails                              | No         |
| `PostToolBatch`      | After parallel tool batch resolves                 | Yes        |
| `Stop`               | Claude finishes responding                         | Yes        |
| `SessionEnd`         | Session terminates                                 | No         |

Additional async / state events (no block): `SubagentStart`, `SubagentStop`, `TeammateIdle`, `TaskCreated`, `TaskCompleted`, `PreCompact`, `PostCompact`, `Elicitation`, `ElicitationResult`, `Notification`, `CwdChanged`, `FileChanged`, `WorktreeCreate`, `WorktreeRemove`, `InstructionsLoaded`, `ConfigChange`, `StopFailure`. (source: https://code.claude.com/docs/en/hooks)

## Common JSON input fields

```json
{
  "session_id": "abc123",
  "transcript_path": "/path/to/transcript.jsonl",
  "cwd": "/current/working/directory",
  "permission_mode": "default",
  "hook_event_name": "PreToolUse",
  "effort": { "level": "high" },
  "agent_id": "subagent-123",
  "agent_type": "Explore"
}
```

(source: https://code.claude.com/docs/en/hooks)

## PreToolUse-specific input

```json
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "npm test",
    "description": "Run test suite",
    "timeout": 120000,
    "run_in_background": false
  },
  "tool_use_id": "abc-123-def"
}
```

## PostToolUse-specific input

Adds:
```json
{
  "tool_result": "File written successfully"
}
```

## Output schema

```json
{
  "continue": true,
  "stopReason": "...",
  "suppressOutput": false,
  "systemMessage": "Warning to user",
  "terminalSequence": "\033]777;notify;Title;Body\007",
  "decision": "block",
  "reason": "Why blocked",
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Policy violation",
    "additionalContext": "Context for Claude",
    "retry": true
  }
}
```

(source: https://code.claude.com/docs/en/hooks)

## Exit code table

| Code | Meaning              | Effect                                  |
| ---- | -------------------- | --------------------------------------- |
| `0`  | Success              | stdout JSON parsed                      |
| `2`  | Blocking error       | stdout/JSON ignored; stderr is shown    |
| other| Non-blocking error   | stderr logged; execution continues      |

Return JSON **or** non-zero exit code, never both. See [[ClaudeExperience/AntiPatterns/HookExitCodeConfusion]]. (source: https://code.claude.com/docs/en/hooks)

## `permissionDecision` values (PreToolUse)

- `allow` — approve without prompt.
- `deny` — block.
- `ask` — escalate to user prompt.
- `defer` — fall through to default permission rules.

(source: https://code.claude.com/docs/en/hooks)

## Handler config shape

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/validate.sh",
            "args": [],
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

Per-handler fields:

- `type`: `command | http | mcp_tool | prompt | agent`
- `command` + `args`: exec form (preferred for env substitution)
- `command` only: shell form (`sh -c` on Unix, PowerShell on Windows)
- `timeout`: seconds; defaults vary by type — `command`/`http`/`mcp_tool` 10 min (but `UserPromptSubmit` 30s), `prompt` 30s, `agent` 60s (source: https://code.claude.com/docs/en/hooks-guide)
- `if` (v2.1.85+): permission-rule pattern (`Bash(git *)`, `Edit(*.ts)`) — fires only when tool **and** argument match. Tool events only. (source: https://code.claude.com/docs/en/hooks-guide)
- `async`: don't gate the agentic loop
- `asyncRewake`: rewake Claude when this finishes (compaction-event friendly)
- `shell`: `bash` (default) or `powershell`

For HTTP handlers, add `url`, `headers`, `allowedEnvVars`. (source: https://code.claude.com/docs/en/hooks)

## Event-specific matchers (full set)

| Event                | Matcher values                                                                                  |
| -------------------- | ----------------------------------------------------------------------------------------------- |
| `SessionStart`       | `startup | resume | clear | compact`                                                            |
| `Setup`              | `init | maintenance`                                                                            |
| `SessionEnd`         | `clear | resume | logout | prompt_input_exit | bypass_permissions_disabled | other`             |
| `Notification`       | `permission_prompt | idle_prompt | auth_success | elicitation_dialog | elicitation_complete | elicitation_response` |
| `SubagentStart/Stop` | `general-purpose | Explore | Plan | <custom agent name>`                                        |
| `PreCompact/PostCompact` | `manual | auto`                                                                             |
| `ConfigChange`       | `user_settings | project_settings | local_settings | policy_settings | skills`                  |
| `StopFailure`        | `rate_limit | authentication_failed | oauth_org_not_allowed | billing_error | invalid_request | model_not_found | server_error | max_output_tokens | unknown` |
| `InstructionsLoaded` | `session_start | nested_traversal | path_glob_match | include | compact`                       |
| `FileChanged`        | literal filenames pipe-separated (NOT regex)                                                    |

(source: https://code.claude.com/docs/en/hooks-guide)

## Stop hook block cap

`Stop` hooks that return `block` are auto-overridden after **8 consecutive blocks without progress**. Parse `stop_hook_active` from stdin and exit 0 when true to allow stop. Env var `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` raises the cap. (source: https://code.claude.com/docs/en/hooks-guide)

## Hooks-vs-permissions precedence

- PreToolUse hook fires **before** the permission-mode check — a hook `deny` overrides `bypassPermissions` and `--dangerously-skip-permissions`.
- Hook `allow` does **not** bypass settings-level deny/ask rules. Managed-policy deny lists always win.

(source: https://code.claude.com/docs/en/hooks-guide)

## Global disable

`"disableAllHooks": true` in any settings file. Managed-policy hooks still run unless that file also sets it. `/hooks` menu is read-only — edit JSON directly. (source: https://code.claude.com/docs/en/hooks-guide)

## Related pages

- [[ClaudeExperience/Workflows/Hooks]]
- [[ClaudeExperience/AntiPatterns/HookExitCodeConfusion]]
- [[ClaudeExperience/Reference/PermissionModes]]
