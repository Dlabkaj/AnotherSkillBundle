# CLAUDE.md Locations

**Summary**: Where Claude looks for CLAUDE.md files and which one applies in which scope. Multiple files compose; child directories load on demand. Managed policy files cannot be excluded by users.

**Sources**: https://code.claude.com/docs/en/best-practices, https://code.claude.com/docs/en/memory

**Last updated**: 2026-05-23

---

## Locations (load order: broad → specific)

| Path | Scope |
|------|-------|
| Managed policy: macOS `/Library/Application Support/ClaudeCode/CLAUDE.md`; Linux/WSL `/etc/claude-code/CLAUDE.md`; Windows `C:\Program Files\ClaudeCode\CLAUDE.md` | Organization-wide. Pushed by IT. Cannot be excluded by user settings. |
| `~/.claude/CLAUDE.md` | User-level — applies to all sessions on this machine. |
| `./CLAUDE.md` or `./.claude/CLAUDE.md` | Project — checked into git, team-shared. |
| `./CLAUDE.local.md` | Personal project notes — add to `.gitignore`. |
| Parent directories | Walked up from the working directory; useful for monorepos. |
| Child directories | Loaded on demand when Claude reads files in those directories. |

All discovered files are **concatenated** into context rather than overriding each other, ordered from filesystem root down to working directory. (source: https://code.claude.com/docs/en/memory)

## Imports

```
@AGENTS.md

# Additional Instructions
- git workflow @docs/git-instructions.md
- @~/.claude/my-project-instructions.md
```

- `@path` syntax expands the imported file into context at launch.
- Relative paths resolve to the file containing the import, not the working directory.
- Recursive imports allowed up to 5 hops.
- First time Claude Code encounters external imports in a project it shows an approval dialog; declining permanently disables them. (source: https://code.claude.com/docs/en/memory)

## AGENTS.md interop

Claude Code reads CLAUDE.md, **not** AGENTS.md. If your repo already uses AGENTS.md for other agents:

- Create a CLAUDE.md that imports AGENTS.md (`@AGENTS.md`) — both tools stay in sync without duplication.
- Or symlink: `ln -s AGENTS.md CLAUDE.md` (Linux/macOS). On Windows, symlinks need Admin or Developer Mode, so use the `@AGENTS.md` import.

## Excluding ancestor files

In large monorepos, ancestor CLAUDE.md files may not be relevant. Use `claudeMdExcludes` in settings:

```
{
  "claudeMdExcludes": [
    "**/monorepo/CLAUDE.md",
    "/home/user/monorepo/other-team/.claude/rules/**"
  ]
}
```

Managed policy CLAUDE.md cannot be excluded. (source: https://code.claude.com/docs/en/memory)

## Additional directories

`--add-dir` extends file access but does **not** load CLAUDE.md from those dirs by default. Opt in with:

```
CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1 claude --add-dir ../shared-config
```

## Compaction behavior

Project-root CLAUDE.md survives `/compact` — Claude re-reads it from disk and re-injects after compaction. Nested CLAUDE.md files in subdirectories are **not** auto-re-injected; they reload only when Claude next reads a file in that subdirectory. (source: https://code.claude.com/docs/en/memory)

If a rule "disappears" after `/compact`, it was either given only in conversation or it lives in a nested CLAUDE.md that hasn't reloaded yet.

## How CLAUDE.md is delivered

CLAUDE.md content is delivered as a **user message after the system prompt**, not part of the system prompt itself. Claude reads and tries to follow it, but adherence is best-effort, especially for vague or conflicting instructions. (source: https://code.claude.com/docs/en/memory) For hard guarantees, use hooks or settings, not CLAUDE.md.

## Reminders

- Treat it like code: review when things go wrong, prune regularly, test by observing whether Claude's behavior actually shifts.
- Bloat causes rules to be ignored — see [[ClaudeExperience/AntiPatterns/OverSpecifiedClaudeMd]].
- For modular per-path instructions, use [[ClaudeExperience/Reference/ProjectRules]] instead of stuffing CLAUDE.md.

## Related pages

- [[ClaudeExperience/GoodPractices/EffectiveClaudeMd]]
- [[ClaudeExperience/AntiPatterns/OverSpecifiedClaudeMd]]
- [[ClaudeExperience/Reference/AutoMemory]]
- [[ClaudeExperience/Reference/ProjectRules]]
