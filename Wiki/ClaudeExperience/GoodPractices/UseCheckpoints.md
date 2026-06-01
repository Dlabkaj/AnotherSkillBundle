# UseCheckpoints

**Summary**: Every prompt creates a checkpoint. Use `/rewind` or `Esc + Esc` to restore conversation, code, or both. Trade caution for speed: tell Claude to try something risky, rewind if it goes wrong.

**Sources**: https://code.claude.com/docs/en/best-practices

**Last updated**: 2026-05-23

---

## Mechanics

- Each prompt sent = a checkpoint.
- Claude snapshots files before each change.
- `Esc + Esc` or `/rewind` opens the rewind menu.
- Choose: restore conversation only, code only, both, or "summarize from a selected message".
- Checkpoints persist across sessions — close terminal, rewind later.

## When to use

- **Risky experiment** — let Claude try an aggressive refactor; rewind if it breaks something subtle.
- **Failed correction loop** — see [[ClaudeExperience/AntiPatterns/RepeatedCorrections]]. Rewind to before the wrong turn, retry with a sharper prompt.
- **Compact mid-task** — "summarize from this message" trims accumulated noise while keeping recent work.

## Limits

Checkpoints only track changes made by Claude, not external processes (your own edits, build outputs, etc.). This is **not** a replacement for git (source: https://code.claude.com/docs/en/best-practices).

## Related pages

- [[ClaudeExperience/Workflows/CheckpointsRewind]]
- [[ClaudeExperience/GoodPractices/ManageContext]]
- [[ClaudeExperience/AntiPatterns/RepeatedCorrections]]
