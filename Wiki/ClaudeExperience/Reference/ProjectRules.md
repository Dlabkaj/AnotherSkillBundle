# Project Rules (`.claude/rules/`)

**Summary**: Modular alternative to a single bloated CLAUDE.md. Rule files in `.claude/rules/` load like extra CLAUDE.md content, and can be path-scoped via YAML frontmatter so they only enter context when Claude touches matching files.

**Sources**: https://code.claude.com/docs/en/memory

**Last updated**: 2026-05-23

---

## Layout

```
your-project/
├── .claude/
│   ├── CLAUDE.md           # Main project instructions
│   └── rules/
│       ├── code-style.md   # Always loaded
│       ├── testing.md      # Always loaded
│       └── security.md     # Always loaded
```

Rules **without** a `paths:` frontmatter load every session at the same priority as `.claude/CLAUDE.md`.

## Path-scoped rules

```
---
paths:
  - "src/api/**/*.ts"
---

# API Development Rules
- All API endpoints must include input validation
- Use the standard error response format
- Include OpenAPI documentation comments
```

The rule enters context only when Claude reads a file matching the pattern. Multiple patterns and brace expansion work:

```
---
paths:
  - "src/**/*.{ts,tsx}"
  - "lib/**/*.ts"
  - "tests/**/*.test.ts"
---
```

Pattern examples (source: https://code.claude.com/docs/en/memory):
- `**/*.ts` — all TS files anywhere
- `src/**/*` — everything under `src/`
- `*.md` — markdown in repo root only
- `src/components/*.tsx` — specific directory

## When to prefer rules over CLAUDE.md

- Instructions only matter for part of the codebase → path-scoped rule.
- Different teams own different paths in a monorepo → per-path rule files.
- CLAUDE.md is approaching ~200 lines → split out topic files into rules.

For instructions that only matter sometimes and shouldn't be in context all the time, use a **skill** instead — rules still load on every matching file open, skills load on demand. (source: https://code.claude.com/docs/en/memory)

## Sharing across projects

`.claude/rules/` supports symlinks:

```
ln -s ~/shared-claude-rules .claude/rules/shared
ln -s ~/company-standards/security.md .claude/rules/security.md
```

## User-level rules

`~/.claude/rules/` applies to every project on the machine. User-level rules load **before** project rules, giving project rules higher priority on conflicts. (source: https://code.claude.com/docs/en/memory)

## Related pages

- [[ClaudeExperience/GoodPractices/EffectiveClaudeMd]]
- [[ClaudeExperience/AntiPatterns/OverSpecifiedClaudeMd]]
- [[ClaudeExperience/Reference/ClaudeMdLocations]]
