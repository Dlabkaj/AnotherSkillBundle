# SkipPlanMode

**Summary**: Jumping straight to code on a task that touches multiple files or has an unclear approach. Claude produces a plausible implementation that solves the wrong problem because the problem was never spec'd.

**Sources**: https://code.claude.com/docs/en/best-practices

**Last updated**: 2026-05-23

---

## Observable symptoms

- Task spans multiple files; user starts with "implement X" without an explore step.
- First diff is large and only loosely tied to what the user wanted.
- Mid-task pivots ("actually, do it like Y") that imply the design wasn't shared up front.

## Why it breaks

Letting Claude jump straight to coding can produce code that solves the wrong problem (source: https://code.claude.com/docs/en/best-practices). Without a plan, both sides discover the design mid-implementation, which means rework and context pollution.

## When skipping plan mode IS fine

For tasks where the scope is clear and the fix is small — typos, log lines, renaming a variable — planning is overhead. "If you could describe the diff in one sentence, skip the plan" (source: https://code.claude.com/docs/en/best-practices).

## Fix

Use the explore → plan → implement → commit workflow:

1. **Explore (plan mode)**: "read `/src/auth` and understand how sessions work."
2. **Plan (plan mode)**: "I want to add Google OAuth. What files change? Create a plan." `Ctrl+G` opens the plan in your editor for direct editing.
3. **Implement (default mode)**: "implement the OAuth flow from your plan. write tests, run them, fix failures."
4. **Commit**: "commit with a descriptive message and open a PR."

See [[ClaudeExperience/Workflows/PlanMode]] and [[ClaudeExperience/GoodPractices/PlanThenImplement]].

## Related pages

- [[ClaudeExperience/Workflows/PlanMode]]
- [[ClaudeExperience/GoodPractices/PlanThenImplement]]
- [[ClaudeExperience/AntiPatterns/VaguePrompts]]
