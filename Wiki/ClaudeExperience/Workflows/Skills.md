# Workflow: Skills

**Summary**: How skills work mechanically — directory layout, lifecycle, invocation control, dynamic context injection, subagent execution.

**Sources**: https://code.claude.com/docs/en/skills

**Last updated**: 2026-05-23

---

## Directory layout

```
my-skill/
├── SKILL.md          # required entrypoint
├── reference.md      # loaded only when SKILL.md says so
├── examples/         # additional resources
└── scripts/
    └── helper.py     # executed, not loaded
```

Reference sibling files from inside `SKILL.md` so Claude knows when to load them. (source: https://code.claude.com/docs/en/skills)

## Lifecycle

1. Skill **descriptions** for all available skills are listed up-front so Claude knows what exists (subject to truncation budget — see [[ClaudeExperience/AntiPatterns/BloatedSkillBody]]).
2. On invocation (by you or by Claude), the rendered `SKILL.md` content enters the conversation **as a single message** and stays for the rest of the session.
3. Claude Code does **not** re-read the file on later turns. Write standing instructions, not single-shot steps.
4. Auto-compaction keeps the first 5,000 tokens of each recently-invoked skill, combined cap 25,000 tokens — fills from most-recent backwards. (source: https://code.claude.com/docs/en/skills)
5. Subagents with a preloaded `skills:` field get **full** skill content injected at startup (different from a regular session).

## Invocation control

| Frontmatter                    | You invoke | Claude invokes | Description in context              |
| ------------------------------ | ---------- | -------------- | ----------------------------------- |
| (default)                      | Yes        | Yes            | Yes                                 |
| `disable-model-invocation: true` | Yes      | No             | No (only loads when you invoke)     |
| `user-invocable: false`        | No         | Yes            | Yes                                 |

`disable-model-invocation` for side-effects (`/commit`, `/deploy`); `user-invocable: false` for background knowledge skills. (source: https://code.claude.com/docs/en/skills)

## Dynamic context injection (`!`)

The `` !`<command>` `` syntax runs the shell command **before** Claude sees the skill. Output replaces the placeholder. One pass — nested placeholders are not re-scanned.

```
## Current changes
!`git diff HEAD`
```

`` ! `` must appear at the start of a line or immediately after whitespace; otherwise it stays literal. `shell:` frontmatter picks bash (default) or powershell. (source: https://code.claude.com/docs/en/skills)

## `context: fork` — run in a subagent

Adds isolation. Skill content becomes the subagent's task prompt. CLAUDE.md is loaded except when `agent:` is `Explore` or `Plan`. (source: https://code.claude.com/docs/en/skills)

| Approach                        | System prompt           | Task                        |
| ------------------------------- | ----------------------- | --------------------------- |
| Skill with `context: fork`      | From `agent:` type      | `SKILL.md` content          |
| Subagent with `skills:` field   | Subagent's markdown body| Claude's delegation message |

Warning: `context: fork` is pointless for guideline-style skills with no task — the subagent just returns. Pair it with an actionable prompt. See [[ClaudeExperience/GoodPractices/UseSubagents]].

## Restrictions and permissions

- Deny the `Skill` tool in `/permissions` to disable all skills.
- Allow/deny specific skills: `Skill(name)` (exact) or `Skill(name *)` (with args).
- `allowed-tools` in the skill frontmatter pre-approves tools while the skill is active. Does **not** restrict — every tool remains callable; your permission rules still apply to non-listed tools.

## Bundled skills worth knowing

`/code-review`, `/batch`, `/debug`, `/loop`, `/claude-api`, plus `/run` + `/verify` + `/run-skill-generator` — the latter trio launches the actual app to confirm changes rather than relying on tests/type-checks alone. `/run-skill-generator` captures install commands, env vars, and launch script into a per-project skill at `.claude/skills/run-<name>/`. (source: https://code.claude.com/docs/en/skills)

## Troubleshooting quick reference

- **Skill doesn't trigger** → description lacks the keywords you'd actually say; or many skills crowded its description out of the listing.
- **Skill triggers too often** → tighten description; consider `disable-model-invocation`.
- **Skill seems to lose effect after first reply** → content is still there; the model is choosing another tool. Strengthen the description or back the behavior with a hook.
- **Descriptions cut short** → raise `skillListingBudgetFraction` (or `SLASH_COMMAND_TOOL_CHAR_BUDGET`); set low-priority entries to `"name-only"` in `skillOverrides`. (source: https://code.claude.com/docs/en/skills)

## Related pages

- [[ClaudeExperience/GoodPractices/SkillsForProcedures]]
- [[ClaudeExperience/AntiPatterns/BloatedSkillBody]]
- [[ClaudeExperience/Reference/SkillFrontmatter]]
- [[ClaudeExperience/Workflows/PlanMode]]
- [[ClaudeExperience/GoodPractices/UseSubagents]]
