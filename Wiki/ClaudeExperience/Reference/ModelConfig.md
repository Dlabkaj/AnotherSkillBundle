# Model Configuration

**Summary**: Which model alias does what, how to pin / override / restrict it, plus effort levels, extended thinking, and 1M context. Use this when budgeting cost, choosing speed-vs-quality, or locking down a managed deployment.

**Sources**: https://code.claude.com/docs/en/model-config

**Last updated**: 2026-05-24

---

## Model aliases

| Alias | Behavior |
| --- | --- |
| `default` | Clears any override; reverts to the recommended model for your account |
| `best` | Most capable (currently `opus`) |
| `sonnet` | Latest Sonnet — daily coding tasks |
| `opus` | Latest Opus — complex reasoning |
| `haiku` | Fast and efficient — simple tasks |
| `sonnet[1m]` | Sonnet with 1M token context |
| `opus[1m]` | Opus with 1M token context |
| `opusplan` | Opus during plan mode, Sonnet during execution |

On Anthropic API and Claude Platform on AWS: `opus` → Opus 4.7, `sonnet` → Sonnet 4.6. (source: https://code.claude.com/docs/en/model-config)

### `default` resolution by tier

| Tier | Default model |
| --- | --- |
| Max, Team Premium | Opus 4.7 |
| Pro, Team Standard, Enterprise, Anthropic API | Sonnet 4.6 |
| Bedrock, Vertex, Foundry | Sonnet 4.5 |

Auto-fallback to Sonnet may happen if you hit a usage threshold on Opus. (source: https://code.claude.com/docs/en/model-config)

## Setting the model (priority order)

1. **During session** — `/model <alias|name>` (applies to session only as of v2.1.144; press `d` on the row in the picker to save as default)
2. **At startup** — `claude --model <alias|name>`
3. **Env var** — `ANTHROPIC_MODEL=<alias|name>`
4. **Settings file** — `model` field

Resumed sessions (`--resume`, `--continue`, `/resume`) **keep the model from when the transcript was saved**, regardless of the current setting. If retired, fall through to normal precedence. (source: https://code.claude.com/docs/en/model-config)

## Restricting models (enterprise / managed)

```json
{ "availableModels": ["sonnet", "haiku"] }
```

**Default is always available** in the picker regardless of `availableModels` — it represents the system default for the user's tier. To fully control, combine:

- `availableModels` — restricts which named models users can switch to
- `model` — initial selection at session start
- `ANTHROPIC_DEFAULT_SONNET_MODEL` / `ANTHROPIC_DEFAULT_OPUS_MODEL` / `ANTHROPIC_DEFAULT_HAIKU_MODEL` — control what `Default` and the aliases resolve to

(source: https://code.claude.com/docs/en/model-config)

## `opusplan` details

- Plan mode → Opus (reasoning)
- Execution → Sonnet (cheaper code-gen)
- **Plan-mode Opus phase uses standard 200K context.** The automatic 1M upgrade applies to the `opus` alias, NOT to `opusplan`.
- Each plan-mode toggle is a model switch → fresh cache. See [[ClaudeExperience/AntiPatterns/CacheChurn]].

(source: https://code.claude.com/docs/en/model-config)

## Effort levels

Adaptive reasoning controls how much the model thinks per step. Supported on Opus 4.7, Opus 4.6, Sonnet 4.6.

| Model | Levels |
| --- | --- |
| Opus 4.7 | `low`, `medium`, `high`, `xhigh`, `max` |
| Opus 4.6 + Sonnet 4.6 | `low`, `medium`, `high`, `max` |

If you set an unsupported level, falls back to the highest supported at or below. Default since v2.1.117: `xhigh` on Opus 4.7, `high` on Opus 4.6 / Sonnet 4.6. (source: https://code.claude.com/docs/en/model-config)

### When to use each

| Level | When |
| --- | --- |
| `low` | Short, scoped, latency-sensitive, not intelligence-sensitive |
| `medium` | Cost-sensitive work that can trade some intelligence |
| `high` | Minimum for intelligence-sensitive work; or to reduce spend vs `xhigh` |
| `xhigh` | Recommended default on Opus 4.7 — best for most coding/agentic |
| `max` | Deepest reasoning, no token cap. Session-only (except via env var). Prone to overthinking — test before adopting |

(source: https://code.claude.com/docs/en/model-config)

### Setting effort

Priority: env var > frontmatter > session level > model default.

- `/effort` (slider) / `/effort high` / `/effort auto`
- Arrow keys on `/model` row
- `--effort <level>` flag
- `CLAUDE_CODE_EFFORT_LEVEL` env var (only place `max` can persist)
- `effortLevel` in settings (no `max` here)
- `effort:` in skill/subagent frontmatter (active only while that skill/agent runs)

(source: https://code.claude.com/docs/en/model-config)

### Effort is NOT part of the cache key

Mid-session effort changes don't invalidate the prompt cache (effort isn't in the prompt). See [[ClaudeExperience/Reference/PromptCaching]].

### `ultrathink` one-off

Including `ultrathink` anywhere in your prompt requests deeper reasoning for that turn without changing the session effort setting. Other phrases like "think", "think hard", "think more" are NOT recognized — they're just prompt text. (source: https://code.claude.com/docs/en/model-config)

## Extended thinking

| Control | How |
| --- | --- |
| Toggle for current session | `Option+T` (macOS), `Alt+T` (Win/Linux) |
| Global default | `/config` toggle → `alwaysThinkingEnabled` in `~/.claude/settings.json` |
| Disable regardless of effort | `MAX_THINKING_TOKENS=0` (other values apply only on fixed-budget mode) |

Output collapsed by default. `Ctrl+O` toggles verbose. **You're charged for all thinking tokens, even when collapsed or redacted.** (source: https://code.claude.com/docs/en/model-config)

### Adaptive vs fixed thinking

- Opus 4.7 always uses adaptive reasoning. `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` does NOT apply.
- Opus 4.6 / Sonnet 4.6: `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1` reverts to fixed budget controlled by `MAX_THINKING_TOKENS`. (source: https://code.claude.com/docs/en/model-config)

## Extended (1M) context

Supported on Opus 4.7, Opus 4.6, Sonnet 4.6.

| Plan | Opus 1M | Sonnet 1M |
| --- | --- | --- |
| Max / Team / Enterprise | Included | Requires usage credits |
| Pro | Requires credits | Requires credits |
| API / pay-as-you-go | Full access | Full access |

Disable entirely with `CLAUDE_CODE_DISABLE_1M_CONTEXT=1`. Activate per session via `/model opus[1m]`, `/model sonnet[1m]`, or `/model claude-opus-4-7[1m]`. (source: https://code.claude.com/docs/en/model-config)

## Environment variables

| Var | Description |
| --- | --- |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | Model for `opus`, and `opusplan` when plan mode active |
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | Model for `sonnet`, and `opusplan` when not in plan mode |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | Model for `haiku` and background functionality |
| `CLAUDE_CODE_SUBAGENT_MODEL` | Model for all subagents and agent teams. **Overrides** per-invocation params and frontmatter. Use `inherit` for normal resolution |

### Pin for third-party deployments

On Bedrock, Vertex, Foundry, or Claude Platform on AWS: pin model versions before rollout. Without pinning, aliases resolve to the latest. Bedrock/Vertex users see a notice + fall back to previous version when a new model isn't enabled in their account; Foundry users see errors. **Set all three model env vars to specific version IDs as part of initial setup.** (source: https://code.claude.com/docs/en/model-config)

## Related pages

- [[ClaudeExperience/Reference/ModelJaggedness]]
- [[ClaudeExperience/Reference/PromptCaching]]
- [[ClaudeExperience/Reference/ContextWindow]]
- [[ClaudeExperience/Reference/SubagentFrontmatter]]
- [[ClaudeExperience/AntiPatterns/CacheChurn]]
