# UseSubagents

**Summary**: Delegate research, investigation, and review to subagents. They run in a separate context window and report a summary back, keeping your main conversation lean.

**Sources**: https://code.claude.com/docs/en/best-practices, https://code.claude.com/docs/en/sub-agents, https://claude.com/blog/using-claude-code-session-management-and-1m-context

**Last updated**: 2026-05-24

---

## Why

Context is the fundamental constraint. When Claude researches a codebase it reads lots of files, all of which consume your main context. Subagents run in separate context windows and report back summaries (source: https://code.claude.com/docs/en/best-practices).

## The one-line test

**"Will I need this tool output again, or just the conclusion?"** If only the conclusion, delegate to a subagent — the intermediate output stays in the child context and never bloats yours. (source: https://claude.com/blog/using-claude-code-session-management-and-1m-context)

## When to use

- **Codebase investigation** — "use subagents to investigate X". They explore in a separate context.
- **Verification against spec** — fresh-context subagent checks the implementation against requirements (source: https://claude.com/blog/using-claude-code-session-management-and-1m-context).
- **Verification after implementation** — "use a subagent to review this code for edge cases / security / performance". Fresh context = unbiased review (the writer-reviewer pattern).
- **Summarizing external codebases** — reference implementation extraction without pulling the whole repo into your context (source: https://claude.com/blog/using-claude-code-session-management-and-1m-context).
- **Writing documentation from git changes** — read the diff, produce the doc, return the doc only (source: https://claude.com/blog/using-claude-code-session-management-and-1m-context).
- **Isolated tasks** — anything that reads many files but only needs a one-paragraph answer back.
- **Verbose tool output** — running tests, fetching docs, processing logs. The output stays in the subagent's context; only the summary returns. (source: https://code.claude.com/docs/en/sub-agents)

## When NOT to use

- Frequent back-and-forth with the user.
- Multiple phases share significant context (planning → impl → testing).
- Quick targeted change.
- Latency-sensitive tasks (subagents start fresh and may need time to gather context).
- A simple side question about the existing conversation — use [`/btw`](https://code.claude.com/docs/en/interactive-mode) instead. (source: https://code.claude.com/docs/en/sub-agents)

If you want a reusable prompt that should see your conversation, choose [[ClaudeExperience/Workflows/Skills|skills]] instead.

## Definition + invocation

Custom subagents live in `.claude/agents/` (project) or `~/.claude/agents/` (user). Each runs with its own allowed-tools set, model, and permission mode. Tell Claude explicitly: "Use a subagent to review this code for security issues." Or `@`-mention to guarantee it runs.

To restrict a subagent's tools, use the `tools:` allowlist or `disallowedTools:` denylist in frontmatter. To preload domain knowledge, set `skills: [api-conventions, error-patterns]` — the full skill content is injected at startup.

For the full field list, see [[ClaudeExperience/Reference/SubagentFrontmatter]].

## Built-in subagents to know

- `Explore` (Haiku, read-only) — file discovery / search. Skips CLAUDE.md and git status for speed.
- `Plan` (inherits model, read-only) — research during plan mode.
- `general-purpose` (inherits, all tools) — complex multi-step research + action.

(source: https://code.claude.com/docs/en/sub-agents)

## Watch out for

- **Background subagents auto-deny anything that would prompt.** If a background subagent fails on missing permissions, restart it in the foreground.
- **Many parallel subagents that each return detailed results** still bloats main context. For sustained fan-out, use agent-teams.
- **Subagents cannot spawn other subagents.** Chain from the main conversation or use skills.

(source: https://code.claude.com/docs/en/sub-agents)

## Related pages

- [[ClaudeExperience/Workflows/Subagents]]
- [[ClaudeExperience/Reference/SubagentFrontmatter]]
- [[ClaudeExperience/AntiPatterns/InfiniteExploration]]
- [[ClaudeExperience/GoodPractices/ManageContext]]
- [[ClaudeExperience/Workflows/MultipleSessionsFanout]]
