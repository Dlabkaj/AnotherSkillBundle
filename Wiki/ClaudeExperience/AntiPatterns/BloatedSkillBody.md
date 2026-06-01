# Bloated Skill Body

**Summary**: Skill body keeps reciting "why" or background narrative. Once invoked it stays in context for the whole session, so every line is a recurring token cost — and bigger skills cap the auto-compaction re-attach budget for everyone else.

**Sources**: https://code.claude.com/docs/en/skills

**Last updated**: 2026-05-23

---

## Symptom

- `SKILL.md` is hundreds of lines and explains rationale, history, or alternatives that aren't actionable.
- Multiple invoked skills add up; later compaction silently drops older ones because they no longer fit the 25K combined re-attach budget.
- A skill seems to "stop working" after a few turns — actually the description was dropped from the listing because the per-skill listing was truncated by the description budget (default 1% of context). (source: https://code.claude.com/docs/en/skills)

## Why it happens

- Authors copy reference docs into the skill body instead of moving them to sibling files loaded on demand.
- Authors mix `disable-model-invocation` task-skills with reference-style guidance; the latter belongs near the codebase, not as standing instructions.
- Authors add too many skills; descriptions for least-used ones get stripped first when the budget overflows.

## Corrective

See [[ClaudeExperience/GoodPractices/SkillsForProcedures]]:
- Keep `SKILL.md` under 500 lines; move detail into siblings (`reference.md`, `examples.md`) referenced from the body.
- State *what to do*, not *why*. Drop narration.
- Cull old skills. If you must keep many, raise `skillListingBudgetFraction` (e.g. `0.02`) or set `SLASH_COMMAND_TOOL_CHAR_BUDGET` so descriptions don't get clipped. (source: https://code.claude.com/docs/en/skills)
- Auto-compaction re-attaches only the first 5,000 tokens per recently-invoked skill, capped at 25,000 combined — bigger skills evict smaller ones. (source: https://code.claude.com/docs/en/skills)

## Related pages

- [[ClaudeExperience/GoodPractices/SkillsForProcedures]]
- [[ClaudeExperience/Workflows/Skills]]
- [[ClaudeExperience/AntiPatterns/OverSpecifiedClaudeMd]]
- [[ClaudeExperience/GoodPractices/ManageContext]]
