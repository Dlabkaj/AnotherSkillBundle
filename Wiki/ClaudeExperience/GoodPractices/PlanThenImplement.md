# PlanThenImplement

**Summary**: Separate research and planning from execution. Plan mode for explore + design; default mode for implement + commit. Avoids solving the wrong problem.

**Sources**: https://code.claude.com/docs/en/best-practices

**Last updated**: 2026-05-23

---

## The four-phase workflow

1. **Explore (plan mode)** — Claude reads files, builds a mental model. No writes.
   > "read /src/auth and understand how we handle sessions and login. also look at how we manage environment variables for secrets."
2. **Plan (plan mode)** — Claude produces a written plan you can edit. Press `Ctrl+G` to open the plan in your editor.
   > "I want to add Google OAuth. What files need to change? What's the session flow? Create a plan."
3. **Implement (default mode)** — Claude executes the plan.
   > "implement the OAuth flow from your plan. write tests for the callback handler, run the test suite and fix any failures."
4. **Commit** — descriptive message, PR.

## When to skip planning

Plan mode adds overhead. For tasks where scope is clear and fix is small — typos, log lines, single-line renames — ask Claude to do it directly. Heuristic: "If you could describe the diff in one sentence, skip the plan." (source: https://code.claude.com/docs/en/best-practices).

Planning is most useful when:
- You're uncertain about the approach.
- The change touches multiple files.
- You're unfamiliar with the code being modified.

## Structured interview before plan (office-hours pattern)

When you don't know what you actually want — common at the start of a feature — invert the conversation: ask Claude to interview you first. Garry Tan's `/office-hours` slash command forces Claude to ask 5-6 questions before any code is written: *what problem does it solve, who is it for, what does success look like, what should it not do.* Surfaces ambiguity you didn't know you had and prevents Claude from filling gaps with bad assumptions. (source: https://www.youtube.com/watch?v=GN0yhCt9qeo, Garry Tan / G-stack)

Pattern: paste a 6-question interview prompt up front, let Claude grill you, *then* enter plan mode.

## Related pages

- [[ClaudeExperience/Workflows/PlanMode]]
- [[ClaudeExperience/AntiPatterns/SkipPlanMode]]
- [[ClaudeExperience/GoodPractices/SpecificContext]]
