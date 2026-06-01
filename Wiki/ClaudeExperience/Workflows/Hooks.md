# Workflow: Hooks

**Summary**: How to wire deterministic behavior into Claude Code. Hooks fire at lifecycle events; they can block tool calls, inject context, run async checks, or notify the terminal. Use them when you want enforcement that doesn't depend on Claude obeying CLAUDE.md.

**Sources**: https://code.claude.com/docs/en/hooks, https://code.claude.com/docs/en/hooks-guide, https://smartscope.blog/en/generative-ai/claude/claude-code-hooks-guide/

**Last updated**: 2026-05-25

---

## When to reach for a hook

- The rule is *non-negotiable* (security policy, formatting before commit, redact secrets).
- The check is *deterministic* (regex, schema, build status).
- You want Claude to know about state changes without prompting (`additionalContext`).
- You want a desktop notification when Claude is idle or asks for permission.

If the rule can drift or needs nuance, prefer a [[ClaudeExperience/GoodPractices/SkillsForProcedures|skill]] or [[ClaudeExperience/GoodPractices/EffectiveClaudeMd|CLAUDE.md]] entry — hooks are blunt.

## Lifecycle cadences

- **Session** — `SessionStart`, `SessionEnd`, `Setup`.
- **Turn** — `UserPromptSubmit`, `UserPromptExpansion`, `Stop`, `StopFailure`.
- **Agentic loop** — `PreToolUse`, `PermissionRequest`, `PermissionDenied`, `PostToolUse`, `PostToolUseFailure`, `PostToolBatch`.
- **Async / state** — `FileChanged`, `CwdChanged`, `ConfigChange`, `InstructionsLoaded`, `Notification`, `WorktreeCreate`, `WorktreeRemove`, `PreCompact`, `PostCompact`, `Elicitation`, `ElicitationResult`, `SubagentStart`, `SubagentStop`, `TeammateIdle`, `TaskCreated`, `TaskCompleted`.

