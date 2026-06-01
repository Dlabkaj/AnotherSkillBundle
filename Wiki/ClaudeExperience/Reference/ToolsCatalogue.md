# Tools Catalogue — Behaviors and Traps

**Summary**: Per-tool quirks you actually hit in practice. The full catalogue is in the official docs; this page extracts only the actionable behaviors and traps relevant to Jakub's workflow.

**Sources**: https://code.claude.com/docs/en/tools-reference (https://code.claude.com/docs/en/tools-reference)

**Last updated**: 2026-05-24

---

## Permission rule format (deny → ask → allow, first match wins)

| Rule | Applies to | Notes |
| --- | --- | --- |
| `Bash(npm run *)` | Bash, Monitor | Command pattern |
| `PowerShell(Get-ChildItem *)` | PowerShell | Command pattern |
| `Read(~/secrets/**)` | Read, Grep, Glob, LSP | Path pattern |
| `Edit(/src/**)` | Edit, Write, NotebookEdit | Path pattern. **`Edit(...)` also grants Read for the same path** — no separate Read rule needed |
| `Skill(deploy *)` | Skill | Skill name |
| `Agent(Explore)` | Agent | Subagent type |
| `WebFetch(domain:example.com)` | WebFetch | Domain |
| `WebSearch` | WebSearch | No specifier — allow/deny the whole tool |

Hook `matcher` fields use **bare tool names** (no parentheses).

## Bash — gotchas

- `cd` **carries over** to later commands only while you stay inside the project / additional working dirs. Stepping out resets cwd; Claude Code appends `Shell cwd was reset to <dir>` to the tool result. Disable with `CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=1`.
- **Env vars do NOT persist** between commands. `export FOO=bar` in one call is gone in the next. Activate venv/conda **before** launching Claude Code.
- Default timeout **2 minutes**, max 10 minutes via `timeout` parameter.
- Default output cap **30,000 characters**. Overflow: full output saved to a file in the session dir, Claude gets the path + a short preview from the start.
- Long-running stuff (dev servers, watchers): use `run_in_background: true`.

## Edit — three checks must pass

1. **Read-before-edit**: Claude must have read the file in this conversation, and the file must not have changed on disk since that read. Checked **first**, before any string matching.
2. **Match**: `old_string` must appear **exactly** — single whitespace/indent char off and it misses.
3. **Uniqueness**: `old_string` must appear exactly once. Otherwise add surrounding context or use `replace_all: true`.

`cat`, `head`, `tail`, `sed -n 'X,Yp'` via Bash satisfy read-before-edit — but only on a single file with no pipes, redirects, or extra flags.

## Glob vs Grep — gitignore asymmetry (trap)

- **Glob does NOT respect `.gitignore`** by default → returns gitignored files alongside tracked ones. Override with `CLAUDE_CODE_GLOB_NO_IGNORE=false`.
- **Grep DOES respect `.gitignore`** → gitignored files skipped silently. To search one, pass its path directly.

They look symmetrical, they aren't. Bites when searching build output, node_modules, or `.env*` files.

Glob results are sorted by mtime and capped at 100 files.

Grep uses **ripgrep regex**, not POSIX. Literal braces need escaping: `interface\{\}` for Go's `interface{}`. Modes: `files_with_matches` (default), `content`, `count`. Set `multiline: true` for cross-line patterns.

## Read — partial views and file types

- Returns content with line numbers. Always pass **absolute paths**.
- Large files: returns the first page with a `PARTIAL view` notice telling Claude how much it got + how to continue with `offset` / `limit`.
- **Images** (PNG/JPG/...): returned as visual content; Claude Code resizes/recompresses large ones.
- **PDFs**: short ones whole; >10 pages must use `pages` parameter, max 20 pages per call.
- **Jupyter notebooks**: returns all cells with outputs.
- Files only, not directories.

## Write — read-before-overwrite

- Creates or overwrites with full content. Does NOT append/merge.
- Overwriting an existing file requires Claude to have **read it at least once this conversation**. Write to an unread existing file fails. New files are exempt.
- For partial changes use Edit, not Write.

## WebFetch — lossy by design

See [[ClaudeExperience/AntiPatterns/WebFetchAsRaw]].

- Auto-converts HTML → Markdown, then runs an extraction prompt through a small/fast model. **Claude receives that model's answer, not the raw page.** Conversion is not configurable.
- HTTP auto-upgrades to HTTPS.
- Large pages truncated to a fixed char limit before processing.
- Responses cached **15 minutes**.
- Cross-host redirect → WebFetch returns a text result naming original + redirect target instead of following. Claude must call WebFetch again on the new URL.
- First reach to a new domain prompts in `default`/`acceptEdits`. Pre-allow via `WebFetch(domain:example.com)`. `auto` / `bypassPermissions` skip the prompt.

For the unprocessed page, use `curl` via Bash.

## WebSearch

- Returns titles + URLs only. Does NOT fetch result pages — that needs a follow-up WebFetch.

## Agent / subagent tool inheritance

- Neither `tools` nor `disallowedTools` set → subagent inherits everything from parent.
- `tools` only → only the listed ones.
- `disallowedTools` only → everything except the listed ones.
- **Both set → `disallowedTools` wins** for any tool in both lists.

Subagent permission prompts:
- **Foreground**: prompts surface in the terminal like the main session.
- **Background**: NO prompts. Runs with already-granted permissions; any tool call that would prompt is **auto-denied** and the subagent keeps going without that tool.

## TodoWrite is deprecated

As of **v2.1.142**, `TodoWrite` is disabled by default in favor of `TaskCreate` / `TaskGet` / `TaskList` / `TaskUpdate`. Set `CLAUDE_CODE_ENABLE_TASKS=0` to re-enable the old behavior.

## Monitor tool — not everywhere

Lets Claude tail a log, poll CI, watch a directory, etc., feeding each output line back without pausing the conversation. Uses the same permission rules as Bash.

**Not available** on Amazon Bedrock, Google Vertex AI, Microsoft Foundry, or when `DISABLE_TELEMETRY` / `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` is set.

## Skills are not tools

Skills run through the existing `Skill` tool rather than adding a new tool entry. Adding a custom tool means connecting an MCP server, not writing a skill.

## Related pages

- [[ClaudeExperience/Reference/PermissionModes]]
- [[ClaudeExperience/Reference/HookEvents]]
- [[ClaudeExperience/Reference/SubagentFrontmatter]]
- [[ClaudeExperience/AntiPatterns/WebFetchAsRaw]]
