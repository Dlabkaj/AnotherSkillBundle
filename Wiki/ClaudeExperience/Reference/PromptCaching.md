# Prompt Caching

**Summary**: Claude Code manages prompt caching automatically. Understanding what invalidates it explains slow turns after model switches, `/compact`, mid-session MCP reconnects, and Claude Code upgrades.

**Sources**: https://code.claude.com/docs/en/prompt-caching

**Last updated**: 2026-05-24

---

## Mental model

Each turn re-sends the full request. The API caches by **exact prefix match** of recently processed content; only the latest exchange is new. Match is exact — a change anywhere in the prefix recomputes everything after it. **No per-file or per-segment caching.** (source: https://code.claude.com/docs/en/prompt-caching)

Claude Code orders each request so rarely-changing content comes first:

| Layer | Content | Invalidates when |
| --- | --- | --- |
| System prompt | Core instructions, tool definitions, output style | MCP server connects/disconnects, Claude Code upgrade |
| Project context | CLAUDE.md, auto memory, unscoped rules | Session start, after `/clear` or `/compact` |
| Conversation | Your messages, Claude's responses, tool results | Every turn |

Two settings aren't in the prompt text but matter:
- **Model** — cache is keyed by model. Switching = full recompute even if content identical.
- **Effort level** — not part of cache key OR prompt; changing has no effect on cache. (source: https://code.claude.com/docs/en/prompt-caching)

## What invalidates the cache

- **Switching models** — `/model`, plus `opusplan` (resolves to Opus in plan, Sonnet in execution → each plan toggle is a model switch).
- **Connecting/disconnecting an MCP server** — tool definitions sit in system prompt. Stdio process exits, HTTP session expires, auto-reconnect all invalidate. **Editing MCP config doesn't change the cache until restart connects/disconnects.**
- **Denying an entire tool** — bare `Bash` / `WebFetch` deny rule (or `Bash(*)`) removes the tool from context. **Scoped deny rules like `Bash(rm *)`, and all allow/ask rules, do NOT invalidate** — Claude Code checks them at call time, prefix intact.
- **Compacting** — replaces message history with a summary. Conversation layer invalidates by design. System prompt reused; project context reloads from disk (cache-hits if CLAUDE.md + memory unchanged since session start).
- **Upgrading Claude Code** — new version typically updates system prompt / tool definitions. Auto-update applies on next launch, never mid-session. Set `DISABLE_AUTOUPDATER=1` for manual control. **Resuming a long session after an upgrade is one of the most expensive requests you can send.**

(source: https://code.claude.com/docs/en/prompt-caching)

## What keeps the cache

- Editing files in your repo (file contents enter context only when Claude reads them; edits don't retroactively change earlier reads — Claude Code appends a `<system-reminder>` and Claude re-reads if needed)
- Editing CLAUDE.md mid-session (cache-safe, but the edit also doesn't apply — see [[ClaudeExperience/Reference/ClaudeMdLocations]])
- Changing output style mid-session (cache-safe, but doesn't apply)
- Changing permission mode (cache-safe — EXCEPT `opusplan` switching to Opus when entering plan mode, which is a model switch)
- Invoking skills and commands (injected as user messages at point of invocation)
- Running `/recap` (appends summary as command output, not history replacement like `/compact`)
- Rewinding the conversation (truncates back to an earlier prefix that is already cached)
- Spawning a subagent (subagent has its own cache; parent prefix intact)

(source: https://code.claude.com/docs/en/prompt-caching)

## Cache lifetime (TTL)

- **5-minute TTL** — default on API keys, Bedrock, Vertex, Foundry, Claude Platform on AWS. Cache writes billed at lower rate.
- **1-hour TTL** — keeps cache warm through longer breaks; cache writes billed at higher rate.

(source: https://code.claude.com/docs/en/prompt-caching)

| Auth context | Default TTL | Override |
| --- | --- | --- |
| Claude subscription | 1-hour (automatic, included in plan) | Drops to 5-min automatically if you exceed plan limits and are billed for credits |
| API key / third-party | 5-minute | `ENABLE_PROMPT_CACHING_1H=1` to opt in to 1-hour |
| Anywhere | — | `FORCE_PROMPT_CACHING_5M=1` to force 5-min regardless of auth |

Each cache hit resets the timer. After a long enough gap, the next request recomputes the full input — why the first turn back after stepping away is noticeably slower. (source: https://code.claude.com/docs/en/prompt-caching)

## Cache scope

Effectively one-machine, one-directory. System prompt embeds working directory, platform, shell, OS version, and auto-memory paths. Two sessions in different directories build different prefixes and miss each other's cache. **Including worktrees of the same repository.** Parallel sessions in the same directory share cache. Sequential sessions share only if the git status snapshot at startup matches (branch + recent commits). (source: https://code.claude.com/docs/en/prompt-caching)

## Subagents and the cache

A subagent starts its own conversation with its own system prompt + tool set. Builds its own cache, starting cold on first call. **Subagents use the 5-minute TTL even on a subscription** (automatic 1-hour TTL is main-conversation only). Parent's cache is unaffected — the call and result append to the parent's conversation, leaving its prefix intact.

A **fork** is the exception: it inherits the parent's system prompt, tools, and history exactly, so its first request reads the parent's cache. See [[ClaudeExperience/Reference/SubagentFrontmatter]]. (source: https://code.claude.com/docs/en/prompt-caching)

## Cache server location

| Setup | Cache lives in |
| --- | --- |
| API key, subscription, Claude Platform on AWS | Anthropic infrastructure |
| Bedrock or Vertex | Your cloud provider's serving infra |
| Foundry | Anthropic infrastructure (requests route there) |
| Custom `ANTHROPIC_BASE_URL` / LLM gateway | Wherever your requests are forwarded |

(source: https://code.claude.com/docs/en/prompt-caching)

## Measure cache performance

Every API response reports:

| Field | Meaning |
| --- | --- |
| `cache_creation_input_tokens` | Tokens written this turn (cache write rate) |
| `cache_read_input_tokens` | Tokens served from cache (~10% of standard input rate) |

High read:creation ratio = caching working well. Creation staying high turn after turn means something in your prefix keeps changing. (source: https://code.claude.com/docs/en/prompt-caching)

## Disable

Env vars to set to `1`:

- `DISABLE_PROMPT_CACHING` — all models
- `DISABLE_PROMPT_CACHING_HAIKU`
- `DISABLE_PROMPT_CACHING_SONNET`
- `DISABLE_PROMPT_CACHING_OPUS`

(source: https://code.claude.com/docs/en/prompt-caching)

## Practical takeaways

- Pick model and connect MCP servers at the **top** of a session.
- Save `/compact` for **natural breaks** between tasks, not mid-task.
- Prefer `/rewind` over `/compact` when abandoning a path — rewinding truncates to a cached prefix instead of building a new one.
- A long gap of inactivity is the most common reason your "first turn back" is slow — that's TTL expiry, not the model being broken.

## Related pages

- [[ClaudeExperience/AntiPatterns/CacheChurn]]
- [[ClaudeExperience/Reference/ContextWindow]]
- [[ClaudeExperience/Reference/ClaudeMdLocations]]
- [[ClaudeExperience/Reference/AutoMemory]]
- [[ClaudeExperience/GoodPractices/ManageContext]]
- [[ClaudeExperience/Workflows/Subagents]]
