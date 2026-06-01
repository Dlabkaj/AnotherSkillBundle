# Auto Memory

**Summary**: A second memory system, complementary to CLAUDE.md. Claude writes notes for itself (build commands, debugging insights, preferences); a small index loads every session, detail files load on demand.

**Sources**: https://code.claude.com/docs/en/memory

**Last updated**: 2026-05-23

---

## CLAUDE.md vs auto memory

|                      | CLAUDE.md             | Auto memory                                |
| -------------------- | --------------------- | ------------------------------------------ |
| Who writes it        | You                   | Claude                                     |
| Contains             | Instructions, rules   | Learnings, patterns                        |
| Scope                | Project / user / org  | Per repository, shared across worktrees    |
| Loaded               | Every session, full   | First 200 lines or 25KB of MEMORY.md only  |
| Use for              | Coding standards, project layout, "always do X" | Build commands, debugging notes, preferences Claude discovers |

(source: https://code.claude.com/docs/en/memory)

Subagents can maintain their own auto memory.

## Storage

Per-project directory: `~/.claude/projects/<project>/memory/`. The `<project>` slug is derived from the git repo, so all worktrees and subdirectories of the same repo share one auto memory directory. Auto memory is machine-local — not shared across machines or cloud environments. (source: https://code.claude.com/docs/en/memory)

```
~/.claude/projects/<project>/memory/
├── MEMORY.md          # Concise index, loaded every session
├── debugging.md       # Detail file, loaded on demand
└── api-conventions.md
```

Relocate with `autoMemoryDirectory` in `~/.claude/settings.json`.

## Load behavior

- `MEMORY.md`: first 200 lines or 25KB (whichever comes first) load at session start. Anything past that does not auto-load.
- Topic files (`debugging.md`, etc.): not loaded at startup. Claude reads them on demand using its standard file tools.
- Implication: keep `MEMORY.md` as a thin index pointing to detail files. Don't dump everything inline.

## Controls

- Toggle per session: `/memory` (also lists CLAUDE.md / CLAUDE.local.md / rules files and links the auto memory folder).
- Project-level disable: `"autoMemoryEnabled": false` in settings.
- Machine-level disable: env var `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`.
- Requires Claude Code v2.1.59 or later.

## What Claude saves vs not

Claude does not save every session. It decides what's worth remembering based on whether the information would be useful in a future conversation (source: https://code.claude.com/docs/en/memory). When you explicitly say "always use pnpm, not npm" or "remember the API tests need a local Redis instance," it lands in auto memory by default — say "add this to CLAUDE.md" if you want it in the project file instead.

## Audit

Auto memory files are plain markdown — edit or delete them at any time. `/memory` opens the folder.

## Related pages

- [[ClaudeExperience/Reference/ClaudeMdLocations]]
- [[ClaudeExperience/GoodPractices/EffectiveClaudeMd]]
- [[ClaudeExperience/Reference/ProjectRules]]
