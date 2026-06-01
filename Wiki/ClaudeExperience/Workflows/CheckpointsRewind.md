# Checkpoints and Rewind

**Summary**: Every prompt creates a checkpoint. `Esc + Esc` or `/rewind` restores conversation, code, or both — across sessions.

**Sources**: https://code.claude.com/docs/en/best-practices, https://code.claude.com/docs/en/how-claude-code-works

**Last updated**: 2026-05-24

---

## Controls

- `Esc` — stop Claude immediately. The running tool call is **canceled** and Claude waits for your next instruction (source: https://code.claude.com/docs/en/how-claude-code-works).
- **Type a correction + Enter mid-tool** — sends the message without stopping the running tool. Claude reads it as soon as the current action completes and adjusts before deciding its next step. Use this when you spot a wrong direction but the current tool call is still useful or harmless (source: https://code.claude.com/docs/en/how-claude-code-works).
- `Esc + Esc` or `/rewind` — open the rewind menu.
- "Undo that" — Claude reverts its last changes.
- `/clear` — full reset.

## Checkpoint scope and limits

- Every file edit is reversible — Claude snapshots file contents **before** each edit (source: https://code.claude.com/docs/en/how-claude-code-works).
- Checkpoints are **local to your session, separate from git**, and cover file changes only.
- Actions with **external side effects** (databases, APIs, deployments, sent messages) cannot be checkpointed. This is why Claude asks before running commands that touch remote systems — there is no undo (source: https://code.claude.com/docs/en/how-claude-code-works).

## Rewind menu choices

- Restore conversation only.
- Restore code only.
- Restore both.
- Summarize from a selected message (partial compaction).
- Summarize up to a selected message.

## Persistence

Checkpoints persist across sessions. Close the terminal, open it tomorrow, still rewind.

## Constraint

Checkpoints only track changes made by Claude, not external processes. Not a git replacement (source: https://code.claude.com/docs/en/best-practices).

## Use cases

- Risky refactors — try aggressively, rewind if it broke something subtle.
- Failed correction loops — rewind to before the wrong turn instead of correcting forward.
- Mid-task compaction — `/rewind` → "summarize from here" to trim accumulated noise.

## Related pages

- [[ClaudeExperience/GoodPractices/UseCheckpoints]]
- [[ClaudeExperience/GoodPractices/ManageContext]]
