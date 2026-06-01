# MaximizeTokenThroughput

**Summary**: Treat tokens like GPU-hours — wasted capacity is wasted leverage. Fan out, auto-loop, and arrange tasks so they can run without you in the loop.

**Sources**: https://www.youtube.com/watch?v=kwSVtQ7dziU

**Last updated**: 2026-05-23

---

## The reframe

Karpathy: "If you're not maximizing your subscription at least. And ideally for multiple agents... I feel nervous when I have subscription left over. That just means I haven't maximized my token throughput" (source: https://www.youtube.com/watch?v=kwSVtQ7dziU). Same intuition as a PhD student feeling nervous when GPUs are idle — flops became tokens.

## How to push throughput

- **Multiple sessions, multiple repos** — worktrees or web sandboxes for parallel work. See [[ClaudeExperience/Workflows/MultipleSessionsFanout]].
- **Fan out non-interactively** — `claude -p` across a task list. See [[ClaudeExperience/Workflows/NonInteractiveMode]].
- **Auto-loops over verifiable metrics** — set objective + metric + boundaries + go. Karpathy's auto-research overnight found tunings he had missed after two decades of hand-tuning the same kind of model.
- **Run multiple labs / subscriptions** — if Codex quota is out, switch to Claude. The constraint is your token budget, not any single vendor.

## When NOT to push throughput

- **Non-verifiable tasks** — without a cheap success check, fanning out just produces more unreviewable output. See [[ClaudeExperience/Reference/ModelJaggedness]].
- **Soft / nuanced work** — anything outside the reinforcement-learning targets degrades when run on rails.
- **Risky writes to shared state** — multiple agents touching the same files cause merge hell. Worktrees mitigate.

## Cultural shift

"The customer is not the human anymore. It's like agents who are acting on behalf of humans" (source: https://www.youtube.com/watch?v=kwSVtQ7dziU). Pricing, UIs, and APIs are starting to reflect that — increasingly, you build the system so it can run when you're not there.

## Related pages

- [[ClaudeExperience/AntiPatterns/HumanAsBottleneck]]
- [[ClaudeExperience/Workflows/NonInteractiveMode]]
- [[ClaudeExperience/Workflows/MultipleSessionsFanout]]
- [[ClaudeExperience/Reference/ModelJaggedness]]
