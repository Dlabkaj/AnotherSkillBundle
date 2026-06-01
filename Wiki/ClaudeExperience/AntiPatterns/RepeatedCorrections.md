# RepeatedCorrections

**Summary**: User corrects Claude on the same issue more than twice in one session. Context is now polluted with failed approaches — every subsequent attempt sees them and may re-anchor on them.

**Sources**: https://code.claude.com/docs/en/best-practices

**Last updated**: 2026-05-23

---

## Observable symptoms

- "No, not like that" appears repeatedly in the conversation.
- Claude makes the same class of mistake after explicit correction.
- Tone slides toward repetitive "you're right, let me fix that".

## Why it breaks

After two failed corrections, the context contains both the wrong attempt(s) and the corrections. The signal-to-noise ratio drops; useful instructions get diluted (source: https://code.claude.com/docs/en/best-practices).

## Fix

- After two corrections on the same issue: `/clear` and start fresh with a better initial prompt that incorporates what you learned.
- Course-correct early via `Esc` to stop mid-action while context is preserved.
- Use `Esc + Esc` / `/rewind` to roll back conversation and code to a clean checkpoint.

A clean session with a better prompt almost always outperforms a long session with accumulated corrections (source: https://code.claude.com/docs/en/best-practices).

## Related pages

- [[ClaudeExperience/AntiPatterns/KitchenSinkSession]]
- [[ClaudeExperience/GoodPractices/ManageContext]]
- [[ClaudeExperience/Workflows/CheckpointsRewind]]
