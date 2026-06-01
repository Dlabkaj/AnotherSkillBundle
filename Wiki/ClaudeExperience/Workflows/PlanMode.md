# Plan Mode

**Summary**: A read-only mode where Claude explores and proposes a written plan without making changes. Used for the explore + plan phases before switching to default mode to implement.

**Sources**: https://code.claude.com/docs/en/best-practices, https://code.claude.com/docs/en/common-workflows

**Last updated**: 2026-05-23

---

## What it does

- No file writes, no destructive Bash. Reads are allowed.
- Output is a plan you can review and edit.
- `Ctrl+G` opens the plan in your text editor for direct editing before implementation.

## How to enter

- Launch in plan mode: `claude --permission-mode plan` (source: https://code.claude.com/docs/en/common-workflows)
- Toggle mid-session: press `Shift+Tab` to flip into (or out of) plan mode (source: https://code.claude.com/docs/en/common-workflows)

## Two-step usage

1. **Explore in plan mode**: "read /src/auth and understand how we handle sessions."
2. **Plan in plan mode**: "I want to add Google OAuth. Create a plan."

Then exit plan mode and ask Claude to implement from the plan.

## When to use

- Approach is uncertain.
- Change touches multiple files.
- You're unfamiliar with the code being modified.

## When to skip

"If you could describe the diff in one sentence, skip the plan" (source: https://code.claude.com/docs/en/best-practices). Plan mode is overhead for small changes — typos, log lines, single-line renames.

## Related pages

- [[ClaudeExperience/GoodPractices/PlanThenImplement]]
- [[ClaudeExperience/AntiPatterns/SkipPlanMode]]
