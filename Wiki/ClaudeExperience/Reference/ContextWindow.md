# Context Window

**Summary**: What loads into Claude Code's context before you type, what each operation costs, what survives `/compact`. Use this when budgeting tokens or debugging "Claude forgot X".

**Sources**: https://code.claude.com/docs/en/context-window

**Last updated**: 2026-05-24

---

## Pre-prompt — loaded before your first message

| Item | Approx tokens | Notes |
| --- | --- | --- |
| System prompt | ~4,200 | Core instructions, tool use, response formatting. Always first. Never visible. |
| Auto memory `MEMORY.md` | ~680 | First 200 lines or 25KB, whichever first |
| Environment info | ~280 | cwd, platform, shell, OS version, git-repo flag |
| Git status block | (varies) | Branch, status, recent commits — appears at very end of system prompt |
| MCP tools (deferred) | ~120 | Names only by default. Schemas load on demand via tool search. `ENABLE_TOOL_SEARCH=auto` loads schemas upfront when they fit within 10% of context; `=false` loads everything |
| Skill descriptions | ~450 | One-line per skill. Skills with `disable-model-invocation: true` are excluded. **NOT re-injected after `/compact` — only skills you actually invoked are preserved** |
| `~/.claude/CLAUDE.md` | ~320 | Your global preferences |
| Project `CLAUDE.md` | ~1,800 | Keep under 200 lines; move reference content to skills or path-scoped rules |

(source: https://code.claude.com/docs/en/context-window)

## During a working session

| Item | Approx tokens | Notes |
| --- | --- | --- |
| Your prompt | ~45 | Shown in terminal in full |
| File read | ~2,400 per medium file | You see "Read auth.ts"; the 2,400 tokens of content are Claude-only |
| Path-scoped rule load | ~380 | A rule in `.claude/rules/` with `paths:` matching a read file loads automatically |
| Grep results | ~600 | You see the command, not the output |
| Claude's analysis | ~800 | Visible in terminal |
| Edit (diff) | ~400 | Visible in terminal |
| `PostToolUse` hook output | ~120 | Only `hookSpecificOutput.additionalContext` enters context. **Plain stdout on exit 0 does NOT — debug log only.** Exit 2 surfaces stderr as error |

**File reads dominate context usage.** Be specific in prompts so Claude reads fewer files. For research-heavy tasks, use a subagent. (source: https://code.claude.com/docs/en/context-window)

## Bang commands `!cmd`

`!git status` runs in your shell and the command + output both enter context as part of your message. Useful for grounding Claude in command output without Claude running it (no tool call, no permission prompt). ~180 tokens for short output. (source: https://code.claude.com/docs/en/context-window)

## User-invoked skills (`disable-model-invocation: true`)

Description NOT in the startup skill index → **zero context cost** until invoked. On `/name`, full skill body loads. Use for skills with side effects (commit, deploy, send messages) so they stay out of context entirely until needed. (source: https://code.claude.com/docs/en/context-window)

## Subagent delegation (separate context window)

When Claude spawns a subagent:

- Subagent gets its own (shorter) system prompt + environment details.
- Main session's auto memory is **NOT** included. Custom agents with `memory:` load their own separate `MEMORY.md`.
- Subagent loads CLAUDE.md (same file) — but it counts against the subagent's context, not yours. **Built-in `Explore` and `Plan` skip CLAUDE.md.**
- Same MCP servers and skills available, minus plan-mode controls, background-task tools, and by default the `Agent` tool itself (prevents recursion).
- Subagent file reads fill the subagent's context, not yours.
- Only the subagent's final text response returns to your context, plus a small metadata trailer (token counts, duration).

**Concrete example from the docs**: subagent read 6,100 tokens of files, you got a 420-token result. That's the savings. (source: https://code.claude.com/docs/en/context-window)

## What survives `/compact`

| Mechanism | After compaction |
| --- | --- |
| System prompt and output style | Unchanged (not part of message history) |
| Project-root `CLAUDE.md` + unscoped rules | Re-injected from disk |
| Auto memory | Re-injected from disk |
| Rules with `paths:` frontmatter | **LOST** until a matching file is read again |
| Nested `CLAUDE.md` in subdirectories | **LOST** until a file in that subdirectory is read again |
| Invoked skill bodies | Re-injected, **5,000 tokens/skill, 25,000 tokens total cap**; oldest dropped first |
| Hooks | N/A — hooks run as code, not context |

(source: https://code.claude.com/docs/en/context-window)

### Implications

- **If a rule must persist across compaction**, drop the `paths:` frontmatter or move it to project-root `CLAUDE.md`.
- **Truncation keeps the START of the file** for skills → put the most important instructions near the top of `SKILL.md`. See [[ClaudeExperience/AntiPatterns/BloatedSkillBody]].

## What `/compact` keeps in the summary

- Your requests and intent
- Key technical concepts
- Files examined or modified with important code snippets
- Errors and how they were fixed
- Pending tasks
- Current work

**Discarded**: full tool outputs and intermediate reasoning. Claude can still reference earlier work but won't have the exact code it read. (source: https://code.claude.com/docs/en/context-window)

## Inspecting your own session

- `/context` — live breakdown by category with optimization suggestions.
- `/memory` — which CLAUDE.md and auto memory files loaded at startup.

(source: https://code.claude.com/docs/en/context-window)

## Related pages

- [[ClaudeExperience/Reference/PromptCaching]]
- [[ClaudeExperience/Reference/AutoMemory]]
- [[ClaudeExperience/Reference/ClaudeMdLocations]]
- [[ClaudeExperience/GoodPractices/ManageContext]]
- [[ClaudeExperience/AntiPatterns/InfiniteExploration]]
- [[ClaudeExperience/AntiPatterns/BloatedSkillBody]]
- [[ClaudeExperience/Workflows/Subagents]]
