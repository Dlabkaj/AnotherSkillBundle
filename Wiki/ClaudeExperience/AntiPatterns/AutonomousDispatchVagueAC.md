# AutonomousDispatchVagueAC

**Summary**: Dispatching tickets to headless / autonomous Claude sessions without crisp acceptance criteria. The agent can't ask back, so it fills the gap by hallucinating intent.

**Sources**: https://www.youtube.com/watch?v=nX_bGyIOFM4

**Last updated**: 2026-05-24

---

## Observable symptoms

- Issue body is a one-liner ("squashed pricing layout", "navbar feels off") with no measurable success criteria.
- Autonomous run completes "successfully" but the change addresses a different problem than intended.
- Revision counter climbs because each pass interprets the spec differently.
- Tickets end up blocked for "performance criteria not met" / "design not matching" — criteria that should have been explicit upfront.

## Why it breaks

In autonomous loops the agent can't pause to ask a clarifying question (source: https://www.youtube.com/watch?v=nX_bGyIOFM4). Whatever it can't disambiguate from the ticket, it has to guess. That guess then propagates downstream: builder builds the wrong thing, QA tests against the same vague spec and rubber-stamps it, reviewer either approves on inertia or rejects without enough signal for builder to fix on the next pass.

This is distinct from [[ClaudeExperience/AntiPatterns/VaguePrompts]] — in interactive mode you can recover from a bad prompt with one follow-up message. In autonomous mode the cost of vagueness compounds across the whole pipeline.

## Fix — lint preflight

Add an explicit lint step between "ticket ready" and "dispatch":

- Run a lint pass over each issue in the queue before kicking off the autonomous loop.
- Flag: missing acceptance criteria, unmeasurable language ("looks better", "feels right"), missing links to existing patterns / mock-ups, missing scope boundary (in / out of scope).
- The lint output is a list of suggested rewrites; approve / edit each before dispatch (source: https://www.youtube.com/watch?v=nX_bGyIOFM4).
- Only tickets that pass lint enter the autonomous queue.

Concrete checklist for an autonomous-ready ticket:

- **Measurable AC** — "Lighthouse mobile score ≥ 90", not "performant".
- **Visual targets** — paste mock-up image or link, not "make it nicer".
- **Out-of-scope explicit** — name what NOT to touch.
- **Reproducer if it's a bug** — exact steps, not "sometimes flaky".
- **Single concern** — split tickets that bundle multiple changes.

## Fix — max revision cap

Even with good AC, some tickets are unsolvable autonomously (need a real human design call, a production API token, a payment subscription). Cap revisions at N (e.g. 3) and auto-route to a `blocked` column when hit (source: https://www.youtube.com/watch?v=nX_bGyIOFM4). Stops the agent from grinding tokens on a task that needs a human.

## Related pages

- [[ClaudeExperience/AntiPatterns/VaguePrompts]]
- [[ClaudeExperience/Workflows/AutonomousPipeline]]
- [[ClaudeExperience/AntiPatterns/HumanAsBottleneck]]
- [[ClaudeExperience/GoodPractices/ProvideVerification]]
