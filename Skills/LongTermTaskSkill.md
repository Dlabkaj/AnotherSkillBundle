---
name: LongTermTaskSkill
description: Manage long-term tasks that don't fit in a single context session. Decompose into partial tasks, each runs in its own claude -p subprocess, metric-driven iteration, background autonomy via PowerShell runner.
triggers: ["long term task", "long-term task", "ltt", "create LTT", "run LTT", "new long term task"]
---

# LongTermTaskSkill

For goals too big for one session. Three layers:
- **Long Term Task (LTT)** — the overall goal + metrics + iteration cap
- **Partial Task** — a sub-goal with its own metrics + steps + own `claude -p` session
- **Step** — a single concrete action inside a partial task

Architecture mirrors AutoresearchSkill: state files + state script + PowerShell runner + `Mode: WORKER` dispatch.

> `{{LONGTERM_ROOT}}` resolves from `skillSettings.json`. See repo `README.md`.

**Reference docs loaded on demand:** file format schemas, full state-script API, background-runner internals, repeatable/one-of semantics, STOP.md, verification — see [LongTermTaskSkill/details.md](LongTermTaskSkill/details.md).

---

## Modes

- **CREATE** — user wants to build a new LTT. Interactive. Default if user says "create long term task", "new LTT", etc.
- **WORKER** — invoked by `LongTermTaskSkill/Run-LongTermTask.ps1` via `claude -p`. Executes one partial task. Detect via `Mode: WORKER` in the prompt + `Partial:` line.
- **MANUAL** — user wants to run next partial in current session (on-demand). Triggered by "run next LTT", "run LTT step", etc.

---

## Folder layout

```
{{LONGTERM_ROOT}}/<task-slug>/
├── task.md              # frozen brief
├── partial-tasks.md     # ordered list of partial tasks
├── progress.md          # live state
├── iter-log.txt         # dispatcher log
├── STOP.md              # (optional) kill switch
└── partial/
    ├── 01-<slug>/
    │   ├── partial.md   # goal, metrics, repeatable, iter_limit
    │   ├── steps.md     # steps with status
    │   └── log.txt
    └── 02-<slug>/
```

