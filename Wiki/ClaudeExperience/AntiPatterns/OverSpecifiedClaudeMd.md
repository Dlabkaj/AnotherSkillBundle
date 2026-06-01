# OverSpecifiedClaudeMd

**Summary**: CLAUDE.md grows large with every reminder, exception, and aspiration. Once bloated, Claude starts ignoring half of it — important rules get lost in the noise.

**Sources**: https://code.claude.com/docs/en/best-practices

**Last updated**: 2026-05-23

---

## Observable symptoms

- CLAUDE.md keeps growing; nothing ever gets pruned.
- Claude breaks a rule that is in the file.
- Claude asks questions whose answers are already in CLAUDE.md (phrasing probably ambiguous).
- File contains generic prose like "write clean code" or restates standard language conventions.

## Why it breaks

CLAUDE.md is loaded at the start of every session — it's permanent context tax. Anthropic explicitly warns: "Bloated CLAUDE.md files cause Claude to ignore your actual instructions!" (source: https://code.claude.com/docs/en/best-practices).

## Fix

For each line ask: "Would removing this cause Claude to make mistakes?" If not, cut it.

Exclude:
- Anything Claude can figure out by reading code
- Standard language conventions
- Detailed API documentation (link instead)
- Information that changes frequently
- Long explanations or tutorials
- Self-evident practices

Include:
- Bash commands Claude can't guess
- Code style rules that differ from defaults
- Testing instructions and preferred runners
- Repository etiquette
- Architectural decisions specific to this project
- Developer environment quirks
- Common gotchas

Convert sometimes-relevant knowledge into skills (loaded on demand) instead of bloating CLAUDE.md. Move deterministic rules to hooks.

## Related pages

- [[ClaudeExperience/GoodPractices/EffectiveClaudeMd]]
- [[ClaudeExperience/Reference/ClaudeMdLocations]]
- [[ClaudeExperience/Workflows/PlanMode]]
