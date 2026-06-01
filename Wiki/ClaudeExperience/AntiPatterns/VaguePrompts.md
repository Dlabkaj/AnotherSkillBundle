# VaguePrompts

**Summary**: Under-specified asks ("fix the login bug", "make it look nicer") force Claude to guess intent. Wrong guess → wasted tokens correcting → see [[ClaudeExperience/AntiPatterns/RepeatedCorrections]].

**Sources**: https://code.claude.com/docs/en/best-practices

**Last updated**: 2026-05-23

---

## Observable symptoms

- Prompt is a short imperative with no file, no constraints, no example.
- Claude asks back many clarifying questions (or worse, guesses silently).
- Output solves a different problem than the one you had in mind.

## Why it breaks

Claude can infer intent but can't read your mind. The more precise the instructions, the fewer corrections needed (source: https://code.claude.com/docs/en/best-practices). Vagueness has a place — early exploration, getting a quick read on how Claude interprets a problem — but as the default it just creates rework.

## Fix

Specify four things when you can:

- **Scope**: which file, which function, which scenario.
- **Sources**: point to git history, existing patterns, similar widgets.
- **Symptom**: describe the user-visible failure and the suspected area.
- **Done**: what "fixed" looks like (test passes, screenshot matches, error gone).

Examples (from source):
- ~~"add tests for foo.py"~~ → "write a test for foo.py covering the edge case where the user is logged out. avoid mocks."
- ~~"fix the login bug"~~ → "users report login fails after session timeout. check `src/auth/`, especially token refresh. write a failing test that reproduces the issue, then fix it."

Also: reference files with `@`, paste images directly, give URLs for docs, pipe data with `cat file | claude`.

## Related pages

- [[ClaudeExperience/GoodPractices/SpecificContext]]
- [[ClaudeExperience/GoodPractices/ProvideVerification]]
- [[ClaudeExperience/AntiPatterns/RepeatedCorrections]]
