---
name: AutoresearchSkill
disable-model-invocation: true
description: Orchestrates autonomous research. BOOTSTRAP only — interview user, write task brief, delegate candidate-list build to SourceScrapeSkill, print launch command. Runs background via PowerShell dispatcher that chains SourceScrapeSkill (FETCH) → IngestionSkill (INGEST) → IngestionReviewSkill (REVIEW).
triggers: ["autoresearch", "auto research", "research and fill wiki", "background research", "research topic", "deep research"]
---

# Autoresearch Skill (Orchestrator)

Owns the **research brief**, hard rules, and dispatcher logic. The actual work is delegated:

| Phase  | Skill                                                          | Runner                                                |
| ------ | -------------------------------------------------------------- | ----------------------------------------------------- |
| FETCH  | [SourceScrapeSkill](SourceScrapeSkill.md)                      | `Skills/SourceScrapeSkill/Run-SourceScrape.ps1`       |
| INGEST | [IngestionSkill](IngestionSkill.md)                            | `Skills/IngestionSkill/Run-Ingestion.ps1`             |
| REVIEW | [IngestionReviewSkill](IngestionReviewSkill.md)                | `Skills/IngestionReviewSkill/Run-IngestionReview.ps1` |

All task state lives in `{{RAW_ROOT}}/<topic-slug>/`. State script `Skills/SharedScripts/research_state.py` is the single source of truth — read/write via its `status / mark / update / check-stop` commands rather than parsing files by hand.

This skill runs **BOOTSTRAP mode only**. Sub-skills handle the WORKER mode loops.

> `{{RAW_ROOT}}` and `{{WIKI_ROOT}}` are placeholders resolved from `skillSettings.json` at the project root. See the repo `README.md` for the full token list.

---

## BOOTSTRAP

Run once at the start. Interview user, build task brief, delegate candidate-list build to SourceScrapeSkill, write progress.md, exit. **DO NOT fetch or ingest in this mode.**

### 1. Interview (AskUserQuestion)

Cover all of these. Use up to two batches of questions (max 4 per AskUserQuestion call):

**Batch 1:**
- **Scope**: what's in / out (free-text)
- **Research focus**: what information to optimize for — ask this explicitly. Examples: "chemical formulas and type localities", "economic and mining history", "Czech-specific occurrences", "biographical info on discoverers", "environmental impact". Free-text. This is the most important question.
- **Depth**: LOW (10 sources) / MEDIUM (25) / HIGH (40) — default MEDIUM
- **Language**: **English** / **Czech** — pick ONE for entire topic dir

**Batch 2 (if needed, max 4 questions):**
- **Sources**: web only / web + existing `{{RAW_ROOT}}/` files / Raw/ only
- **Wiki target**: existing folder or new (default: `{{WIKI_ROOT}}/<TopicPascalCase>/`)
- **Authoritative sources to prioritize** (free-text, optional)
- **Hard cap on sources scraped** (default 50)

**On token limit (`ON_LIMIT`)** — don't ask by default. Set from prompt keywords:
- Prompt contains "auto-relaunch", "auto relaunch", "schedule retry", or "keep going after limit" → `ON_LIMIT: relaunch`
- Otherwise → `ON_LIMIT: stop`

When `relaunch`, dispatcher registers a Task Scheduler one-shot job ~1 min after token reset. Caps at 3 auto-relaunches per task. User can always edit `task.md` to flip the flag later.

### 2. Write task brief

Create `{{RAW_ROOT}}/<topic-slug>/` (slug = kebab-case topic):

- **`task.md`** — frozen brief:
  ```
  TOPIC: <topic>
  SCOPE: <in/out>
  RESEARCH_FOCUS: <verbatim from user — what to optimize for>
  DEPTH: LOW|MEDIUM|HIGH
  LANGUAGE: English|Czech
  WIKI_TARGET: {{WIKI_ROOT}}/<Folder>/
  HARD_CAP: <N>
  AUTHORITATIVE: <list or none>
  ON_LIMIT: stop|relaunch
  ```
- **`progress.md`** — live state, this exact format:
  ```
  STATUS: READY_FETCH
  PHASE: FETCH
  ITER: 0
  SOURCES_FETCHED: 0
  SOURCES_INGESTED: 0
  SOURCES_SKIPPED: 0
  RECENT_EDIT_CHARS: []
  LAST_EDIT: (none)
  WIKI_PAGES_TOUCHED: []
  LAST_VERIFY: (none)
  ```

### 3. Delegate candidate-list build to SourceScrapeSkill

