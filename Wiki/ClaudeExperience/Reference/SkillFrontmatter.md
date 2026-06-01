# Skill Frontmatter Reference

**Summary**: Authoritative list of frontmatter fields for `SKILL.md` files and the substitutions they enable.

**Sources**: https://code.claude.com/docs/en/skills

**Last updated**: 2026-05-23

---

## Fields

| Field                      | Required    | Description |
| -------------------------- | ----------- | ----------- |
| `name`                     | No          | Display name. Defaults to directory name. Lowercase letters, numbers, hyphens only. Max 64 chars. |
| `description`              | Recommended | What the skill does + when to use it. Hard-truncated at 1,536 chars in the listing. |
| `when_to_use`              | No          | Extra invocation guidance. Counts toward the 1,536 char cap. |
| `argument-hint`            | No          | Autocomplete hint. Example: `[issue-number]`. |
| `arguments`                | No          | Named positional arguments for `$name` substitution. |
| `disable-model-invocation` | No          | `true` = only you can invoke. Default `false`. |
| `user-invocable`           | No          | `false` = only Claude can invoke; hidden from `/` menu. |
| `allowed-tools`            | No          | Tools pre-approved while skill is active. Does not restrict — only grants. |
| `model`                    | No          | Model to use when skill is active. |
| `effort`                   | No          | Effort level when skill is active. |
| `context`                  | No          | `fork` = run in a forked subagent context. |
| `agent`                    | No          | Subagent type when `context: fork`. |
| `hooks`                    | No          | Hooks scoped to this skill's lifecycle. |
| `paths`                    | No          | Glob patterns that gate skill activation. |
| `shell`                    | No          | `bash` (default) or `powershell` for `` !`command` `` blocks. |

(source: https://code.claude.com/docs/en/skills)

## String substitutions

- `$ARGUMENTS` — all arguments passed at invocation.
- `$ARGUMENTS[N]` or `$N` — specific argument by 0-based index. Shell-style quoting; wrap multi-word values in quotes to pass as one arg.
- `$name` — named argument declared in `arguments`.
- `${CLAUDE_SESSION_ID}` — current session ID.
- `${CLAUDE_EFFORT}` — current effort level.
- `${CLAUDE_SKILL_DIR}` — directory holding this `SKILL.md`.

If you invoke with args but `$ARGUMENTS` is absent in the body, Claude Code appends `ARGUMENTS: <your input>` at the end of the rendered skill content. (source: https://code.claude.com/docs/en/skills)

## `skillOverrides` setting

Controls visibility without editing the skill file (e.g. shared/MCP-provided skills):

| Value                 | Listed to Claude   | In `/` menu |
| --------------------- | ------------------ | ----------- |
| `"on"`                | Name + description | Yes         |
| `"name-only"`         | Name only          | Yes         |
| `"user-invocable-only"` | Hidden           | Yes         |
| `"off"`               | Hidden             | Hidden      |

Plugin skills are unaffected by `skillOverrides`. (source: https://code.claude.com/docs/en/skills)

## Budgets

- Per-skill listing: each entry's `description + when_to_use` capped at **1,536 chars**.
- Total listing budget: default **1% of model context window**. Raise via `skillListingBudgetFraction` (e.g. `0.02`) or `SLASH_COMMAND_TOOL_CHAR_BUDGET` (fixed char count).
- Auto-compaction re-attach: first **5,000 tokens** per recently-invoked skill, **25,000 tokens** combined cap, filled most-recent backwards. (source: https://code.claude.com/docs/en/skills)

## Related pages

- [[ClaudeExperience/Workflows/Skills]]
- [[ClaudeExperience/GoodPractices/SkillsForProcedures]]
- [[ClaudeExperience/AntiPatterns/BloatedSkillBody]]
