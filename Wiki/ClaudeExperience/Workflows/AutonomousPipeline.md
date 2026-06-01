# Autonomous Pipeline (Kanban-driven multi-agent loop)

**Summary**: Pattern for running a self-managing build → QA → review pipeline over a backlog without per-step human prompting. State lives in a shared board (e.g. GitHub Projects); an orchestrator agent dispatches the right specialist based on which column a ticket is in.

**Sources**: https://www.youtube.com/watch?v=nX_bGyIOFM4

**Last updated**: 2026-05-24

---

## Shape

Four roles, all separate skill / subagent definitions:

| Role | Reads from column | Writes to column |
| --- | --- | --- |
| **Orchestrator** | scans all columns | moves tickets between stages |
| **Builder** | `building` | `qa` (success) / stays for revision |
| **QA** | `qa` | `review` (pass) / `building` (fail, with feedback) |
| **Reviewer** | `review` | `done` (approve + merge) / `building` (changes requested) |

Columns: `ready`, `building`, `qa`, `review`, `done`, `blocked`, `skipped`. The board IS the state machine — there's no separate workflow definition. Whichever column a ticket lands in determines which specialist will pick it up next (source: https://www.youtube.com/watch?v=nX_bGyIOFM4).

This mirrors the dispatcher pattern in Jerry's own [`AutoresearchSkill`](../../../../Skills/AutoresearchSkill.md) — a thin orchestrator that reads task state and dispatches the right phase worker.

## Lifecycle of one ticket

1. Human drops ticket in `ready` with title + body.
2. **Lint pass** before any dispatch — see [[ClaudeExperience/AntiPatterns/AutonomousDispatchVagueAC]]. Tickets without crisp acceptance criteria are flagged and held back.
3. Orchestrator pulls from `ready` → moves to `building` → invokes builder.
4. Builder opens PR, writes the change, comments back on the issue.
5. QA picks up from `qa` column, runs acceptance checks against AC.
   - Pass → `review`.
   - Fail → back to `building` with explicit feedback comment.
6. Reviewer reads diff + PR, runs code review.
   - Approve → squash-merge PR, move ticket to `done`.
   - Changes requested → back to `building` with feedback.
7. After N revisions (e.g. 3) → orchestrator moves ticket to `blocked` — needs human triage.

## Why the loops have to be bounded

Without a cap, an autonomous pipeline can grind forever on a task that's unsolvable from within the loop — needs a design decision, a production API key, a stripe coupon, a screenshot review. Two escape hatches keep the run finite (source: https://www.youtube.com/watch?v=nX_bGyIOFM4):

- **Max revision counter** — N failed builder→QA cycles → block.
- **Skipped column** — explicit human signal "don't touch this one in the loop" (e.g. payment integration that needs prod credentials).

Diagnose the bottleneck on blocked tickets: usually one column needs an extra specialist (e.g. a UX skill between `building` and `qa` to enforce the design system before QA bothers measuring it).

## Trigger surface

Designed to be kicked off from outside the IDE — Telegram message, scheduled cron, webhook (source: https://www.youtube.com/watch?v=nX_bGyIOFM4). Once started the orchestrator runs headless until the queue is empty or only `blocked`/`skipped` remain. Maps cleanly to [[ClaudeExperience/Workflows/NonInteractiveMode]] (`claude -p` per dispatch) and [[ClaudeExperience/Workflows/ScheduledRuns]].

## Caveats

- Single-source practitioner pattern (one YouTube creator) — concept is sound and generalises the dispatcher pattern already in this repo, but specific implementation details (column names, revision-cap value) are taste, not gospel.
- The lint preflight is the load-bearing step; skipping it converts the pipeline into a hallucination amplifier (see [[ClaudeExperience/AntiPatterns/AutonomousDispatchVagueAC]]).
- Verification still required per stage — auto-merging without QA gates is the [[ClaudeExperience/AntiPatterns/TrustThenVerifyGap]] anti-pattern at scale.

## Related pages

- [[ClaudeExperience/AntiPatterns/AutonomousDispatchVagueAC]]
- [[ClaudeExperience/AntiPatterns/HumanAsBottleneck]]
- [[ClaudeExperience/AntiPatterns/TrustThenVerifyGap]]
- [[ClaudeExperience/Workflows/Subagents]]
- [[ClaudeExperience/Workflows/NonInteractiveMode]]
- [[ClaudeExperience/Workflows/MultipleSessionsFanout]]
- [[ClaudeExperience/Workflows/ScheduledRuns]]
- [[ClaudeExperience/GoodPractices/UseSubagents]]
