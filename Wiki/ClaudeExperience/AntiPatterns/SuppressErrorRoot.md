# SuppressErrorRoot

**Summary**: Prompt asks Claude to "fix the build" or "make the error go away". Claude takes the shortest path — try/except, default value, comment out the failing assertion. Symptom hidden, root cause untouched.

**Sources**: https://code.claude.com/docs/en/best-practices

**Last updated**: 2026-05-23

---

## Observable symptoms

- Diff adds a broad `try/except` swallowing the failure.
- Failing test gets skipped instead of fixed.
- A `// TODO` comment replaces real handling.
- Mysterious default value appears where the real value should come from upstream.

## Why it breaks

The bug is still there, hidden. It'll resurface in production, in CI later, or in a downstream caller. "Address root causes, not symptoms" (source: https://code.claude.com/docs/en/best-practices).

## Fix

Phrase the prompt so the root-cause expectation is explicit:

> "the build fails with this error: [paste error]. fix it and verify the build succeeds. address the root cause, don't suppress the error."

Always paste the actual error text — Claude can't fix what it can't read. Pair with [[ClaudeExperience/GoodPractices/ProvideVerification]] so the fix has a concrete success check.

## Related pages

- [[ClaudeExperience/AntiPatterns/TrustThenVerifyGap]]
- [[ClaudeExperience/GoodPractices/ProvideVerification]]
- [[ClaudeExperience/GoodPractices/SpecificContext]]
