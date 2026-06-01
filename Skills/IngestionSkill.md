---
name: IngestionSkill
disable-model-invocation: true
description: Read raw .txt source files, extract facts with cross-source verification, integrate into Wiki pages. One source per session. Used by AutoresearchSkill during INGEST phase. Can be invoked manually to ingest raw files into an existing wiki.
triggers: ["ingest sources", "ingest raw", "extract facts", "integrate into wiki"]
---

# Ingestion Skill

Read raw text sources, extract facts with verification, write into Wiki. One source per loop iteration — context budget rules in [AutoresearchSkill.md § Hard rules](AutoresearchSkill.md#hard-rules--worker-mode) cap each session at ~80K tokens / typically 4-8 sources.

State script: `Skills/SharedScripts/research_state.py` (commands `status / mark / update / check-stop`).

> `{{WIKI_ROOT}}` and `{{RAW_ROOT}}` resolve from `skillSettings.json`. See repo `README.md`.

## Invocation modes (auto-detect)

- **Orchestrated** — prompt contains `Mode: WORKER` AND `task.md` + `candidates.md` exist in `<task_dir>` → run INGEST loop per state machine.
- **Inline** — caller provides `raw_files=[...]` + `wiki_target=...` + `research_focus=...` + `language=...` → ingest each file in order, no progress tracking, no state files. Verification rules still apply.

When in WORKER mode, follow the hard rules in [AutoresearchSkill.md § Hard rules](AutoresearchSkill.md#hard-rules--worker-mode).

---

## INGEST loop (orchestrated mode)

Goal: one source at a time, deep fact extraction, wiki integration, verification.

1. **Get state**: `python Skills/SharedScripts/research_state.py status <task_dir>`. Note `iter_started_at = now`.
2. **Pre-check**: if `should_exit: true` → exit immediately. No summary, no report.
3. **Check transition**: if `next_candidate` is null:
   - If `candidate_counts.pending > 0` → `update <task_dir> PHASE=FETCH STATUS=READY_FETCH` → exit. (Dispatcher launches SourceScrapeSkill next.)
   - Otherwise → `update <task_dir> PHASE=REVIEW STATUS=READY_REVIEW` → exit. (Dispatcher launches IngestionReviewSkill next.)
4. **`next_candidate`** from status JSON is the current source to ingest.
5. **Ingest — atomic unit. Never mark `done` unless every step below completed** (AI judgment):
   - Read the raw file from `next_candidate.raw` path (or original path for pre-existing `{{RAW_ROOT}}/` files).
   - Use `RESEARCH_FOCUS` from `task.json` field in status output to guide extraction. Prioritize facts and content that serve the stated focus. Spend proportionally more depth on focus-relevant material.
   - If content is irrelevant / garbage after reading → `mark <task_dir> <url> skipped-ingest` → step 6.
   - Extract facts, integrate into wiki per the project's wiki conventions (page format, citations, wiki-links). All output in topic's chosen language.
   - **Citations must use the original URL**, not the raw .txt filename. The URL is in `next_candidate.url` and on the `SOURCE_URL:` line at the top of each raw file. Raw txt files are temporary and will be deleted.
   - **Conflict rule**: if a new fact contradicts something already written in the wiki, **do not overwrite**. Record both versions inline with their sources and flag with `⚠️ CONFLICT:`. Format: `⚠️ CONFLICT: Source A says X (source: A); Source B says Y (source: B). Needs resolution.`
   - **Verification pass — required before marking `done`**: for every crisp factual atom added (years, formulas, type localities, etymologies, namesakes, "first/largest/only" superlatives) → cross-check against ≥2 independent sources. Already-ingested raw files in this task count as a second source. If second source unavailable or blocked, mark claim `*(needs second source)*` inline.
   - Update `{{WIKI_ROOT}}/Index.md` and `{{WIKI_ROOT}}/Log.md`.
   - Measure `chars_added_this_scrape` (sum of lines added across wiki files).
   - `update <task_dir> SOURCES_INGESTED+=1 RECENT_EDIT_CHARS+=<chars> LAST_EDIT=<ISO timestamp> LAST_VERIFY=<short note>`
   - `mark <task_dir> <url> done`
6. **Post-ingest checks** — run `python Skills/SharedScripts/research_state.py check-stop <task_dir>`:
   1. If `stop: true` and reason starts with `status=STOP_` → already set, exit.
   2. If `stop: true` (hard cap or diminishing returns) → `update <task_dir> STATUS=STOP_DIMINISHING` (or `COMPLETE` for cap) → exit.
   3. **Permission wall** — 5 consecutive skipped with blocked/403/permission reason → `update <task_dir> STATUS=STOP_BLOCKED` + write NOTES (see SourceScrapeSkill format) → exit.
   4. **Context budget** — estimated cumulative tokens used in this session > **~80 000** → exit. STATUS stays `READY_INGEST` (current source is already `done`, runner starts fresh session for the next batch). See `Context budget` rule in hard rules.
   5. Otherwise → loop to step 1.
7. Exit.

---

## Diminishing returns table — applies to INGEST phase only

Trigger STOP_DIMINISHING **only** when both columns satisfied. "Yield feels low" is not a stop condition. Min thresholds are ~50% of the depth source target — gives the run a real shot before allowing early stop.

| Depth  | Target sources | Min SOURCES_INGESTED before stop | Stop if last N RECENT_EDIT_CHARS all < X |
| ------ | -------------- | -------------------------------- | ---------------------------------------- |
| LOW    | 10             | 5                                | last 3 < 200                             |
| MEDIUM | 25             | 12                               | last 3 < 100                             |
| HIGH   | 40             | 20                               | last 5 < 100                             |

`skipped-ingest` sources do NOT push entries into RECENT_EDIT_CHARS.

---

## Adding new candidates mid-research

If a scraped source links to a clearly-better source not in `candidates.md`, append it (status: `pending`, source: `discovered-from-<existing>`). Max 2 additions per iteration. Adding `pending` mid-ingest will trigger a fetch round on next phase transition check (dispatcher returns to SourceScrapeSkill).

---

## Verification traps (from past runs)

- **Year of description ≠ year of naming.** Older minerals described decades before accepted name. Label clearly: `(described YYYY)` / `(named YYYY)`.
- **Etymology vs alias.** Check *which name* is "named after X" — canonical name vs nickname.
- **Conflated superlatives.** If two pages both claim "largest crystals up to N cm", one borrowed from the other. Verify independently.
- **Stale aggregate stats.** "X of ~4000 IMA species" type figures decay — cite year of count.

---

## Wiki layout (new topics)

`{{WIKI_ROOT}}/<TopicPascalCase>/`:
- `Index.md` — landing page, summary, links to sub-pages
- `<Concept>.md` — one per major sub-concept that accumulates >300 chars

Follow the project's wiki page-format conventions.
Update root `{{WIKI_ROOT}}/Index.md` to link new folder.

---

## Inline mode

Caller supplies `raw_files=[...]` + `wiki_target={{WIKI_ROOT}}/Foo/` + `research_focus="..."` + `language=English|Czech`.

For each file in order:
1. Read it. If first line is `SOURCE_URL: <url>`, that's the citation source.
2. Extract facts per `research_focus`, write into `wiki_target` following the same rules above (citations, conflicts, verification pass).
3. Print a one-line summary of chars added per file.

No `progress.md` writes. No state script. No diminishing-returns stop — caller decides when enough is enough by what they passed in.
