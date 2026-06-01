# MCP Configuration Reference

**Summary**: `.mcp.json` schema, env var expansion syntax, environment variables that control MCP behavior, the OAuth-related fields, and version-gated features.

**Sources**: https://code.claude.com/docs/en/mcp

**Last updated**: 2026-05-24

---

## Config files

| File                     | Scope    | Notes                                            |
| ------------------------ | -------- | ------------------------------------------------ |
| `.mcp.json` (project root)| project | Committed to VCS. Approval prompt on first use   |
| `~/.claude.json`         | user, local | Both scopes co-exist in this file              |

In JSON config, `type` accepts `streamable-http` as an alias for `http`. (source: https://code.claude.com/docs/en/mcp)

## Env var expansion in `.mcp.json`

Syntax:

- `${VAR}` — required; parse fails if unset.
- `${VAR:-default}` — falls back to `default` if unset.

Expands in: `command`, `args`, `env`, `url`, `headers`. (source: https://code.claude.com/docs/en/mcp)

```json
{
  "mcpServers": {
    "api-server": {
      "type": "http",
      "url": "${API_BASE_URL:-https://api.example.com}/mcp",
      "headers": { "Authorization": "Bearer ${API_KEY}" }
    }
  }
}
```

## Environment variables that affect MCP

| Var                       | Effect                                                                  |
| ------------------------- | ----------------------------------------------------------------------- |
| `MCP_TIMEOUT`             | Server startup timeout                                                  |
| `MAX_MCP_OUTPUT_TOKENS`   | Per-tool output cap (default 25,000; warns at 10,000)                   |
| `ENABLE_TOOL_SEARCH`      | `true` / `auto` / `auto:N` / `false` (see [[ClaudeExperience/Workflows/MCP]]) |

`CLAUDE_PROJECT_DIR` is set in spawned stdio server env, not consumed by Claude Code itself. (source: https://code.claude.com/docs/en/mcp)

## Per-server config fields

| Field                      | Type    | Notes                                                                              |
| -------------------------- | ------- | ---------------------------------------------------------------------------------- |
| `type`                     | string  | `http` (or `streamable-http`), `sse`, `stdio`                                      |
| `url`                      | string  | http/sse only                                                                      |
| `command`, `args`          | strings | stdio only                                                                         |
| `env`                      | object  | stdio only                                                                         |
| `headers`                  | object  | http/sse; supports env var expansion                                               |
| `timeout`                  | number  | Per-server tool execution timeout, **milliseconds**                                |
| `alwaysLoad`               | bool    | v2.1.121+. Exempt this server from Tool Search deferral                            |
| `authServerMetadataUrl`    | string  | Override OAuth discovery chain                                                     |
| `oauth.scopes`             | array   | Pin requested OAuth scopes to subset                                               |
| `headersHelper`            | object  | Shell command returning headers at connection time (non-OAuth auth)                |

(source: https://code.claude.com/docs/en/mcp)

## Reconnection / retry behavior

| Phase                  | Behavior                                                                    |
| ---------------------- | --------------------------------------------------------------------------- |
| Initial connect        | 3 retries on 5xx / connection-refused / timeout (v2.1.121+). No retry on auth or 404 |
| HTTP/SSE mid-session   | Exponential backoff, 5 attempts (1s → 16s). Then marked failed              |
| Stdio mid-session      | **No auto-reconnect.** Process death is permanent for the session           |

(source: https://code.claude.com/docs/en/mcp)

## list_changed notification

Servers can push tool/prompt/resource updates dynamically without forcing disconnect/reconnect — Claude Code honors MCP `list_changed` notifications. (source: https://code.claude.com/docs/en/mcp)

## Truncation thresholds

| Field                       | Limit                          |
| --------------------------- | ------------------------------ |
| Tool description            | 2 KB                           |
| Server `instructions`       | 2 KB                           |
| Tool output (default cap)   | 25,000 tokens                  |
| Tool output (warning)       | 10,000 tokens                  |
| Server-author per-tool ceiling | 500,000 chars (`_meta["anthropic/maxResultSizeChars"]`) |

(source: https://code.claude.com/docs/en/mcp)

## Plugin-provided MCP servers

Plugins can bundle `.mcp.json` at the plugin root or define servers inline in `plugin.json`. They start when the plugin is enabled and appear alongside manually configured servers. Manage them through plugin commands, not `/mcp`. (source: https://code.claude.com/docs/en/mcp)

## Related pages

- [[ClaudeExperience/Workflows/MCP]]
- [[ClaudeExperience/AntiPatterns/MCPPromptInjection]]
- [[ClaudeExperience/AntiPatterns/CacheChurn]]
- [[ClaudeExperience/Reference/PermissionModes]]
