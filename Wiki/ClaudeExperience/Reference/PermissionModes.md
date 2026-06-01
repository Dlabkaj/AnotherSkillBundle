# Permission Modes

**Summary**: Six modes control when Claude pauses to ask before editing files, running shell commands, or making network requests. Cycle with `Shift+Tab` in the CLI; some modes require startup flags.

**Sources**: https://code.claude.com/docs/en/best-practices, https://code.claude.com/docs/en/permission-modes

**Last updated**: 2026-05-24

---

## Modes at a glance

| Mode | Runs without asking | Best for |
| --- | --- | --- |
| `default` | Reads only | Getting started, sensitive work |
| `acceptEdits` | Reads + file edits + `mkdir/touch/rm/rmdir/mv/cp/sed` inside cwd | Iterating on code you'll review afterwards |
| `plan` | Reads only (no writes at all) | Exploring a codebase before changing it |
| `auto` | Everything, with a classifier model gating risky actions | Long tasks, reducing prompt fatigue |
| `dontAsk` | Only `permissions.allow` tools + read-only Bash | Locked-down CI / pre-approved scripts |
| `bypassPermissions` | Everything, no safety checks | Isolated containers / VMs only |

In every mode except `bypassPermissions`, writes to [protected paths](#protected-paths) are never auto-approved. (source: https://code.claude.com/docs/en/permission-modes)

## Switching modes

- `Shift+Tab` cycles `default → acceptEdits → plan`. (source: https://code.claude.com/docs/en/permission-modes)
- `auto` only appears in the cycle when your account meets the [auto-mode requirements](#auto-mode-requirements).
- `bypassPermissions` only appears after starting with `--permission-mode bypassPermissions`, `--dangerously-skip-permissions`, or `--allow-dangerously-skip-permissions`.
- `dontAsk` is never in the cycle — set via `--permission-mode dontAsk`.
- Persist a default in `settings.json` via `"permissions": { "defaultMode": "..." }`. (source: https://code.claude.com/docs/en/permission-modes)

## `acceptEdits` details

Auto-approves file edits and the common filesystem Bash commands above, including when prefixed with safe env wrappers (`LANG=C`, `NO_COLOR=1`) or process wrappers (`timeout`, `nice`, `nohup`). Auto-approval applies only to paths inside the working directory or `additionalDirectories`. Anything outside, writes to protected paths, and all other Bash still prompt. (source: https://code.claude.com/docs/en/permission-modes)

## Plan mode details

Plan mode = read-only research that ends with a proposed plan. Enter with `Shift+Tab` or by prefixing one prompt with `/plan`. CLI: `claude --permission-mode plan`. (source: https://code.claude.com/docs/en/permission-modes)

When the plan is ready Claude asks how to proceed:

- Approve and start in `auto` mode
- Approve and `acceptEdits`
- Approve and review each edit manually
- Keep planning with feedback
- Refine with **Ultraplan** (browser-based review)

Approving switches the session to whichever mode you picked, so Claude starts editing. To plan again, cycle back to plan mode. Press `Ctrl+G` to open the proposed plan in your default editor before Claude proceeds. (source: https://code.claude.com/docs/en/permission-modes)

Set as project default in `.claude/settings.json`: `"permissions": { "defaultMode": "plan" }`. See [[ClaudeExperience/Workflows/PlanMode]].

## Auto mode details

Requires Claude Code v2.1.83+. A separate classifier model reviews every action that would otherwise prompt. Auto mode also nudges Claude to keep working without stopping for clarifying questions. (source: https://code.claude.com/docs/en/permission-modes)

### Auto-mode requirements

- **Plan**: all plans
- **Admin**: Team/Enterprise admins must enable it
- **Model**: Sonnet 4.6, Opus 4.6, or Opus 4.7 (older models including Sonnet 4.5, Opus 4.5, Haiku, and claude-3 are not supported)
- **Provider**: Anthropic API only — not Bedrock, Vertex, or Foundry

### Classifier defaults

Blocks by default: `curl | bash`-style download-and-exec, sending sensitive data to external endpoints, production deploys/migrations, mass cloud-storage deletion, granting IAM/repo perms, modifying shared infra, irreversible destruction of pre-existing files, force push, pushing direct to main.

Allows by default: local file ops in cwd, installing deps declared in lock files / manifests, reading `.env` and sending creds to their matching API, read-only HTTP, pushing to the branch you started on or one Claude created. (source: https://code.claude.com/docs/en/permission-modes)

### Boundaries you state in conversation

Telling Claude "don't push" or "wait until I review" is treated as a block signal by the classifier and stays in force until you lift it. **Boundaries are not stored as rules** — the classifier re-reads them from the transcript on each check, so a boundary can be lost if context compaction removes the message that stated it. For a hard guarantee, add a `deny` rule. (source: https://code.claude.com/docs/en/permission-modes)

### Fallback to prompts

3 consecutive blocks OR 20 total blocks pauses auto mode and Claude Code resumes prompting. Approving the prompted action resumes auto mode. Thresholds are not configurable. With `-p` (non-interactive), repeated blocks abort the session. Denied actions appear in `/permissions` under **Recently denied**; press `r` to retry with manual approval. (source: https://code.claude.com/docs/en/permission-modes)

### Decision order

First match wins:
1. `permissions.allow` / `deny` rules
2. Read-only actions and edits in cwd (auto-approved, except writes to protected paths)
3. Classifier
4. If classifier blocks, Claude sees the reason and tries an alternative

On entering auto mode, broad allow rules granting arbitrary code execution are dropped (`Bash(*)`, `PowerShell(*)`, `Bash(python*)`, package-manager run commands, `Agent` allow rules). Narrow rules like `Bash(npm test)` carry over. Dropped rules are restored when you leave auto mode. (source: https://code.claude.com/docs/en/permission-modes)

The classifier sees user messages, tool calls, and CLAUDE.md content. Tool results are stripped so hostile content in a file or web page cannot manipulate the classifier directly. (source: https://code.claude.com/docs/en/permission-modes)

### Auto mode + subagents

The classifier checks subagent work at three points: (1) before the subagent starts (its delegation task description), (2) each tool call while it runs (parent's rules apply; `permissionMode` in subagent frontmatter is ignored), (3) on finish (full action history review; flagged concerns prepend a security warning to the subagent's result). (source: https://code.claude.com/docs/en/permission-modes)

## `dontAsk` mode

Auto-denies every tool call that would prompt. Only `permissions.allow` rules and read-only Bash execute; explicit `ask` rules are denied rather than prompting. Fully non-interactive — designed for CI pipelines where you pre-define exactly what Claude may do. (source: https://code.claude.com/docs/en/permission-modes)

## `bypassPermissions` mode

Disables permission prompts AND safety checks. As of v2.1.126 this includes writes to protected paths (earlier versions still prompted). `rm -rf /` and `rm -rf ~` still prompt as a circuit breaker. Cannot enter from a session not started with one of the enabling flags — restart with `--permission-mode bypassPermissions` or `--dangerously-skip-permissions`. Refused at startup on Linux/macOS when running as root or under sudo. **No protection against prompt injection.** For background safety without prompts, use `auto` instead. (source: https://code.claude.com/docs/en/permission-modes)

## Protected paths

Writes are never auto-approved in any mode except `bypassPermissions`. In default/acceptEdits/plan they prompt; in auto they route to the classifier; in dontAsk they are denied.

Protected directories:
- `.git`
- `.vscode`
- `.idea`
- `.husky`
- `.claude` — except `.claude/commands`, `.claude/agents`, `.claude/skills`, `.claude/worktrees` where Claude routinely creates content

Protected files:
- `.gitconfig`, `.gitmodules`
- `.bashrc`, `.bash_profile`, `.zshrc`, `.zprofile`, `.profile`
- `.ripgreprc`
- `.mcp.json`, `.claude.json`

(source: https://code.claude.com/docs/en/permission-modes)

## Related pages

- [[ClaudeExperience/Workflows/PlanMode]]
- [[ClaudeExperience/Workflows/NonInteractiveMode]]
- [[ClaudeExperience/Workflows/Hooks]]
- [[ClaudeExperience/GoodPractices/SpecificContext]]
