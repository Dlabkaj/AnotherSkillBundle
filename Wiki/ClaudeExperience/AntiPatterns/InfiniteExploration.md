# InfiniteExploration

**Summary**: User asks Claude to "investigate" or "look into" something without scoping it. Claude reads dozens or hundreds of files trying to understand — the main context fills with file contents before any real work starts.

**Sources**: https://code.claude.com/docs/en/best-practices

**Last updated**: 2026-05-23

---

## Observable symptoms

- Prompts like "investigate X", "look into Y", "understand the codebase" with no boundary.
- Long sequences of Read tool calls early in the session.
- Context fills before any deliverable is produced.

## Why it breaks

Claude reads lots of files when researching — all of them consume your main context. Once filled, performance degrades and there's no room left for the actual implementation work (source: https://code.claude.com/docs/en/best-practices).

## Fix

Two options:

1. **Scope narrowly.** Name the files or directories to inspect. "Read `src/auth/session.py` and `src/auth/oauth.py`. Don't read anything else."
2. **Delegate to a subagent.** "Use a subagent to investigate how sessions work in `src/auth/`. Report a summary back." The subagent's reads happen in a separate context window; only the summary lands in yours.

See [[ClaudeExperience/GoodPractices/UseSubagents]].

## Related pages

- [[ClaudeExperience/GoodPractices/UseSubagents]]
- [[ClaudeExperience/AntiPatterns/KitchenSinkSession]]
- [[ClaudeExperience/GoodPractices/ManageContext]]
