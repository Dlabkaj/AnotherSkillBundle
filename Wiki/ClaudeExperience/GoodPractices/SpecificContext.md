# SpecificContext

**Summary**: Precise instructions reduce corrections. Scope the task, point to sources, reference existing patterns, describe the symptom.

**Sources**: https://code.claude.com/docs/en/best-practices, https://code.claude.com/docs/en/common-workflows

**Last updated**: 2026-05-23

---

## Four levers

- **Scope the task**: which file, what scenario, testing preferences.
  > "write a test for foo.py covering the edge case where the user is logged out. avoid mocks."
- **Point to sources**: history, prior decisions.
  > "look through ExecutionFactory's git history and summarize how its api came to be."
- **Reference existing patterns**: name a known-good example.
  > "look at how existing widgets are implemented on the home page. HotDogWidget.php is a good example. follow that pattern for a new calendar widget."
- **Describe the symptom + likely location + 'fixed' looks like**:
  > "users report login fails after session timeout. check `src/auth/`, especially token refresh. write a failing test that reproduces the issue, then fix it."

## Rich content shortcuts

- `@path/to/file` references files directly — Claude reads them before responding. Paths may be relative or absolute. `@`-referencing a file also pulls in CLAUDE.md from its directory and parent directories (source: https://code.claude.com/docs/en/common-workflows).
- `@path/to/dir` returns a directory listing (not contents) — useful for orienting Claude without spending tokens on every file.
- `@server:resource` fetches data from a connected MCP server, e.g. `@github:repos/owner/repo/issues` (source: https://code.claude.com/docs/en/common-workflows).
- Paste images (copy/paste, drag/drop, or pass a file path) — works for diagrams, screenshots, mockups, error UIs.
- Give URLs for documentation. Use `/permissions` to allowlist domains you use often.
- Pipe data in: `cat error.log | claude`, `git log --oneline -20 | claude -p "summarize"` (source: https://code.claude.com/docs/en/common-workflows).
- For unknown context, tell Claude to fetch what it needs — Bash, MCP, file reads.

## When to be vague on purpose

Vague prompts can be useful when you're exploring and can afford to course-correct — you want to see how Claude interprets the problem before constraining it.

## Related pages

- [[ClaudeExperience/AntiPatterns/VaguePrompts]]
- [[ClaudeExperience/GoodPractices/ProvideVerification]]
- [[ClaudeExperience/GoodPractices/PlanThenImplement]]
