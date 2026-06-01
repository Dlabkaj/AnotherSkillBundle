# ManageContext

**Summary**: Context window is the fundamental constraint. Performance degrades as it fills. Use `/clear`, `/compact`, subagents, `/btw`, and rewind to keep signal-to-noise high.

**Sources**: https://code.claude.com/docs/en/best-practices, https://claude.com/blog/using-claude-code-session-management-and-1m-context

**Last updated**: 2026-05-24

---

## Tools

- **`/clear`** — fully reset context between unrelated tasks. The default move when switching topics.
- **Auto-compaction** — triggered automatically near context limits. Summarizes what matters: code patterns, file states, key decisions. You don't have to do anything.
- **`/compact <instructions>`** — explicit compaction, biased toward what you tell it to preserve.
  > "/compact Focus on the API changes"
- **`Esc + Esc` / `/rewind`** — partial summarization. Pick a checkpoint and summarize from / up to it.
- **`/btw`** — quick questions whose answer appears in a dismissible overlay and never enters conversation history. Use for sidebar questions during long tasks.
- **CLAUDE.md compaction hint**:
  > "When compacting, always preserve the full list of modified files and any test commands"
- **`/rewind` beats `/compact` when abandoning a path** — rewind truncates back to an already-cached prefix; compact builds a new one and costs a full reprocess. See [[ClaudeExperience/Reference/PromptCaching]]. (source: https://code.claude.com/docs/en/prompt-caching)
- **`/usage`** — view consumption patterns for the current account. Use when planning sessions around quota. (source: https://claude.com/blog/using-claude-code-session-management-and-1m-context)

## Why proactive `/compact` beats autocompact

**"The model is at its least intelligent point when compacting"** — context rot has already kicked in by the time autocompact fires (source: https://claude.com/blog/using-claude-code-session-management-and-1m-context). Two failure modes:

- Autocompact can't predict where the conversation will go next. If you pivot after a long debug session to a different warning, the summary may drop the relevant context.
- The summary itself is built by a model already operating in a degraded context.

Mitigations:
- Trigger `/compact` **early** with an explicit focus (`/compact focus on auth refactor, drop test debugging`) rather than letting it auto-fire at the wall.
- Or `/clear` and hand-write what matters (refactor goals, constraints, relevant files, ruled-out approaches). More effort, but the new context is exactly what you chose.
- After a failed approach, `/rewind` to before the failed turn is usually better than correcting forward — it preserves the useful file reads and discards the noise (source: https://claude.com/blog/using-claude-code-session-management-and-1m-context).

## Heuristics

- Switching tasks → `/clear` before starting.
- Two corrections on same issue → `/clear` and rewrite the prompt.
- Long investigation → use a subagent so the reads don't land in your context. See [[ClaudeExperience/GoodPractices/UseSubagents]].
- Risky experiment → checkpoint before, [[ClaudeExperience/Workflows/CheckpointsRewind|rewind]] after if it goes sideways.

## Related pages

- [[ClaudeExperience/AntiPatterns/KitchenSinkSession]]
- [[ClaudeExperience/AntiPatterns/RepeatedCorrections]]
- [[ClaudeExperience/AntiPatterns/InfiniteExploration]]
- [[ClaudeExperience/AntiPatterns/CacheChurn]]
- [[ClaudeExperience/Workflows/CheckpointsRewind]]
- [[ClaudeExperience/Reference/PromptCaching]]
