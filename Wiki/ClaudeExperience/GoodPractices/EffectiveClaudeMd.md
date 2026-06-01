# EffectiveClaudeMd

**Summary**: Treat CLAUDE.md like code — prune it, review it, test changes. Include only what Claude can't infer from the codebase. When unsure, cut.

**Sources**: https://code.claude.com/docs/en/best-practices, https://code.claude.com/docs/en/memory

**Last updated**: 2026-05-23

---

## Bootstrap

Run `/init` to generate a starter CLAUDE.md from current project structure, then refine over time. Set `CLAUDE_CODE_NEW_INIT=1` to use the interactive multi-phase flow (source: https://code.claude.com/docs/en/memory).

## The cut test

For each line ask: "Would removing this cause Claude to make mistakes?" If not, cut it.

## Include

- Bash commands Claude can't guess (custom build scripts, internal CLI tools)
- Code style rules that differ from language defaults
- Testing instructions and preferred test runners
- Repository etiquette (branch naming, PR conventions)
- Architectural decisions specific to this project
- Developer environment quirks (required env vars)
- Common gotchas / non-obvious behaviors
- **Search-before-build directive.** Tell Claude to grep existing code for similar functionality before writing new — prevents reinventing wheels in larger projects. Practitioners report this is one of the highest-leverage CLAUDE.md lines as a codebase grows. (source: https://www.youtube.com/watch?v=GN0yhCt9qeo, Garry Tan / G-stack)

## Exclude

- Anything Claude can figure out by reading code
- Standard language conventions Claude already knows
- Detailed API docs — link to them instead
- Information that changes frequently
- Long explanations or tutorials
- File-by-file descriptions of the codebase
- Self-evident practices ("write clean code")

## Emphasis

Adding `IMPORTANT` or `YOU MUST` improves adherence on specific rules — use sparingly so the emphasis stays meaningful.

## Diagnostic signals

- Claude breaks a rule in the file → file is probably too long; the rule got lost.
- Claude asks questions whose answers are in the file → phrasing is ambiguous; rewrite.

## Alternatives for non-always knowledge

- **Skills** — domain knowledge or workflows that only apply sometimes. Loaded on demand. See [[ClaudeExperience/Workflows/MultipleSessionsFanout]] context — skills replace per-session boilerplate.
- **Hooks** — deterministic rules that must execute every time. CLAUDE.md is advisory; hooks are guarantees.
- **`.claude/rules/`** — modular rules, optionally path-scoped. See [[ClaudeExperience/Reference/ProjectRules]].
- **Auto memory** — let Claude record its own learnings instead of you adding every nuance manually. See [[ClaudeExperience/Reference/AutoMemory]].
- **`--append-system-prompt`** — for instructions you want at the system-prompt level. Must be passed on every invocation, so better suited to scripts than interactive use (source: https://code.claude.com/docs/en/memory).

## Maintainer-only notes

Block-level HTML comments (`<!-- ... -->`) in CLAUDE.md are **stripped before injection** into Claude's context. Use them to leave notes for human maintainers without spending context tokens. Comments inside code blocks are preserved. (source: https://code.claude.com/docs/en/memory)

## Imports + locations

CLAUDE.md supports `@path/to/file` imports. See [[ClaudeExperience/Reference/ClaudeMdLocations]] for which file applies where.

## Related pages

- [[ClaudeExperience/AntiPatterns/OverSpecifiedClaudeMd]]
- [[ClaudeExperience/Reference/ClaudeMdLocations]]
