# Scheduled Runs

**Summary**: Four ways to run Claude on a schedule, each with different tradeoffs around where the code executes, what files it can touch, and how long it survives. Pick by location, not just cadence.

**Sources**: https://code.claude.com/docs/en/common-workflows

**Last updated**: 2026-05-23

---

## Four options

| Option | Where it runs | Best for |
| --- | --- | --- |
| **Routines** | Anthropic-managed infra | Tasks that must run even when your machine is off. Also trigger on API calls or GitHub events, not just cron. |
| **Desktop scheduled tasks** | Your machine, via the desktop app | Tasks that need local files, local tools, or uncommitted changes. |
| **GitHub Actions** | Your CI pipeline | Tasks tied to repo events (opened PR, push) or cron schedules that should live next to your workflow config. |
| **`/loop`** | Current CLI session | Quick polling while a session is open. Tasks stop when you start a new conversation; `--resume` / `--continue` restore unexpired ones. |

(source: https://code.claude.com/docs/en/common-workflows)

## Prompting for unattended runs

The task runs without you, so it cannot ask clarifying questions. Be explicit about:

- **What success looks like** — a definite predicate, not "do a good job".
- **What to do with results** — file a PR, post to a channel, write to a file, exit silently.

Example: "Review open PRs labeled `needs-review`, leave inline comments on any issues, and post a summary in the `#eng-reviews` Slack channel." (source: https://code.claude.com/docs/en/common-workflows)

## Choosing between them

- Need **local file access** (uncommitted changes, secrets in your home dir, dev DB)? Desktop scheduled tasks.
- Need it to run while your **laptop is closed**? Routines.
- Tied to a **repo event** (PR opened, commit pushed)? GitHub Actions.
- Polling **during an active session** for state changes? `/loop`.

## Related pages

- [[ClaudeExperience/Workflows/NonInteractiveMode]]
- [[ClaudeExperience/GoodPractices/SpecificContext]]
