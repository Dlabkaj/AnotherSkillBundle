# Use Skills for Procedures

**Summary**: When a CLAUDE.md section grows from a fact into a multi-step procedure, move it into a skill. Skill bodies load only on invocation, so the procedure stops paying tokens every turn.

**Sources**: https://code.claude.com/docs/en/skills

**Last updated**: 2026-05-23

---

## Heuristic

> "Create a skill when you keep pasting the same instructions, checklist, or multi-step procedure into chat, or when a section of CLAUDE.md has grown into a procedure rather than a fact." (source: https://code.claude.com/docs/en/skills)

Facts → CLAUDE.md. Procedures → skills. Reference material → skill sibling files.

## Where the skill lives

- Enterprise (managed settings): all org users.
- Personal: `~/.claude/skills/<name>/SKILL.md` — all your projects.
- Project: `.claude/skills/<name>/SKILL.md` — this project only.
- Plugin: `<plugin>/skills/<name>/SKILL.md` — namespaced as `plugin:skill`.

Conflict order: enterprise > personal > project. Plugins never conflict. Project skills also load from `.claude/skills/` in every parent directory up to the repo root, and from nested ones on demand. (source: https://code.claude.com/docs/en/skills)

## Authoring rules

- Keep `SKILL.md` under 500 lines.
- Write *standing instructions* — content stays in context the rest of the session and is **not** re-read on later turns.
- For side-effecting actions (`/commit`, `/deploy`), set `disable-model-invocation: true` so Claude can't trigger them on its own.
- For background knowledge (`legacy-context`), set `user-invocable: false` so Claude can pull it but it doesn't pollute the `/` menu.
- For one-shot research / large-context tasks, use `context: fork` + an `agent:` (e.g. `Explore`) so the skill drives a subagent and doesn't bloat the main context. See [[ClaudeExperience/GoodPractices/UseSubagents]].
- Pre-approve only the tools the skill needs via `allowed-tools` to skip per-use prompts.
- Inject live data with `` !`<command>` `` at the start of a line — output is substituted before Claude sees the skill. Only one pass; nested placeholders don't re-expand. (source: https://code.claude.com/docs/en/skills)

## Custom commands and skills are the same thing now

`.claude/commands/deploy.md` and `.claude/skills/deploy/SKILL.md` both create `/deploy`. Existing command files keep working. Skill format adds a directory, frontmatter, and auto-invocation by Claude when relevant. (source: https://code.claude.com/docs/en/skills)

## Live edits

Adding/editing/removing skills in `~/.claude/skills/`, project `.claude/skills/`, or any `--add-dir` `.claude/skills/` takes effect within the current session. Creating a *top-level* skills dir that didn't exist at startup requires a restart. (source: https://code.claude.com/docs/en/skills)

## Related pages

- [[ClaudeExperience/Workflows/Skills]]
- [[ClaudeExperience/AntiPatterns/BloatedSkillBody]]
- [[ClaudeExperience/Reference/SkillFrontmatter]]
- [[ClaudeExperience/GoodPractices/EffectiveClaudeMd]]
- [[ClaudeExperience/GoodPractices/UseSubagents]]
