# Cache Churn

**Summary**: Mid-task actions that invalidate the prompt cache — switching models, `/compact`-ing mid-task, MCP servers flapping, editing CLAUDE.md and expecting it to apply now. Each one forces a full reprocess of the next request and costs real money + latency on long conversations.

**Sources**: https://code.claude.com/docs/en/prompt-caching

**Last updated**: 2026-05-24

---

## Symptom

- A turn that should take seconds takes 30+ seconds for no obvious reason.
- API responses show `cache_creation_input_tokens` climbing every turn while `cache_read_input_tokens` stays low.
- Subscription usage burns through the daily cap unusually fast.
- You edited CLAUDE.md mid-session and Claude is still ignoring the new rule.
- Resuming yesterday's long conversation is the slowest request all day.
- `opusplan` toggling between Opus and Sonnet on every plan-mode entry/exit silently doubles work.

## Why it happens

- The prompt cache is **exact prefix match** — one byte different in the system prompt or earlier conversation and everything after it recomputes. No per-file or per-segment caching. (source: https://code.claude.com/docs/en/prompt-caching)
- Each model has its own cache. `/model` is a full recompute, even on identical content.
- `opusplan` resolves to Opus in plan mode, Sonnet during execution → each plan-mode toggle is a model switch → fresh cold cache. (source: https://code.claude.com/docs/en/prompt-caching)
- MCP server connect/disconnect lives in the system prompt layer. Servers flapping (stdio exit, HTTP session timeout, auto-reconnect) invalidates the cache silently. (source: https://code.claude.com/docs/en/prompt-caching)
- Adding/removing a **bare** tool deny rule (`Bash`, `WebFetch`, `Bash(*)`) reshapes the tool set in the system prompt. Scoped denies (`Bash(rm *)`) are cache-safe.
- `/compact` replaces conversation history with a summary → conversation-layer invalidation by design.
- Claude Code upgrade rewrites system prompt + tool defs. Resuming a long session after an upgrade reprocesses the entire history. (source: https://code.claude.com/docs/en/prompt-caching)
- CLAUDE.md and output-style mid-session edits are cache-safe — but **they also don't take effect until `/clear`, `/compact`, or restart**. The opposite of intuition.

## Corrective

- Pick model + connect MCP servers at the **start** of the session, not mid-task.
- Save `/compact` for natural breaks **between** tasks, not mid-task. If you've gone down a doomed path, `/rewind` instead — it truncates to an already-cached prefix.
- If you need to swap MCP rule scope, prefer scoped denies (`Bash(git push *)`) over bare tool denies (`Bash`).
- Treat CLAUDE.md/output-style edits as "applies next session". To force the new rules now, `/clear`.
- On `opusplan`: accept that plan-mode toggles cost. If you toggle constantly, pick a single model.
- After an upgrade, resume short sessions first to avoid the expensive long-history reprocess.
- Monitor `cache_read_input_tokens` ÷ `cache_creation_input_tokens` — if creation stays high turn after turn, find what's changing in your prefix.

## Related pages

- [[ClaudeExperience/Reference/PromptCaching]]
- [[ClaudeExperience/GoodPractices/ManageContext]]
- [[ClaudeExperience/Workflows/CheckpointsRewind]]
- [[ClaudeExperience/AntiPatterns/KitchenSinkSession]]