Only `PreToolUse`, `UserPromptSubmit`, `UserPromptExpansion`, `PermissionRequest`, `PostToolBatch`, and `Stop` can **block** the action. `PostToolUse` cannot block — see [[ClaudeExperience/AntiPatterns/HookExitCodeConfusion]]. (source: https://code.claude.com/docs/en/hooks)

## Where to put hooks

- `~/.claude/settings.json` — all projects, local machine.
- `.claude/settings.json` — single project, checked in.
- `.claude/settings.local.json` — single project, not checked in.
- Plugin `hooks/hooks.json`.
- Inside skill / agent frontmatter (`hooks:` field).

## Handler types

- **command** — local script (default). Pick exec form with `args` for reliable env substitution.
- **http** — POST event JSON to a URL; receives same JSON schema back. Use `allowedEnvVars` to scope headers. HTTP status codes alone cannot block — must return 2xx with `hookSpecificOutput` body. (source: https://code.claude.com/docs/en/hooks-guide)
- **mcp_tool** — call an MCP server tool with templated input (`${tool_input.field}`).
- **prompt** — single-turn LLM evaluation. Default model: Haiku; override with `model`. Returns `{"ok": true/false, "reason": "..."}`. 30s timeout. On `Stop`/`SubagentStop`, `reason` is fed back to Claude so it keeps working. (source: https://code.claude.com/docs/en/hooks-guide)
- **agent** — multi-turn verification with tool access. Same `ok`/`reason` schema as `prompt`. 60s default timeout, up to 50 tool turns. Experimental. Use when verification needs filesystem inspection or shell commands. (source: https://code.claude.com/docs/en/hooks-guide)

(source: https://code.claude.com/docs/en/hooks)

## Decision control (PreToolUse)

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow|deny|ask|defer",
    "permissionDecisionReason": "...",
    "updatedInput": { "command": "modified" },
    "additionalContext": "Visible to Claude"
  }
}
```

`updatedInput` lets the hook rewrite the tool input before execution — useful for sanitizing commands or injecting flags. (source: https://code.claude.com/docs/en/hooks)

## Adding context without blocking

Any event can return `hookSpecificOutput.additionalContext`. Visible to Claude:
- `SessionStart` → start of conversation.
- `UserPromptSubmit` → alongside the submitted prompt.
- `PreToolUse` → before the tool runs.
- `PostToolUse` → next to the tool result.

(source: https://code.claude.com/docs/en/hooks)

## Matchers

- `"*"` — all (also `""` or omitted).
- `"Bash"` — exact name.
- `"Edit|Write"` — pipe-separated exact matches.
- `"mcp__.*"` — JS regex (for MCP tool names).

Event-specific matchers:
- `SessionStart` — `startup | resume | clear | compact`.
- `Setup` — `init | maintenance`.
- `SessionEnd` — `clear | resume | logout | other`.
- `Notification` — `permission_prompt | idle_prompt`.
- `SubagentStart/Stop` — agent type (`general-purpose`, `Explore`, ...).
- `FileChanged` — literal filename(s).
- `StopFailure` — `rate_limit | authentication_failed | ...`.

(source: https://code.claude.com/docs/en/hooks)

## Terminal notifications (v2.1.141+)

Return an OSC escape sequence in `terminalSequence` to flash window title / native notification:
- OSC 0/1/2: window titles
- OSC 9: iTerm2, Windows Terminal
- OSC 99: Kitty
- OSC 777: urxvt, Ghostty, Warp
- Bare BEL

Color/cursor/clipboard (OSC 52) sequences are rejected. (source: https://code.claude.com/docs/en/hooks)

## Filter by tool name AND arguments — `if` field (v2.1.85+)

`matcher` filters at the group level by tool name only. `if` uses [permission-rule syntax](https://code.claude.com/docs/en/permissions) (`Bash(git *)`, `Edit(*.ts)`) so the hook process only spawns when both the tool and its arguments match. For compound commands like `npm test && git push`, each subcommand is evaluated and the hook fires if any matches.

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Bash",
      "hooks": [{
        "type": "command",
        "if": "Bash(git *)",
        "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/check-git-policy.sh"
      }]
    }]
  }
}
```

`if` only works on tool events (`PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `PermissionDenied`). Adding it elsewhere silently disables the hook. (source: https://code.claude.com/docs/en/hooks-guide)

## Cookbook patterns

### Re-inject context after compaction

```json
{ "hooks": { "SessionStart": [{ "matcher": "compact",
  "hooks": [{ "type": "command",
    "command": "echo 'Reminder: use Bun, not npm. Current sprint: auth refactor.'" }] }] } }
```

stdout from any `SessionStart`/`UserPromptSubmit`/`PreToolUse`/`PostToolUse` command becomes Claude context. (source: https://code.claude.com/docs/en/hooks-guide)

### Auto-reload env vars per directory (direnv pattern)

`SessionStart` + `CwdChanged` both write to `$CLAUDE_ENV_FILE`, which Claude runs as a script preamble before every Bash command — so `cd`-driven env changes actually take effect:

```json
{ "hooks": {
  "SessionStart": [{ "hooks": [{ "type": "command", "command": "direnv export bash > \"$CLAUDE_ENV_FILE\"" }] }],
  "CwdChanged":   [{ "hooks": [{ "type": "command", "command": "direnv export bash > \"$CLAUDE_ENV_FILE\"" }] }]
} }
```

Works with devbox/nix too (`devbox shellenv`). Watch specific files instead with `FileChanged` + matcher like `".envrc|.env"`. (source: https://code.claude.com/docs/en/hooks-guide)

### Auto-approve ExitPlanMode (skip plan→implement prompt)

```json
{ "hooks": { "PermissionRequest": [{
  "matcher": "ExitPlanMode",
  "hooks": [{ "type": "command",
    "command": "echo '{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"allow\"}}}'" }]
}] } }
```

Hook keeps the current conversation — unlike the dialog, it cannot clear context and start fresh. Optionally set `updatedPermissions: [{type:"setMode", mode:"acceptEdits", destination:"session"}]` to switch modes on approve. **Keep matcher narrow** — `.*` or `""` auto-approves every permission prompt (writes, shell, the lot). (source: https://code.claude.com/docs/en/hooks-guide)

### Enforce tests on Stop (block turn completion until green)

```json
{ "hooks": { "Stop": [{ "hooks": [{ "type": "command",
  "command": "INPUT=$(cat); [ \"$(echo $INPUT | jq -r '.stop_hook_active')\" = 'true' ] && exit 0; npm test || exit 2" }] }] } }
```

`exit 2` blocks the turn and feeds the test failure back so Claude keeps working. The `stop_hook_active` check is mandatory — without it, the hook loops until Claude Code hits the 8-block cap and overrides it anyway. (source: https://smartscope.blog/en/generative-ai/claude/claude-code-hooks-guide/)

### Async session log (fire-and-forget at Stop)

```json
{ "hooks": { "Stop": [{ "hooks": [{ "type": "command",
  "command": "echo \"$(date): session completed\" >> ~/claude-work.log", "async": true }] }] } }
```

`"async": true` returns immediately — cannot block the turn. Use for logging, backups, notifications. Sync hooks gate the loop; async ones don't. (source: https://smartscope.blog/en/generative-ai/claude/claude-code-hooks-guide/)

### Audit ConfigChange

```json
{ "hooks": { "ConfigChange": [{ "matcher": "",
  "hooks": [{ "type": "command",
    "command": "jq -c '{timestamp: now | todate, source: .source, file: .file_path}' >> ~/claude-config-audit.log" }] }] } }
```

Matcher filters by source: `user_settings | project_settings | local_settings | policy_settings | skills`. Exit 2 (or `{"decision":"block"}`) blocks the change. (source: https://code.claude.com/docs/en/hooks-guide)

## Stop hook block cap

`Stop` hooks that return `block` are auto-overridden after **8 consecutive blocks without progress** to prevent runaway loops. Your script should parse `stop_hook_active` from stdin and exit 0 when true:

```bash
if [ "$(echo "$INPUT" | jq -r '.stop_hook_active')" = "true" ]; then exit 0; fi
```

Raise the cap with env var `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`. (source: https://code.claude.com/docs/en/hooks-guide)

## Hooks vs permission modes

PreToolUse hooks fire **before** the permission-mode check. A hook `deny` blocks the tool even in `bypassPermissions` / `--dangerously-skip-permissions`. Reverse is not true: a hook `allow` does **not** override settings-level deny rules. Hooks can tighten, not loosen. Also: managed-policy deny lists always trump hook `allow`. (source: https://code.claude.com/docs/en/hooks-guide)

## Timeouts (overridable with `timeout` seconds)

| Type                | Default                       |
| ------------------- | ----------------------------- |
| `command` / `http` / `mcp_tool` | 10 min (30s for `UserPromptSubmit`) |
| `prompt`            | 30s                           |
| `agent`             | 60s                           |

(source: https://code.claude.com/docs/en/hooks-guide)

## Kill switch

`"disableAllHooks": true` in a settings file. Managed-settings hooks still run unless `disableAllHooks` is set in managed settings too. The `/hooks` menu is read-only — edit the JSON to add/modify. (source: https://code.claude.com/docs/en/hooks-guide)

## Frontmatter `Stop` auto-converts to `SubagentStop`

A `Stop` hook defined inside skill or subagent frontmatter is rewritten to `SubagentStop` automatically — the parent session's Stop event is untouched. Put `Stop` in `settings.json` if you want it to fire at the top-level turn boundary. (source: https://smartscope.blog/en/generative-ai/claude/claude-code-hooks-guide/)

## Test a hook before wiring it up

Feed the event JSON via stdin and check the exit code:

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | ./my-hook.sh
echo $?
```

Toggle verbose mode in the TUI with **Ctrl+O** to see hook stdout/stderr live for `PreToolUse`/`PostToolUse`. (source: https://smartscope.blog/en/generative-ai/claude/claude-code-hooks-guide/)

## Sample: block destructive bash

```bash
#!/bin/bash
CMD=$(jq -r '.tool_input.command' < /dev/stdin)
if echo "$CMD" | grep -qE 'rm -rf|git push --force'; then
  jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"Destructive op blocked by policy"}}'
fi
exit 0
```

## Related pages

- [[ClaudeExperience/AntiPatterns/HookExitCodeConfusion]]
- [[ClaudeExperience/Reference/HookEvents]]
- [[ClaudeExperience/Reference/PermissionModes]]
- [[ClaudeExperience/GoodPractices/ProvideVerification]]
