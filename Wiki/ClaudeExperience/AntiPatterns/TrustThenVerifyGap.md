# TrustThenVerifyGap

**Summary**: Claude produces a plausible-looking implementation. User reviews superficially, ships it, then discovers it fails on edge cases or doesn't compile. No verification step was ever defined.

**Sources**: https://code.claude.com/docs/en/best-practices

**Last updated**: 2026-05-23

---

## Observable symptoms

- Task is accepted with no test, screenshot, or runnable check.
- "Looks good to me" without running the code.
- Bug reports surface days later for code Claude wrote.
- Prompts ask for behavior in prose; no example inputs/outputs given.

## Why it breaks

Without clear success criteria, Claude might produce something that looks right but actually doesn't work. Verification is "the single highest-leverage thing you can do" — Claude performs dramatically better when it can verify its own work (source: https://code.claude.com/docs/en/best-practices).

## Fix

Before asking Claude to implement anything, define how the result will be checked:

- Provide example test cases inline. "validateEmail: `user@example.com` true, `invalid` false."
- Ask Claude to run the tests after implementing.
- For UI changes: paste a target screenshot, ask Claude to screenshot the result and diff.
- For build/error fixes: provide the exact error, ask Claude to fix the root cause, ask it to verify the build succeeds.

See [[ClaudeExperience/GoodPractices/ProvideVerification]] for the full pattern.

## Related pages

- [[ClaudeExperience/GoodPractices/ProvideVerification]]
- [[ClaudeExperience/AntiPatterns/SuppressErrorRoot]]
- [[ClaudeExperience/AntiPatterns/VaguePrompts]]
