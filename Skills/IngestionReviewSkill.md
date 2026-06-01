---
name: IngestionReviewSkill
disable-model-invocation: true
description: One-shot cross-wiki consistency check after autoresearch ingestion. Reads recently-touched wiki pages, fixes citation errors, flags conflicts and single-source superlatives, writes review_notes.md. Used by AutoresearchSkill as the final REVIEW phase. Can be invoked manually on any set of wiki pages.
triggers: ["review wiki", "ingestion review", "consistency check", "cross-check wiki pages"]
---

# Ingestion Review Skill

Cross-wiki consistency pass run as the final phase of an autoresearch task. Single session, no iteration. Fixes clear errors in place, flags uncertain claims with markers.

State script: `Skills/SharedScripts/research_state.py` (read-only — `status` to get `WIKI_PAGES_TOUCHED`).

> `{{WIKI_ROOT}}` resolves from `skillSettings.json`. See repo `README.md`.

## Invocation modes (auto-detect)

- **Orchestrated** — prompt contains `Mode: WORKER` AND `task.md` + `progress.md` with `PHASE=REVIEW` exist in `<task_dir>` → read `WIKI_PAGES_TOUCHED` from progress.md, run checklist, write `review_notes.md`, set `STATUS=COMPLETE`.
- **Inline** — caller provides `wiki_pages=[...]` directly → run checklist on those pages, print summary, no `review_notes.md`.

When in WORKER mode, follow the hard rules in [AutoresearchSkill.md § Hard rules](AutoresearchSkill.md#hard-rules--worker-mode).

---

## REVIEW loop (orchestrated mode)

1. **Get state**: `python Skills/SharedScripts/research_state.py status <task_dir>`. Collect `wiki_pages_touched` list.
2. **Pre-check**: if `should_exit: true` → exit immediately.
3. **Read all touched pages** from `WIKI_TARGET` folder.
4. **Run review checklist** — for each page:
   - **Citation format**: any `(source: raw/...)` citation using a raw `.txt` filename → replace with the original URL from the `SOURCE_URL:` line of that raw file.
   - **Port/number conflicts**: if the same port, date, or numeric constant appears with different values across pages → add `⚠️ CONFLICT:` inline on both occurrences, note which source says what.
   - **Single-source superlatives**: any "first/largest/only/always/never" claim added during this run that has only one source and no `*(needs second source)*` marker → add the marker.
   - **Cross-page fact consistency**: same entity (library name, API call, constant) described differently on two pages → reconcile or flag.
   - **Stale library references**: if a deprecated library (e.g. `ib_insync`) is recommended without noting the current successor → add a note.
5. **Fix issues in-place** in the wiki files. Prefer minimal edits — correct the error, add the flag. Don't rewrite sections that have no issue.
6. **Write review summary** to `<task_dir>/review_notes.md`:
   ```
   REVIEW DATE: <ISO date>
   PAGES REVIEWED: <N>
   ISSUES FIXED: <list of fixes with file:line or section>
   FLAGS ADDED: <list of *(needs second source)* and CONFLICT markers added>
   OPEN QUESTIONS: <anything that needs human judgment>
   ```
7. `python Skills/SharedScripts/research_state.py update <task_dir> STATUS=COMPLETE PHASE=REVIEW`
8. Exit.

---

## Inline mode

Caller supplies `wiki_pages=[...]`. No `task.md`, no `progress.md`.

1. Read each page.
2. Run the same checklist as above.
3. Fix issues in place.
4. Print a summary to stdout in the same shape as `review_notes.md` would have (REVIEW DATE / PAGES REVIEWED / ISSUES FIXED / FLAGS ADDED / OPEN QUESTIONS). Do not write a `review_notes.md` file.
