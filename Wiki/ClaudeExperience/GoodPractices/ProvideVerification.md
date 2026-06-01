# ProvideVerification

**Summary**: Give Claude a way to check its own work — tests, screenshots, expected outputs, lint commands. Anthropic calls this "the single highest-leverage thing you can do".

**Sources**: https://code.claude.com/docs/en/best-practices

**Last updated**: 2026-05-23

---

## Why

Claude performs dramatically better when it can verify its own work, like run tests, compare screenshots, validate outputs. Without clear success criteria, it might produce something that looks right but actually doesn't work (source: https://code.claude.com/docs/en/best-practices).

## How to provide verification

- **Inline test cases** in the prompt. "implement `validateEmail`. cases: `user@example.com` true, `invalid` false, `user@.com` false. run the tests after implementing."
- **Visual diff for UI**. Paste the target screenshot, ask Claude to screenshot the result and compare. The Claude in Chrome extension supports this for live pages.
- **Build / lint commands**. Tell Claude the exact command to run after the change.
- **Reproducer first, fix second**. For bugs: "write a failing test that reproduces, then fix it."

## Investment pays back

"Your verification can also be a test suite, a linter, or a Bash command that checks output. Invest in making your verification rock-solid." (source: https://code.claude.com/docs/en/best-practices). Solid verification turns into auto-mode-safe loops where Claude iterates without human-in-the-loop on every step.

## Related pages

- [[ClaudeExperience/AntiPatterns/TrustThenVerifyGap]]
- [[ClaudeExperience/AntiPatterns/SuppressErrorRoot]]
- [[ClaudeExperience/GoodPractices/SpecificContext]]
