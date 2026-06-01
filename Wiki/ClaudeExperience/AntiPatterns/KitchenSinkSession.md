# KitchenSinkSession

**Summary**: One session drifts across multiple unrelated tasks. Context fills with irrelevant files, failed attempts, and stale decisions. Performance degrades because the model can't tell which context is still load-bearing.

**Sources**: https://code.claude.com/docs/en/best-practices

**Last updated**: 2026-05-23

---

## Observable symptoms

- Asking Claude task A, then task B (unrelated), then back to A in the same session.
- File reads / command outputs accumulating in context that no longer serve the current task.
- Model "forgets" earlier instructions or re-reads files it already read.

## Why it breaks

Claude's context window is the fundamental constraint, and LLM performance degrades as it fills (source: https://code.claude.com/docs/en/best-practices). A single debugging session can consume tens of thousands of tokens; layering unrelated work on top compounds the noise.

## Fix

Run `/clear` between unrelated tasks. See [[ClaudeExperience/GoodPractices/ManageContext]].

For long-running threads on a single topic, `/compact <instructions>` preserves topic-relevant state while dropping the rest.

## Related pages

- [[ClaudeExperience/AntiPatterns/RepeatedCorrections]]
- [[ClaudeExperience/AntiPatterns/InfiniteExploration]]
- [[ClaudeExperience/GoodPractices/ManageContext]]
