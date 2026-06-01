# LongTermTaskSkill — Reference

Loaded on demand. Companion to [../LongTermTaskSkill.md](../LongTermTaskSkill.md). Skim only what you need.

---

## File formats

### `task.md`

```
GOAL: <free text — what done looks like overall>
METRICS:
  - <metric 1, deterministic if possible>
  - <metric 2>
ITER_LIMIT: 5
PARTIAL_ITER_LIMIT: 5
MODE: background
AUTO_RELAUNCH: true
```

### `partial-tasks.md`

```
- [01] data-collection: Collect all relevant raw source files
  status: pending
  repeatable: false
  iter_limit: 5
  iter_count: 0
- [02] fact-extraction: Extract verified facts into wiki
  status: pending
  repeatable: true
  iter_limit: 5
  iter_count: 0
```

Status vocab: `pending | in-progress | done | error | skipped`.

### `partial/<NN-slug>/partial.md`

```
GOAL: <one-paragraph description of this partial task>
METRICS:
  - <metric 1>
  - <metric 2>
REPEATABLE: true|false
ITER_LIMIT: 5
NOTES:
  <free-text context, hints, references>
```

### `partial/<NN-slug>/steps.md`

```
- [01] Read all .txt files in {{RAW_ROOT}}/foo/ and summarize each
  status: pending
- [02] For each summary, check if related wiki page exists
  status: pending
- [03] Write missing wiki pages
  status: pending
```

Step status vocab: `pending | done | error`.

### `progress.md`

```
STATUS: READY
ITER: 0
CURRENT_PARTIAL:
LAST_ERROR:
LAST_VERIFY:
AUTO_RELAUNCH_COUNT: 0
```

Task-level status vocab: `READY | RUNNING | COMPLETE | STOP_ITER_LIMIT | STOP_ERROR | STOP_BLOCKED | STOP_USER`.

---

## State script — `Skills/LongTermTaskSkill/longterm_state.py`

Reduces token cost: AI never parses MD files inline, calls these commands instead.

```
python Skills/LongTermTaskSkill/longterm_state.py init <task_dir>
python Skills/LongTermTaskSkill/longterm_state.py status <task_dir>
python Skills/LongTermTaskSkill/longterm_state.py next-partial <task_dir>
python Skills/LongTermTaskSkill/longterm_state.py next-step <task_dir> <partial_slug>
python Skills/LongTermTaskSkill/longterm_state.py mark-step <task_dir> <partial_slug> <step_id> <status> [error_msg]
python Skills/LongTermTaskSkill/longterm_state.py mark-partial <task_dir> <partial_slug> <status>
python Skills/LongTermTaskSkill/longterm_state.py inc-partial-iter <task_dir> <partial_slug>
python Skills/LongTermTaskSkill/longterm_state.py reset-steps <task_dir> <partial_slug> <step_id> [<step_id> ...]
python Skills/LongTermTaskSkill/longterm_state.py update <task_dir> KEY=VAL [KEY+=N ...]
python Skills/LongTermTaskSkill/longterm_state.py check-stop <task_dir>
```

`status` returns JSON with: status, iter, iter_limit, current_partial, last_error, should_exit, stop_reason, next_partial (full record), partial_counts, task fields.

---

## Background runner — `Skills/LongTermTaskSkill/Run-LongTermTask.ps1`

Loop:
1. Read state.
2. If `should_exit` → set terminal STATUS → exit.
3. Get `next_partial`.
4. Increment ITER, set CURRENT_PARTIAL.
5. Spawn `claude -p` with WORKER prompt.
6. If usage-limit detected in stdout → schedule Task Scheduler relaunch (if `AUTO_RELAUNCH: true`, cap 3) → exit.
7. Loop.

Stop conditions:
- `STOP.md` present
- STATUS in {COMPLETE, STOP_*}
- ITER >= ITER_LIMIT
- Any partial has status=error (runner halts; user must intervene)
- All partials done/skipped
- MaxIterations (script-level safety, default 30)

---

## Repeatable vs one-of

- **One-of** (`repeatable: false`): once `status: done`, never re-runs. WORKER must not call `inc-partial-iter` on a one-of task. If metric fails → mark error immediately.
- **Repeatable** (`repeatable: true`): WORKER may call `reset-steps` + `inc-partial-iter` up to `iter_limit` times. Beyond limit → mark error.

If user later asks "re-run partial X", they can manually reset its status via:
```
python Skills/LongTermTaskSkill/longterm_state.py mark-partial <task_dir> <slug> pending
```
And drop its `iter_count` to 0 by editing `partial-tasks.md`. Skill should warn user when they ask to re-run a one-of partial.

---

## STOP.md kill switch

Drop a `STOP.md` file (any content, even empty) in the task dir. Runner exits cleanly within one loop iteration. WORKER also checks at start of session.

---

## Verification & metrics

**Default**: AI judgment in WORKER session. After steps done, AI inspects artifacts and writes a short verdict to `LAST_VERIFY` via `update`.

**Script verification** (opt-in): per-metric `verify-cmd:` line in `partial.md`:
```
METRICS:
  - All Czech wiki pages have at least 3 sources
    verify-cmd: python Skills/LongTermTaskSkill/check_wiki_sources.py {{WIKI_ROOT}}/Foo/ --min 3
```
Exit 0 = pass. WORKER runs each verify-cmd; if all pass, partial done.

---

## Sibling scripts

- `Skills/SharedScripts/research_state.py` — sibling state script for AutoresearchSkill. Same design pattern; do not confuse the two.
- `Skills/SharedScripts/_runner-helpers.ps1` — shared PowerShell helpers: UsageLimit detection, `Invoke-UsageLimitHandler`, `Register-RelaunchTask`, `Invoke-WorkerSession`. Both `AutoresearchSkill/Run-Autoresearch.ps1` and `LongTermTaskSkill/Run-LongTermTask.ps1` dot-source it.
