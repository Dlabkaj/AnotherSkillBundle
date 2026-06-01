# Subagent Frontmatter Reference

**Summary**: Data sheet for subagent definition files. Subagents live in `.claude/agents/` (project), `~/.claude/agents/` (user), plugin `agents/`, managed-settings `agents/`, or CLI `--agents` JSON. Only `name` and `description` are required.

**Sources**: https://code.claude.com/docs/en/sub-agents

**Last updated**: 2026-05-24

---

## File shape

```markdown
---
name: code-reviewer
description: Reviews code for quality and best practices
tools: Read, Glob, Grep
model: sonnet
---

You are a code reviewer. When invoked, analyze the code and provide
specific, actionable feedback on quality, security, and best practices.
```

YAML frontmatter + Markdown body. The body is the system prompt. Subagents receive only that prompt plus basic environment details — **not the full Claude Code system prompt**. (source: https://code.claude.com/docs/en/sub-agents)

## Scope and discovery

| Location | Scope | Priority | Notes |
| --- | --- | --- | --- |
| Managed settings `agents/` | Org-wide | 1 (highest) | Deployed by admins |
| `--agents` CLI JSON | Current session | 2 | JSON; no disk file |
| `.claude/agents/` | Current project | 3 | Check into VCS |
| `~/.claude/agents/` | All your projects | 4 | Personal |
| Plugin `agents/` | Where plugin enabled | 5 (lowest) | Scoped name |

Same name → higher priority wins. Project + user scopes scanned recursively; subfolder path does not affect the subagent identifier (identity is the `name` field). Plugin scopes DO use subfolders as scoped identifiers, e.g. `agents/review/security.md` in plugin `my-plugin` → `my-plugin:review:security`. (source: https://code.claude.com/docs/en/sub-agents)

`--add-dir` directories grant file access only — they are NOT scanned for subagents. To share across projects, use `~/.claude/agents/` or a plugin. (source: https://code.claude.com/docs/en/sub-agents)

## Supported frontmatter fields

| Field | Required | Description |
| --- | --- | --- |
| `name` | Yes | Lowercase + hyphens; unique within scope. Hooks see this as `agent_type` |
| `description` | Yes | When Claude should delegate to this subagent |
| `tools` | No | Allowlist. Inherits all tools if omitted. Use `skills:` instead of listing `Skill` here |
| `disallowedTools` | No | Denylist. Applied first; `tools` resolved against the remainder |
| `model` | No | `sonnet` / `opus` / `haiku` / full ID (`claude-opus-4-7`) / `inherit`. Default: `inherit` |
| `permissionMode` | No | `default` / `acceptEdits` / `auto` / `dontAsk` / `bypassPermissions` / `plan`. Ignored for plugin subagents |
| `maxTurns` | No | Max agentic turns before the subagent stops |
| `skills` | No | Skills preloaded at startup — **full skill content injected**, not just the description |
| `mcpServers` | No | Inline server defs or string refs to already-configured servers. Ignored for plugin subagents |
| `hooks` | No | Lifecycle hooks scoped to this subagent. Ignored for plugin subagents |
| `memory` | No | `user` / `project` / `local` — persistent agent-memory directory |
| `background` | No | `true` to always run as background task |
| `effort` | No | `low` / `medium` / `high` / `xhigh` / `max` — overrides session effort (model-dependent) |
| `isolation` | No | `worktree` → run in a temp git worktree branched from default branch |
| `color` | No | `red` / `blue` / `green` / `yellow` / `purple` / `orange` / `pink` / `cyan` |
| `initialPrompt` | No | Auto-submitted as first user turn when this agent runs as the main session via `--agent` |

(source: https://code.claude.com/docs/en/sub-agents)

**Plugin restriction**: plugin subagents ignore `hooks`, `mcpServers`, `permissionMode`. Copy the file to `.claude/agents/` or `~/.claude/agents/` if you need them. (source: https://code.claude.com/docs/en/sub-agents)

## Built-in subagents

| Agent | Model | Tools | Purpose |
| --- | --- | --- | --- |
| `Explore` | Haiku | Read-only | Fast file discovery / search. Specifies thoroughness: `quick` / `medium` / `very thorough` |
| `Plan` | Inherits | Read-only | Research during plan mode (prevents infinite nesting) |
| `general-purpose` | Inherits | All | Complex multi-step research + action |
| `statusline-setup` | Sonnet | — | Auto-invoked by `/statusline` |
| `claude-code-guide` | Haiku | — | Auto-invoked for Claude Code feature questions |

`Explore` and `Plan` are the only subagents that **skip CLAUDE.md and git status** at startup; every other built-in and custom subagent loads them. To override per-rule, restate the rule in your delegation prompt. (source: https://code.claude.com/docs/en/sub-agents)

## Model resolution order

1. `CLAUDE_CODE_SUBAGENT_MODEL` env var
2. Per-invocation `model` parameter from the parent
3. Subagent's `model` frontmatter
4. Main conversation's model

(source: https://code.claude.com/docs/en/sub-agents)

## CLI `--agents` JSON example

```bash
claude --agents '{
  "code-reviewer": {
    "description": "Expert code reviewer. Use proactively after code changes.",
    "prompt": "You are a senior code reviewer.",
    "tools": ["Read", "Grep", "Glob", "Bash"],
    "model": "sonnet"
  }
}'
```

Same fields as file frontmatter; `prompt` replaces the markdown body. (source: https://code.claude.com/docs/en/sub-agents)

## `Agent(...)` restriction syntax

When running as the main thread with `claude --agent`, an agent can spawn subagents via the Agent tool. Restrict to a whitelist:

```yaml
tools: Agent(worker, researcher), Read, Bash
```

`Agent` without parens = allow any subagent. Omit `Agent` entirely = the agent cannot spawn any subagents. (source: https://code.claude.com/docs/en/sub-agents)

> **Note**: As of v2.1.63, the Task tool was renamed to Agent. Existing `Task(...)` references still work as aliases.

## Persistent agent memory

`memory: user|project|local` enables a directory the subagent reads/writes across conversations.

| Scope | Path | Use when |
| --- | --- | --- |
| `user` | `~/.claude/agent-memory/<name>/` | Knowledge applies across all projects |
| `project` | `.claude/agent-memory/<name>/` | Project-specific; shareable via VCS (recommended default) |
| `local` | `.claude/agent-memory-local/<name>/` | Project-specific, never in VCS |

When enabled, Claude injects memory instructions into the subagent's system prompt and auto-enables Read/Write/Edit. The first 200 lines or 25KB of `MEMORY.md` (whichever first) is loaded, with curate instructions if exceeded. (source: https://code.claude.com/docs/en/sub-agents)

## Resume semantics

Each invocation creates a fresh instance. To continue, ask Claude to resume; Claude calls `SendMessage` with the agent's ID (available only when `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`). A stopped subagent that receives a `SendMessage` auto-resumes in the background.

Transcripts live at `~/.claude/projects/{project}/{sessionId}/subagents/agent-{agentId}.jsonl` — independent of the main conversation, so main compaction doesn't affect them. Cleanup follows `cleanupPeriodDays` (default 30). (source: https://code.claude.com/docs/en/sub-agents)

## Forks (`CLAUDE_CODE_FORK_SUBAGENT=1`, v2.1.117+)

A fork = a subagent that **inherits the full parent conversation** (system prompt, tools, model, message history). Drops input isolation but keeps output isolation. Cheaper than a fresh subagent because the first request reuses the parent's prompt cache.

When enabled:
- `general-purpose` spawns become forks
- All spawns run in background (override with `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1`)
- `/fork <directive>` spawns a fork on demand
- A fork cannot spawn further forks

Pass `isolation: "worktree"` so the fork's edits go to a temporary worktree, not your checkout. (source: https://code.claude.com/docs/en/sub-agents)

## Related pages

- [[ClaudeExperience/Workflows/Subagents]]
- [[ClaudeExperience/GoodPractices/UseSubagents]]
- [[ClaudeExperience/Workflows/MultipleSessionsFanout]]
- [[ClaudeExperience/Reference/PermissionModes]]
- [[ClaudeExperience/Workflows/Hooks]]