Invoke [SourceScrapeSkill](SourceScrapeSkill.md)'s **DISCOVER sub-protocol** synchronously. Pass it the inputs from `task.md`. It will:
- Run WebSearch angle queries scaled by depth
- Glob existing `{{RAW_ROOT}}/` files
- Write ranked `candidates.md` in the documented entry format (`- [type] [title] — [url]` + `snippet:` + `status: pending`)
- Append `NOTE: depth target=<N>, candidates found=<M>` to `task.md` if undershot

### 4. Tell user how to launch

Print launch command and exit. Terse, nothing extra.

```
Ready. Run before AFK:
  powershell -File Skills/AutoresearchSkill/Run-Autoresearch.ps1 -TaskDir {{RAW_ROOT}}/<slug>

Or from PowerShell prompt:
  .\Skills\AutoresearchSkill\Run-Autoresearch.ps1 -TaskDir {{RAW_ROOT}}\<slug>

Progress:   {{RAW_ROOT}}/<slug>/progress.md
Stop:       New-Item {{RAW_ROOT}}\<slug>\STOP.md
On limit:   <ON_LIMIT value> (edit task.md to change)
            relaunch -> Task Scheduler one-shot ~1 min after reset, max 3 attempts
            stop     -> dispatcher exits; relaunch manually

Permissions (required in .claude/settings.json -> permissions.allow):
  "Write(path:{{RAW_ROOT}}/**)"
  "Edit(path:{{RAW_ROOT}}/**)"
  "Write(path:{{WIKI_ROOT}}/**)"
  "Edit(path:{{WIKI_ROOT}}/**)"
```

---

## Dispatcher behavior

`Skills/AutoresearchSkill/Run-Autoresearch.ps1` is a thin outer loop that reads `PHASE` from `progress.md` and chains the matching sub-runner:

```
while STATUS not in (COMPLETE, STOP_*) and no STOP.md:
    PHASE = read from progress.md
    switch PHASE:
        FETCH  → & ..\SourceScrapeSkill\Run-SourceScrape.ps1     -TaskDir $TaskDir
        INGEST → & ..\IngestionSkill\Run-Ingestion.ps1           -TaskDir $TaskDir
        REVIEW → & ..\IngestionReviewSkill\Run-IngestionReview.ps1 -TaskDir $TaskDir
    if sub-runner reported USAGE_LIMIT_HIT → handle ON_LIMIT (schedule relaunch or break)
    re-read STATUS, loop
```

Valid phase progression: `FETCH` ⇄ `INGEST` → `REVIEW` → `COMPLETE`. (INGEST can bounce back to FETCH if it discovers new candidates mid-run; REVIEW runs once at the end.)

---

## Hard rules — WORKER mode

Sub-skills (SourceScrapeSkill, IngestionSkill, IngestionReviewSkill) inherit these whenever they run with `Mode: WORKER`.

**Universal rules** (no AskUserQuestion, no commits, STOP.md kill switch, ~80K context budget, hard context-pressure stop, no user-facing summaries) — see [SharedScripts/WORKER-rules.md](SharedScripts/WORKER-rules.md).

**Autoresearch-specific scope rules:**
- **NEVER write outside `{{RAW_ROOT}}/<task-slug>/` or `{{WIKI_ROOT}}/`.**
- **Single-language wiki.** Per `task.md` LANGUAGE. Every word in every wiki page is that language. Translate when ingesting from a different-language source.
- **Source budgeting note** — typical batch: 4-8 sources per session. Heuristic per source ≈ 8-15K tokens (raw file ~3-5K + wiki edits ~2-5K + tool calls/reasoning ~3-5K), plus ~10-15K fixed overhead. Use to estimate when 80K soft budget approaches.
- **Context-pressure mark** — when exiting under hard context-pressure mid-source, mark it `skipped (context limit — retry)`.

---

## State script reference

All deterministic bookkeeping is handled by `Skills/SharedScripts/research_state.py`. Use it instead of reading/writing state files manually.

```
python Skills/SharedScripts/research_state.py status <task_dir>         # JSON: phase, status, next_candidate, counts
python Skills/SharedScripts/research_state.py mark <task_dir> <url_substr> <status> [raw_path]
python Skills/SharedScripts/research_state.py update <task_dir> KEY=VAL ...   # KEY+=N appends to list
python Skills/SharedScripts/research_state.py check-stop <task_dir>     # JSON: {stop, reason}
```

Valid `STATUS` values: `READY_FETCH`, `READY_INGEST`, `READY_REVIEW`, `STOP_BLOCKED`, `STOP_DIMINISHING`, `COMPLETE`.
Valid `PHASE` values: `FETCH`, `INGEST`, `REVIEW`.
