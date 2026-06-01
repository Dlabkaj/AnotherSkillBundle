# Workflow: Subagents

**Summary**: How to drive subagents day-to-day — when to delegate, how to invoke, foreground vs background, chaining, forks, and the patterns that actually save context.

**Sources**: https://code.claude.com/docs/en/sub-agents, https://code.claude.com/docs/en/best-practices, https://www.tembo.io/blog/claude-code-subagents

**Last updated**: 2026-05-25

---

## When to reach for a subagent

Subagents help you:
- **Preserve context** — exploration/implementation stays out of the main conversation
- **Enforce constraints** — limit which tools a subagent can use
- **Reuse configurations** — user-level subagents work across projects
- **Specialize behavior** — focused system prompt per domain
- **Control costs** — route to faster/cheaper models like Haiku

(source: https://code.claude.com/docs/en/sub-agents)

**Use a subagent when**:
- Output is verbose (test runs, log inspection, doc fetches) and you only need the summary.
- You want enforced tool restrictions or permissions.
- The work is self-contained and can return a one-paragraph result.

**Stay in main conversation when**:
- Frequent back-and-forth / iterative refinement.
- Multiple phases share significant context (planning → impl → testing).
- Quick targeted change.
- Latency matters — subagents start fresh and may need time to gather context.

(source: https://code.claude.com/docs/en/sub-agents)

For a side question on existing context, use [`/btw`](https://code.claude.com/docs/en/interactive-mode) instead — it sees your full context, has no tool access, and the answer is discarded rather than added to history. (source: https://code.claude.com/docs/en/sub-agents)

Skills run in the main context — pick [[ClaudeExperience/Workflows/Skills|skills]] when you want a reusable prompt that should see your conversation, not isolated subagent context.

### The isolation spectrum

Think of the four primitives along a single axis from least to most isolation. The right architectural choice is whichever one solves your problem at the lowest overhead.

| Primitive   | Context window      | Process       | Comms                       | Cost / latency      |
| ----------- | ------------------- | ------------- | --------------------------- | ------------------- |
| Skill       | Same as main        | Same          | Inline                      | Lowest              |
| Subagent    | Isolated, ephemeral | Same harness  | One-way summary back        | Medium              |
| Agent team  | Separate            | Separate      | Bidirectional messaging     | Highest             |

(source: https://boringbot.substack.com/p/claude-code-skills-subagents-hooks)

Common failure: reaching for the heaviest primitive ("spawn a subagent") for work a skill could handle in-context, adding latency and losing visibility for no isolation benefit.

## How to invoke

Three escalating patterns:

1. **Natural language** — name the subagent in the prompt; Claude decides whether to delegate.
2. **@-mention** — guarantees that subagent runs for one task: `@"code-reviewer (agent)" look at the auth changes`. Plugin agents appear as `my-plugin:code-reviewer` or `my-plugin:review:security`. Manual form: `@agent-<name>`. (source: https://code.claude.com/docs/en/sub-agents)
3. **Session-wide** — `claude --agent code-reviewer` makes the main thread itself take on that subagent's system prompt, tools, and model. Persists across resume. CLI flag overrides the `agent` setting if both are present. (source: https://code.claude.com/docs/en/sub-agents)

Manage from inside a session with the `/agents` slash command — Library tab lists defined agents, Running tab shows live instances. The menu is the recommended day-to-day entry point for creating/editing/inspecting subagents. (source: https://www.tembo.io/blog/claude-code-subagents)

To make a project session always start as a subagent:
```json
// .claude/settings.json
{ "agent": "code-reviewer" }
```

## Foreground vs background

- **Foreground** = blocks the main conversation; permission prompts pass through to you.
- **Background** = runs concurrently; uses already-granted permissions and **auto-denies any tool call that would prompt**. If a background subagent needs to ask a clarifying question, that tool call fails but the subagent continues.

(source: https://code.claude.com/docs/en/sub-agents)

`Ctrl+B` backgrounds a running task. `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` disables background entirely. If a background subagent fails on missing permissions, retry with a fresh foreground subagent. (source: https://code.claude.com/docs/en/sub-agents)

## Common patterns

### Isolate high-volume output

```
Use a subagent to run the test suite and report only the failing tests with their error messages.
```

The verbose output stays in the subagent; the summary returns. (source: https://code.claude.com/docs/en/sub-agents)

### Run parallel research

```
Research the authentication, database, and API modules in parallel using separate subagents.
```

Best when the research paths don't depend on each other. **Warning**: many subagents each returning detailed results still consumes significant context. For sustained parallelism, see `agent-teams` (each worker gets its own context). (source: https://code.claude.com/docs/en/sub-agents)

### Chain subagents

```
Use the code-reviewer subagent to find performance issues, then use the optimizer subagent to fix them.
```

Each subagent completes and returns; Claude passes relevant context to the next. (source: https://code.claude.com/docs/en/sub-agents)

### Writer-reviewer

After Claude writes code, spawn a second subagent to review for edge cases / security / performance. Fresh context = unbiased read. See [[ClaudeExperience/AntiPatterns/TrustThenVerifyGap]]. (source: https://code.claude.com/docs/en/best-practices)

## What loads at startup

A non-fork subagent starts with a fresh, isolated context containing only:

- **System prompt** — its own (markdown body or `prompt` field) + environment details. NOT the full Claude Code system prompt.
- **Task message** — the delegation prompt Claude writes when handing off.
- **CLAUDE.md + memory** — every level of the memory hierarchy the main session loads. *Exception*: built-in `Explore` and `Plan` skip CLAUDE.md.
- **Git status** — snapshot from session start. Skipped when `includeGitInstructions: false` or when not in a git repo. Explore/Plan skip regardless.
- **Preloaded skills** — full content of any skill in the agent's `skills:` field.

There's no setting to change which agents skip CLAUDE.md. The main conversation reads Explore/Plan results with full CLAUDE.md context, so most rules don't need to reach the subagent itself. If a rule must (e.g. "ignore `vendor/`"), restate it in the prompt you give Claude when delegating. (source: https://code.claude.com/docs/en/sub-agents)

**Resume** retains the full conversation history. **Auto-compaction** triggers ~95% capacity by default; set `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=50` to trigger earlier. (source: https://code.claude.com/docs/en/sub-agents)

## Forks vs named subagents

Fork = inherits the entire conversation. Named = starts fresh.

| | Fork | Named subagent |
| --- | --- | --- |
| Context | Full conversation history | Fresh + delegation prompt |
| System prompt + tools | Same as main session | From definition |
| Model | Same as main session | From `model` field |
| Permissions | Prompts surface in terminal | Auto-denied when background |
| Prompt cache | Shared with main session | Separate cache |

Forks first request reuses parent's prompt cache → cheaper than spawning a fresh subagent for same-context tasks. Pass `isolation: "worktree"` so the fork writes to a separate worktree. **Enable**: `CLAUDE_CODE_FORK_SUBAGENT=1`. A fork cannot spawn further forks. `/fork <directive>` spawns one manually. (source: https://code.claude.com/docs/en/sub-agents)

### Fork panel controls

| Key | Action |
| --- | --- |
| `↑` / `↓` | Move between rows |
| `Enter` | Open fork transcript and send follow-up messages |
| `x` | Dismiss finished or stop running fork |
| `Esc` | Return focus to prompt input |

(source: https://code.claude.com/docs/en/sub-agents)

## Curated recipes (practitioner defaults)

Starting point for the five most common roles — tighten tools and model from here.

| Subagent           | Tools                                              | Model  | Purpose                                                |
| ------------------ | -------------------------------------------------- | ------ | ------------------------------------------------------ |
| `code-reviewer`    | Read, Grep, Glob                                   | Sonnet | Pre-merge review; structured report by file + severity. Read-only by design. Swap to Opus for security-critical code. |
| `debugger`         | Read, Edit, Bash, Grep, Glob                       | Sonnet | Reproduce failures, run tests, propose targeted patches |
| `test-writer`      | Read, Write, Edit, Bash, Glob, Grep                | Sonnet | Generate unit + integration tests for changed modules  |
| `security-auditor` | Read, Grep, Glob                                   | Opus   | Read-only vulnerability / secret / unsafe-pattern audit |
| `doc-maintainer`   | Read, Write, Edit, Glob, Grep, WebFetch, WebSearch | Haiku  | Keep README, API docs, and inline comments in sync     |

Rule of thumb: start with one specialist (`code-reviewer` is safest), let usage patterns drive when to add the next. (source: https://www.tembo.io/blog/claude-code-subagents)

## Restricting subagents

Disable specific subagents via settings deny array:
```json
{ "permissions": { "deny": ["Agent(Explore)", "Agent(my-custom-agent)"] } }
```

Or CLI: `claude --disallowedTools "Agent(Explore)"`. (source: https://code.claude.com/docs/en/sub-agents)

## Best practices

- **One specific task per subagent** — focused beats general.
- **Detailed `description`** — Claude uses it to decide when to delegate. Include phrases like "use proactively" for automatic delegation.
- **Limit tool access** — security and focus.
- **Check project subagents into version control** — share with team.

(source: https://code.claude.com/docs/en/sub-agents)

## Related pages

- [[ClaudeExperience/Reference/SubagentFrontmatter]]
- [[ClaudeExperience/GoodPractices/UseSubagents]]
- [[ClaudeExperience/Workflows/MultipleSessionsFanout]]
- [[ClaudeExperience/Workflows/PlanMode]]
- [[ClaudeExperience/Workflows/Hooks]]
- [[ClaudeExperience/Workflows/Skills]]
