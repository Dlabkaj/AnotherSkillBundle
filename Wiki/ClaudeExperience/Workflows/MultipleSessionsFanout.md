# Multiple Sessions and Fan-Out

**Summary**: Multiple Claude sessions in parallel — worktrees, desktop, web — speed up development, enable isolated experiments, and unlock writer/reviewer workflows.

**Sources**: https://code.claude.com/docs/en/best-practices, https://code.claude.com/docs/en/common-workflows, https://code.claude.com/docs/en/how-claude-code-works

**Last updated**: 2026-05-24

---

## Modes

- **Worktrees** — separate CLI sessions in isolated git checkouts so edits don't collide.
- **Desktop app** — manage multiple local sessions visually, each in its own worktree.
- **Claude Code on the web** — sessions on Anthropic-managed cloud infrastructure in isolated VMs.
- **Agent teams** — automated coordination of multiple sessions with shared tasks, messaging, and a team lead.

## Quality patterns enabled

- **Writer / Reviewer**: Session A implements. Session B (fresh context, unbiased) reviews. Session A addresses feedback. Bias is the key — Claude in the original session is partial to the code it just wrote.
- **TDD split**: One session writes tests. Another writes code to pass them.
- **Assumption audit on vibe-coded projects**: Open a fresh session in the same project directory (empty context, full file access) and ask it to list every assumption made and write them to `assumptions.md`. Useful when *you* don't actually understand all the code your prior session(s) wrote. (source: https://www.youtube.com/watch?v=5PBmvx0eKL4)

## Session management

Name sessions with `/rename` — treat them like branches, each workstream gets its own persistent context.

```
claude --continue              # resume most recent in current dir (same session ID, appends)
claude --resume                # pick from a list (or /resume from inside a session) — same session ID
claude --fork-session          # copy history into a NEW session ID, original untouched
claude --from-pr <number>      # jump back to the session linked to a PR
claude --worktree feature-auth # start an isolated session in its own worktree
```

`/resume` picker shows sessions from the current worktree by default; keyboard shortcuts widen to other worktrees / projects (source: https://code.claude.com/docs/en/how-claude-code-works).

### Resume vs fork

| Action | Session ID | Original history |
| --- | --- | --- |
| `--continue` / `--resume` | Same ID, appends new messages | Mutated in place |
| `--fork-session` / `/branch` | **New ID** | Untouched — original remains for parallel exploration |

Fork when you want to try a different direction without disturbing a session you might come back to (source: https://code.claude.com/docs/en/how-claude-code-works).

### Branches vs sessions

Sessions are tied to **directories**, not branches. Switching branches inside a session changes the files Claude sees, but the conversation history stays the same — Claude remembers what you discussed before the switch. For truly parallel sessions per branch, use git worktrees (source: https://code.claude.com/docs/en/how-claude-code-works).

Sessions created via `gh pr create` are automatically linked to that PR; `--from-pr` or pasting the PR URL into the `/resume` picker re-enters them (source: https://code.claude.com/docs/en/common-workflows). Give names like `oauth-migration` so you can find them later.

## Don't exceed your attention bandwidth

Parallel sessions only pay off if you can actually review each one's output. Some practitioners run 10+ simultaneous Claude Code sessions; a working ceiling for most operators is **~5 concurrent sessions**. Past that, the failure mode is *blind approval* — you have nine other prompts waiting, so you rubber-stamp diffs without reading them. The bottleneck moves from Claude to your judgment, and you ship lower-quality work faster. (source: https://www.youtube.com/watch?v=GN0yhCt9qeo, austin.marchese)

Heuristic: if you couldn't summarize from memory what each session is doing right now, you have too many open. Close one before starting another.

This pairs with the [[ClaudeExperience/AntiPatterns/HumanAsBottleneck]] tradeoff — fan-out raises throughput, but only up to the point where you can still verify outputs.

## Execution environments

Same agentic loop, different host:

| Environment | Where code runs | Use case |
| --- | --- | --- |
| **Local** | Your machine | Default. Full access to files, tools, environment |
| **Cloud** | Anthropic-managed VMs | Offload tasks, work on repos you don't have locally |
| **Remote Control** | Your machine, controlled from a browser | Use the web UI while keeping execution local |

(source: https://code.claude.com/docs/en/how-claude-code-works)

## Related pages

- [[ClaudeExperience/GoodPractices/UseSubagents]]
- [[ClaudeExperience/Workflows/NonInteractiveMode]]
