# HumanAsBottleneck

**Summary**: User stays interactively in the loop, prompting one step at a time, waiting for each agent reply before sending the next. The agent's token-throughput is throttled by the user's typing speed instead of the available compute.

**Sources**: https://www.youtube.com/watch?v=kwSVtQ7dziU

**Last updated**: 2026-05-23

---

## Observable symptoms

- One session, one task, hand-holding through every micro-step.
- Long idle gaps where the user is reading and the agent is waiting.
- Subscription quota unused at end of day — "you haven't maximized your token throughput".
- All work happens at the speed of one human reviewer.

## Why it breaks

Karpathy's framing: "to get the most out of the tools that have become available now you have to remove yourself as the as the bottleneck. You can't be there to prompt the next thing." (source: https://www.youtube.com/watch?v=kwSVtQ7dziU).

Each idle moment while you're waiting on Claude is a moment you could have spent prompting another agent. The Peter Steinberg pattern — multiple Codex agents tiling the monitor, each on a 20-minute high-effort run, moving between them to review and dispatch — exists because one agent is dramatically underused.

## Fix

- **Fan out** with `claude -p` and parallel sessions. See [[ClaudeExperience/Workflows/NonInteractiveMode]] and [[ClaudeExperience/Workflows/MultipleSessionsFanout]].
- **Auto-loops** — define objective, metric, boundaries; hit go. Karpathy's auto-research found tuning he had missed after two decades of hand-tuning the same kind of model (source: https://www.youtube.com/watch?v=kwSVtQ7dziU).
- **Macro actions, not micro** — delegate whole features ("here's a new functionality, agent one"), not individual lines.
- **Verifiable tasks first** — auto-loops only work where success is cheap to check. See [[ClaudeExperience/Reference/ModelJaggedness]] for which tasks qualify.

## Caveat

Don't auto-loop without verification — see [[ClaudeExperience/AntiPatterns/TrustThenVerifyGap]]. And without good prompts the parallel agents just produce more noise faster.

## Related pages

- [[ClaudeExperience/GoodPractices/MaximizeTokenThroughput]]
- [[ClaudeExperience/Workflows/MultipleSessionsFanout]]
- [[ClaudeExperience/Reference/ModelJaggedness]]
