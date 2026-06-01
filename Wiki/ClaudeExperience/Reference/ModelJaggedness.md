# Model Jaggedness — On-Rails vs Off-Rails

**Summary**: Frontier models are simultaneously brilliant and dumb depending on whether the task is in their reinforcement-learning target. Verifiable tasks → on rails, near-superhuman. Soft / nuanced tasks → off rails, mediocre.

**Sources**: https://www.youtube.com/watch?v=kwSVtQ7dziU, https://www.youtube.com/watch?v=96jN2OCOfLs

**Last updated**: 2026-05-24

---

## The phenomenon

Karpathy: "I simultaneously feel like I'm talking to an extremely brilliant PhD student who's been like a systems programmer for their entire life and a 10-year-old. ... You're either on rails and you're part of the super intelligence circuits or you're not on rails and you're outside of the verifiable domains and suddenly everything kind of just like meanders." (source: https://www.youtube.com/watch?v=kwSVtQ7dziU).

## Why

These models are trained heavily with RL. Verifiable tasks (does the code compile, does the unit test pass, does the proof check) have direct rewards. Non-verifiable tasks (write a good joke, judge nuance, know when to ask a clarifying question) do not — so they stay frozen at ~5-year-old behavior even as code skills improve dramatically.

Diagnostic: ask ChatGPT for a joke. You'll get the same handful of jokes that frontier models told 3-4 years ago, because joke quality wasn't in the RL target.

**Current canary (2026-05)**: Karpathy at AI Ascent 2026 — "state-of-the-art Opus 4.7 will simultaneously refactor a 100,000-line codebase or find zero-day vulnerabilities, and yet tells me to walk to a car wash that's 50 m away when I asked whether to drive or walk." Real-world spatial / common-sense reasoning is still off-rails even as code skills go superhuman (source: https://www.youtube.com/watch?v=96jN2OCOfLs). Use this when judging which side of the rails your task is on — if the cognition resembles the car-wash question more than the refactor, stay in the loop.

Karpathy adds that jaggedness is **partly a function of what labs happened to add to training**: chess capability jumped from GPT-3.5 → GPT-4 not because of general progress but because someone at OpenAI added a large chess corpus. Implication: if your domain didn't make it into the data mix, you may need fine-tuning to reach the on-rails behavior labs get for free in their target domains (source: https://www.youtube.com/watch?v=96jN2OCOfLs).

## On-rails tasks (push throughput, auto-loop, trust output more)

- Writing CUDA kernels with measurable speedup vs. reference behavior.
- Refactors with a test suite.
- Bug fixes with a reproducer.
- Hyperparameter optimization with a loss metric.
- Mechanical migrations (`for file in ...; do claude -p ...`).

## Off-rails tasks (stay in the loop, expect mediocrity, verify human-judged outputs)

- Knowing when to ask clarifying questions instead of guessing.
- Detecting that a request is malformed.
- Producing genuinely novel writing, jokes, or design taste.
- Nuanced ethical or political tradeoffs.
- Saying "I don't know" honestly.

## How to apply

- Before deciding to fan out or auto-loop, ask: can I verify the output mechanically? If no → stay interactive.
- When Claude wastes compute on something obviously wrong: jaggedness, not capability degradation. Restart with a sharper prompt or different angle.
- Frontier labs will keep extending the rails. Today's off-rails task may be on-rails next quarter.

## Related pages

- [[ClaudeExperience/GoodPractices/MaximizeTokenThroughput]]
- [[ClaudeExperience/GoodPractices/ProvideVerification]]
- [[ClaudeExperience/AntiPatterns/HumanAsBottleneck]]
