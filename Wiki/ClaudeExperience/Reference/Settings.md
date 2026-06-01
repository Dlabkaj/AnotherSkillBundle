# Settings Reference

**Summary**: Where `settings.json` lives, how scopes resolve, the keys that actually move the needle (permissions, hooks, env, model, autoMode), live-reload behavior, and the sandbox block. Use this when locking down a managed deployment or debugging "my setting isn't taking effect."

**Sources**: https://code.claude.com/docs/en/settings

**Last updated**: 2026-05-24

---

## Scopes and priority

| Scope | Location | Affects | Shared with team |
| --- | --- | --- | --- |
| Managed | Server-managed, MDM/OS policy, or `managed-settings.json` | All users on machine | Yes (deployed by IT) |
| User | `~/.claude/settings.json` | You, across all projects | No |
| Project | `.claude/settings.json` | All collaborators | Yes (in VCS) |
| Local | `.claude/settings.local.json` | You, this repo only | No (auto-gitignored) |

**Priority (highest → lowest)**: Managed → CLI args → Local → Project → User. Managed cannot be overridden. **Permission rules merge across scopes** rather than override. (source: https://code.claude.com/docs/en/settings)

## Managed delivery mechanisms

All use the same JSON format; cannot be overridden.

- **Server-managed**: Anthropic Claude.ai admin console
- **macOS MDM**: `com.anthropic.claudecode` managed preferences domain
- **Windows MDM**: `HKLM\SOFTWARE\Policies\ClaudeCode` (Settings JSON value); per-user under `HKCU\SOFTWARE\Policies\ClaudeCode`
- **File-based**: `/Library/Application Support/ClaudeCode/` (macOS), `/etc/claude-code/` (Linux/WSL), `C:\Program Files\ClaudeCode\` (Windows)
- **Drop-in directory**: `managed-settings.d/` with `*.json` files — alphabetically sorted, later files override earlier scalars, arrays concatenate, objects deep-merge

(source: https://code.claude.com/docs/en/settings)

## Live reload vs restart-required

Reload without restart:
- `permissions`
- `hooks`
- `apiKeyHelper` and credential helpers
- Fires `ConfigChange` hook on detection

**Read once at startup** (require restart):
- `model` — use `/model` to switch mid-session
- `outputStyle` — rebuild on `/clear` or restart

(source: https://code.claude.com/docs/en/settings)

## Key categories (selected)

### Core

| Key | Effect |
| --- | --- |
| `agent` | Run main thread as named subagent |
| `alwaysThinkingEnabled` | Extended thinking on by default |
| `apiKeyHelper` | Script to generate auth value (sent as both `X-Api-Key` and `Authorization: Bearer`) |
| `attribution` | Customize git commit/PR attribution (`{"commit": "...", "pr": "..."}`) |
| `autoMemoryEnabled` | Auto memory (default: true) |
| `autoMemoryDirectory` | Custom auto memory directory |
| `autoMode` | Customize auto-mode classifier — `environment`, `allow`, `soft_deny`, `hard_deny` arrays |
| `autoUpdatesChannel` | `"stable"` or `"latest"` (default) |
| `availableModels` | Restrict which models user can pick |
| `cleanupPeriodDays` | Session file retention (default 30, min 1) |
| `companyAnnouncements` | Cycled startup messages |
| `defaultShell` | `"bash"` (default) or `"powershell"` for `!` commands |
| `editorMode` | `"normal"` or `"vim"` |
| `effortLevel` | Persist effort: `low` / `medium` / `high` / `xhigh` (NO `max` — session-only) |
| `env` | Env vars applied to every session |
| `model` | Override default model |
| `modelOverrides` | Map Anthropic model IDs → provider-specific (Bedrock ARNs etc.) |
| `outputStyle` | Adjust system prompt style |
| `respectGitignore` | File picker respects `.gitignore` (default: true) |
| `useAutoModeDuringPlan` | Use auto-mode semantics in plan mode (default: true) |

(source: https://code.claude.com/docs/en/settings)

### Permissions

| Key | Effect |
| --- | --- |
| `allow` / `ask` / `deny` | Permission rule arrays. Evaluated **deny → ask → allow**, first match wins |
| `additionalDirectories` | Extra working dirs for file access (grants access only — NOT scanned for subagents) |
| `defaultMode` | Initial mode: `default` / `acceptEdits` / `plan` / `auto` / `dontAsk` / `bypassPermissions` |
| `disableBypassPermissionsMode` | Set `"disable"` to prevent bypass mode |
| `skipDangerousModePermissionPrompt` | Skip bypass-mode confirmation (ignored at project scope) |
| `allowManagedPermissionRulesOnly` | (Managed) Only managed permission rules apply |

(source: https://code.claude.com/docs/en/settings)

### Permission rule syntax

Format: `Tool` or `Tool(specifier)`. Order: deny → ask → allow. First match wins.

| Rule | Effect |
| --- | --- |
| `Bash` | All Bash commands |
| `Bash(npm run *)` | Commands starting with `npm run` |
| `Read(./.env)` | Reading `.env` file |
| `WebFetch(domain:example.com)` | Fetches to example.com |

Bare tool denies invalidate the cache; scoped denies don't. See [[ClaudeExperience/AntiPatterns/CacheChurn]]. (source: https://code.claude.com/docs/en/settings)

### Hooks

| Key | Effect |
| --- | --- |
| `hooks` | Hook config (see [[ClaudeExperience/Workflows/Hooks]]) |
| `allowedHttpHookUrls` | Allowlist URL patterns for HTTP hooks (supports `*`) |
| `allowManagedHooksOnly` | (Managed) Only managed/SDK/plugin hooks loaded |
| `disableAllHooks` | Disable all hooks + custom status line |
| `httpHookAllowedEnvVars` | Allowlist env var names HTTP hooks may interpolate |

(source: https://code.claude.com/docs/en/settings)

### MCP

| Key | Effect |
| --- | --- |
| `allowedMcpServers` | (Managed) Allowlist |
| `allowManagedMcpServersOnly` | (Managed) Only the allowlist applies |
| `deniedMcpServers` | (Managed) Denylist — takes precedence |
| `disabledMcpjsonServers` | Reject specific servers from `.mcp.json` |
| `enableAllProjectMcpServers` | Auto-approve all `.mcp.json` servers |
| `enabledMcpjsonServers` | Pre-approve specific `.mcp.json` servers |

(source: https://code.claude.com/docs/en/settings)

### Plugin / marketplace (managed only)

`allowedChannelPlugins`, `blockedMarketplaces`, `pluginTrustMessage`, `strictKnownMarketplaces`, `strictPluginOnlyCustomization`. (source: https://code.claude.com/docs/en/settings)

### Advanced (selected)

| Key | Effect |
| --- | --- |
| `claudeMd` | (Managed) Org-wide CLAUDE.md instructions |
| `claudeMdExcludes` | Glob patterns of CLAUDE.md files to skip |
| `disableAutoMode` | `"disable"` to prevent auto-mode activation |
| `disableSkillShellExecution` | Disable inline shell exec in skills |
| `disableRemoteControl` | v2.1.128+ — disable Remote Control |
| `includeGitInstructions` | Include git workflow in system prompt (default: true) |
| `maxSkillDescriptionChars` | Per-skill description cap (v2.1.105+, default 1536) |
| `minimumVersion` | Floor preventing downgrade |
| `parentSettingsBehavior` | (Managed, v2.1.133+) `"first-wins"` or `"merge"` |
| `policyHelper` | (Managed, v2.1.136+) Admin executable computing managed settings at startup |
| `skillListingBudgetFraction` | Context fraction for skill listing (v2.1.105+, default 0.01) |
| `skillOverrides` | Per-skill visibility (v2.1.129+): `on` / `name-only` / `user-invocable-only` / `off` |
| `skipWebFetchPreflight` | Skip WebFetch domain safety check |
| `statusLine` | Custom status line |
| `teammateDefaultModel` | Default model for agent-team teammates |
| `teammateMode` | `auto` / `in-process` / `tmux` |

(source: https://code.claude.com/docs/en/settings)

## Worktree settings

| Key | Effect |
| --- | --- |
| `worktree.baseRef` | `"fresh"` (default) or `"head"` — which ref worktrees branch from |
| `worktree.symlinkDirectories` | Symlink these directories from main repo into worktree |
| `worktree.sparsePaths` | Sparse-checkout these |
| `worktree.bgIsolation` | (v2.1.143+) `"worktree"` (default) or `"none"` for background sessions |

(source: https://code.claude.com/docs/en/settings)

## Sandbox (macOS / Linux / WSL2)

```json
{
  "sandbox": {
    "enabled": true,
    "failIfUnavailable": true,
    "autoAllowBashIfSandboxed": true,
    "excludedCommands": ["docker *"],
    "filesystem": {
      "allowWrite": ["/tmp/build", "~/.kube"],
      "denyWrite": ["/etc", "/usr/local/bin"],
      "denyRead": ["~/.aws/credentials"],
      "allowRead": ["."],
      "allowManagedReadPathsOnly": false
    },
    "network": {
      "allowUnixSockets": ["~/.ssh/agent-socket"],
      "allowLocalBinding": false,
      "allowedDomains": ["github.com", "*.npmjs.org"],
      "deniedDomains": ["sensitive.cloud.example.com"],
      "httpProxyPort": 8080,
      "socksProxyPort": 8081
    },
    "bwrapPath": "/opt/admin/bwrap",
    "socatPath": "/opt/admin/socat"
  }
}
```

Path prefixes: `~/` home, `/` absolute, `.` project root. Globs supported in deny rules. (source: https://code.claude.com/docs/en/settings)

## Other config files

| File | Purpose |
| --- | --- |
| `~/.claude.json` | OAuth session, MCP server configs, per-project state, caches. Auto-backed up with timestamps (keeps 5 most recent) |
| `.claude/settings.local.json` | Auto-configured as gitignored |

(source: https://code.claude.com/docs/en/settings)

## Common env vars

Set via `env:` key in settings:

```
CLAUDE_CODE_ENABLE_TELEMETRY=1
CLAUDE_CODE_DISABLE_THINKING=1
CLAUDE_CODE_DISABLE_AUTO_MEMORY=1
CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY=1
CLAUDE_CODE_API_KEY_HELPER_TTL_MS=3600000
CLAUDE_CODE_SKIP_PROMPT_HISTORY=1
CLAUDE_CODE_USE_POWERSHELL_TOOL=1
CLAUDE_CODE_EFFORT_LEVEL=xhigh
DISABLE_AUTOUPDATER=1
```

(source: https://code.claude.com/docs/en/settings)

## Tip: JSON schema autocomplete

```json
{ "$schema": "https://json.schemastore.org/claude-code-settings.json" }
```

Gives you IDE autocomplete on the settings file. (source: https://code.claude.com/docs/en/settings)

## Related pages

- [[ClaudeExperience/Reference/PermissionModes]]
- [[ClaudeExperience/Reference/HookEvents]]
- [[ClaudeExperience/Reference/MCPConfig]]
- [[ClaudeExperience/Reference/ModelConfig]]
- [[ClaudeExperience/Reference/ClaudeMdLocations]]
- [[ClaudeExperience/Workflows/Hooks]]
- [[ClaudeExperience/AntiPatterns/CacheChurn]]
