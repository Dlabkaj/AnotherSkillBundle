# Workflow: MCP (Model Context Protocol)

**Summary**: How to connect Claude Code to external tools — issue trackers, dashboards, databases — via MCP servers. Three transports, three scopes, OAuth flow, Tool Search to keep context costs bounded.

**Sources**: https://code.claude.com/docs/en/mcp

**Last updated**: 2026-05-24

---

## When to add a server

You're copy-pasting data from another tool into chat (Jira ticket, Grafana panel, Postgres query result). Connect the server, ask Claude to read/act directly. (source: https://code.claude.com/docs/en/mcp)

## Three transports

| Transport      | Add command                                                          | Use when                                       |
| -------------- | -------------------------------------------------------------------- | ---------------------------------------------- |
| `http`         | `claude mcp add --transport http <name> <url>`                       | Remote cloud server (recommended)              |
| `sse`          | `claude mcp add --transport sse <name> <url>` (deprecated)           | Legacy SSE-only servers                        |
| `stdio`        | `claude mcp add --transport stdio --env K=V <name> -- <cmd> [args]` | Local process. Most npm-installed servers      |

**Option ordering trap**: all flags (`--transport`, `--env`, `--scope`, `--header`) MUST come BEFORE the server name. `--` then separates server name from command. (source: https://code.claude.com/docs/en/mcp)

`CLAUDE_PROJECT_DIR` is set in the spawned stdio server env so it can resolve project-relative paths. (source: https://code.claude.com/docs/en/mcp)

## Scopes — `--scope <local|project|user>`

| Scope    | Loads in             | Shared    | Stored in                   |
| -------- | -------------------- | --------- | --------------------------- |
| `local` (default) | Current project only | No        | `~/.claude.json`            |
| `project`| Current project only | Yes (VCS) | `.mcp.json` in project root |
| `user`   | All your projects    | No        | `~/.claude.json`            |

**Project-scope servers prompt for approval** before first use. Reset approvals: `claude mcp reset-project-choices`. (source: https://code.claude.com/docs/en/mcp)

### Precedence (same server name in multiple sources)

1. Local
2. Project
3. User
4. Plugin-provided
5. claude.ai connectors

Plugins/connectors match by endpoint, not name. (source: https://code.claude.com/docs/en/mcp)

## Management commands

```
claude mcp list
claude mcp get <name>
claude mcp remove <name>
/mcp           # in session; shows tool count per server, flags zero-tool servers
```

`/mcp` also handles OAuth re-auth when a server returns 401/403. (source: https://code.claude.com/docs/en/mcp)

## Auto-reconnect behavior

- **HTTP / SSE**: exponential backoff, up to 5 attempts (1s, 2s, 4s, 8s, 16s). After 5 failures → server marked failed.
- **Stdio**: NOT auto-reconnected. Local process death is permanent for the session.
- **Initial connect** (v2.1.121+): retried up to 3 times on transient errors (5xx, connection refused, timeout). Auth and 404 errors are NOT retried — they need a config change.

(source: https://code.claude.com/docs/en/mcp)

Every reconnect/disconnect [[ClaudeExperience/AntiPatterns/CacheChurn|invalidates the prompt cache]] because tool defs live in the system prompt layer.

## OAuth

Claude Code marks a remote server as needing auth when it returns 401/403.

- **`--callback-port <N>`**: fix the OAuth callback port when the server requires a pre-registered redirect URI (default: random free port).
- **Pre-configured credentials**: needed when server doesn't support Dynamic Client Registration. Symptom: "Incompatible auth server: does not support dynamic client registration."
- **`authServerMetadataUrl`**: bypass discovery chain (default: RFC 9728 `/.well-known/oauth-protected-resource` → RFC 8414 `/.well-known/oauth-authorization-server`).
- **`oauth.scopes`**: pin requested scopes to a security-approved subset.

(source: https://code.claude.com/docs/en/mcp)

### Non-OAuth auth — `headersHelper`

Returns request headers at connection time. Use for Kerberos, short-lived tokens, internal SSO. **Executes arbitrary shell** — at project/local scope it only runs after you accept the workspace trust dialog. (source: https://code.claude.com/docs/en/mcp)

## Tool Search — keep context low as you add servers

Tool definitions can dominate context if you connect many MCP servers. Tool Search defers loading: only tool names load at startup, full defs load only when Claude searches for them. Default: enabled.

Requires a model that supports `tool_reference` blocks: Sonnet 4+, Opus 4+. **Haiku does NOT support it.** (source: https://code.claude.com/docs/en/mcp)

### `ENABLE_TOOL_SEARCH` values

| Value          | Behavior                                                                          |
| -------------- | --------------------------------------------------------------------------------- |
| unset / `true` | All MCP tools deferred                                                            |
| `auto`         | Load upfront if ≤ 10% of context window, otherwise defer                          |
| `auto:N`       | Custom percentage threshold                                                       |
| `false`        | All tools loaded upfront, no deferral                                             |

### Exempt a server with `alwaysLoad: true`

For a small handful of tools Claude needs every turn. Each upfront tool consumes context the conversation could use — set sparingly. v2.1.121+. (source: https://code.claude.com/docs/en/mcp)

### MCP server author tips

`serverInstructions` becomes critical with Tool Search — it's the only signal Claude has to decide whether to search. Cover: what category of tasks, when to search, key capabilities. **Truncated at 2KB**, same for individual tool descriptions. (source: https://code.claude.com/docs/en/mcp)

## Reference resources with `@`

Format: `@server:protocol://resource/path`. Multiple per prompt.

```
Can you analyze @github:issue://123 and suggest a fix?
Compare @postgres:schema://users with @docs:file://database/user-model
```

(source: https://code.claude.com/docs/en/mcp)

## Run MCP-exposed prompts as slash commands

`/mcp__<server>__<prompt>` — e.g. `/mcp__github__list_prs`, `/mcp__github__pr_review 456`. (source: https://code.claude.com/docs/en/mcp)

## Output limits

- Warning at **10,000 tokens** per tool output.
- Default hard cap: **25,000 tokens** (override with `MAX_MCP_OUTPUT_TOKENS`).
- MCP server authors: raise per-tool persist threshold via `_meta["anthropic/maxResultSizeChars"]` in `tools/list` response, up to **500,000 chars** ceiling.

(source: https://code.claude.com/docs/en/mcp)

## Security checklist before adding a server

- **Verify trust**. Servers that fetch external content are a [[ClaudeExperience/AntiPatterns/MCPPromptInjection|prompt-injection vector]].
- For project-scope servers: read the approval prompt — it's the last gate before .mcp.json from someone else's commit runs in your session.
- Restrict OAuth scopes (`oauth.scopes`) to least privilege.
- `headersHelper` runs arbitrary shell — only enable on servers you fully control.

(source: https://code.claude.com/docs/en/mcp)

## Related pages

- [[ClaudeExperience/Reference/MCPConfig]]
- [[ClaudeExperience/AntiPatterns/MCPPromptInjection]]
- [[ClaudeExperience/AntiPatterns/CacheChurn]]
- [[ClaudeExperience/GoodPractices/SpecificContext]] — using `@server:` references in prompts
- [[ClaudeExperience/Reference/PermissionModes]]