File-format schemas (`task.md`, `partial-tasks.md`, `partial.md`, `steps.md`, `progress.md`) and status vocabularies live in [details.md](LongTermTaskSkill/details.md#file-formats).

---

## CREATE workflow (interactive)

When user triggers a new LTT:

1. **Slug + folder**: ask for a short slug (kebab-case). Create `{{LONGTERM_ROOT}}/<slug>/` and `partial/` subdir.
2. **Overall goal**: ask user to describe the goal in 1–3 sentences. Push back if vague.
3. **Overall metrics**: propose 1–3 metrics. Each metric MUST be measurable. If a metric is fuzzy ("works well", "looks good"), refuse and propose a sharper alternative or get explicit user sign-off that it's AI-judgment only.
4. **Iteration limits + mode**: propose `ITER_LIMIT: 5`, `PARTIAL_ITER_LIMIT: 5`. Ask user: background or on-demand? Auto-relaunch on usage limit?
5. **Partial task breakdown**: propose 3–8 partial tasks. For each, ask:
   - slug + one-line summary
   - repeatable? (default: false unless task is inherently iterative like "review and revise")
6. **Steps per partial**: for each partial, propose 2–6 steps. Each step = a single concrete action a claude session can do in one turn.
7. **Confirm + write**: show full plan to user. On approval, write all files (see [details.md](LongTermTaskSkill/details.md#file-formats) for schemas).
8. **Initialize**: `python Skills/LongTermTaskSkill/longterm_state.py init <task_dir>`.
9. **Run mode handoff**:
   - **background**: launch `powershell -File Skills/LongTermTaskSkill/Run-LongTermTask.ps1 -TaskDir <abs_path>` in a separate terminal. Tell user how to stop it (`STOP.md` or Ctrl+C).
   - **on-demand**: tell user the trigger phrase ("run next LTT for <slug>") and exit.

**Push back on:**
- Vague goals ("get better at X")
- Goals with no measurable metric
- More than 10 partial tasks (too granular — bundle them)
- Steps that are multi-action ("research, write, review" — split into three steps)

---

## WORKER protocol (inside `claude -p` subprocess)

Detect: prompt contains `Mode: WORKER` AND `Partial: [<idx>] <slug>` AND `Task dir: <path>`.

Hard rules:
- **Universal WORKER rules** — see [SharedScripts/WORKER-rules.md](SharedScripts/WORKER-rules.md): no AskUserQuestion, no commits, STOP.md kill switch, ~80K context budget, no user-facing summaries.
- **LTT-specific scope**: stay in the partial dir + steps targets. No skill chaining outside the task dir / wiki.

Execution:

1. **Read partial config**: `partial/<idx>-<slug>/partial.md` and `partial/<idx>-<slug>/steps.md`.
2. **Mark partial in-progress**:
   ```
   python Skills/LongTermTaskSkill/longterm_state.py mark-partial <task_dir> <slug> in-progress
   ```
3. **For each pending step** (in order):
   - Execute the step (whatever it says).
   - **On success**: `python Skills/LongTermTaskSkill/longterm_state.py mark-step <task_dir> <slug> <step_id> done`
   - **On failure**: `python Skills/LongTermTaskSkill/longterm_state.py mark-step <task_dir> <slug> <step_id> error "<short reason>"` → then `mark-partial <slug> error` → `update LAST_ERROR=<reason>` → **exit immediately**. Do not continue.
4. **After all steps done**: evaluate the partial's METRICS.
   - **AI judgment** (default): inspect the artifacts the steps produced. Decide pass/fail per metric.
   - **Script verification** (if `verify-cmd:` present in `partial.md`): run the command. Exit code 0 = pass. See [details.md › Verification & metrics](LongTermTaskSkill/details.md#verification--metrics).
5. **Metric pass**: `mark-partial <slug> done`. Exit.
6. **Metric fail + repeatable + `iter_count < iter_limit`**:
   - Identify which steps' output was deficient (the smart re-run policy — don't blanket-reset).
   - `reset-steps <task_dir> <slug> <id1> <id2> ...` (only the steps you actually want redone)
   - `inc-partial-iter <task_dir> <slug>`
   - Exit. Partial stays `in-progress`. Runner will re-dispatch.
7. **Metric fail + (not repeatable OR `iter_count >= iter_limit`)**:
   - `mark-partial <slug> error`
   - `update LAST_ERROR="metric '<which>' failed after <iter_count> iterations: <short reason>"`
   - Exit.

**Atomicity rule**: a step is atomic. If interrupted mid-step, the step is marked error on next dispatch (or stays pending if mark-step wasn't called). Always call mark-step immediately after the work finishes.

Full state-script command reference: [details.md › State script](LongTermTaskSkill/details.md#state-script--skillslongtermtaskskilllongterm_statepy).

---

## MANUAL workflow (on-demand)

User says: "run next LTT for <slug>" or "run next partial".

1. `python Skills/LongTermTaskSkill/longterm_state.py status <task_dir>` → get next_partial.
2. If `should_exit`, tell user status and stop reason. Done.
3. Otherwise, prompt user: "Next partial: [NN] <slug> — <summary>. Run inline or spawn claude -p?"
4. **Inline**: execute the WORKER protocol above directly in the current session.
5. **Spawn**: launch `claude -p --dangerously-skip-permissions` with the same WORKER prompt the runner uses.

For one-shot, prefer **inline** to avoid extra session-startup cost when user is actively watching.

---

## Anti-patterns (what NOT to do)

- **Don't blanket-reset all steps when a metric fails.** Pick specific failing steps. Wastes tokens otherwise.
- **Don't ask the user questions in WORKER mode.** They're AFK. Make the best judgment, log it, exit.
- **Don't continue after a step errors.** Stop, log, let the user inspect.
- **Don't iterate a one-of partial.** Mark error and stop.
- **Don't run multiple partials in parallel.** Sequential only.
- **Don't write user-facing summaries when in WORKER mode.** Update state files, exit. The runner reports.
