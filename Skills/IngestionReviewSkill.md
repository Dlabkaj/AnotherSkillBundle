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

- **Orchestrated (multi-pass)** — prompt contains `Mode: WORKER` AND `task.md` + `progress.md` with `PHASE=REVIEW` → read `WIKI_PAGES_TOUCHED`, run checklist, fix in place, refresh `review_notes.md`, and emit a `REVIEW_PASS_RESULT:` line. The runner (`Run-IngestionReview.ps1`) loops this up to 3 passes until a pass is clean, then sets the final STATUS itself (`COMPLETE`, or `STOP_NEEDS_WORK` if unconverged). **The worker must NOT set STATUS.**
- **Inline** — caller provides `wiki_pages=[...]` directly → run checklist on those pages, print summary, no `review_notes.md`.

When in WORKER mode, follow the hard rules in [AutoresearchSkill.md § Hard rules](AutoresearchSkill.md#hard-rules--worker-mode).

---

## REVIEW loop (orchestrated mode)

1. **Get state**: `python Skills/SharedScripts/research_state.py status <task_dir>`. Collect `wiki_pages_touched` list.
2. **Pre-check**: if `should_exit: true` → exit immediately.
3. **Read all touched pages** from `WIKI_TARGET` folder.
4. **Run review checklist** — for each page:
   - **Deferred verification pass** (INGEST tags atoms `*(unverified)*` instead of cross-checking, to save turns): for every `*(unverified)*` atom → cross-check against ≥2 independent sources (other wiki pages + raw files in `<task_dir>/raw/`). If corroborated → remove the tag. If only one source supports it → replace with `*(needs second source)*`. If contradicted → add `⚠️ CONFLICT:`. This is REVIEW's main job now; read raw files as needed for corroboration.
   - **Citation format**: any `(source: raw/...)` citation using a raw `.txt` filename → replace with the original URL from the `SOURCE_URL:` line of that raw file.
   - **Port/number conflicts**: if the same port, date, or numeric constant appears with different values across pages → add `⚠️ CONFLICT:` inline on both occurrences, note which source says what.
   - **Single-source superlatives**: any "first/largest/only/always/never" claim added during this run that has only one source and no `*(needs second source)*` marker → add the marker.
   - **Cross-page fact consistency**: same entity (library name, API call, constant) described differently on two pages → reconcile or flag.
   - **Stale library references**: if a deprecated library (e.g. `ib_insync`) is recommended without noting the current successor → add a note.
5. **Fix issues in-place** in the wiki files. Prefer minimal edits — correct the error, add the flag. Don't rewrite sections that have no issue.
6. **Refresh review summary** at `<task_dir>/review_notes.md` (record this pass's findings):
   ```
   REVIEW DATE: <ISO date>
   PASS: <n>
   PAGES REVIEWED: <N>
   ISSUES FIXED: <list of fixes with file:line or section>
   FLAGS ADDED: <list of *(needs second source)* and CONFLICT markers added>
   OPEN QUESTIONS: <anything that needs human judgment / more sources>
   ```
7. **Do NOT set STATUS.** The runner decides `COMPLETE` vs `STOP_NEEDS_WORK` across passes.
8. **Emit exactly one final line** so the runner can measure convergence:
   ```
   REVIEW_PASS_RESULT: high=<count> low=<count> fixed=<count> note=<short>
   ```
   Count only issues you found and acted on **this pass**. A pass reporting `high=0 low=0` = converged.
9. Exit.

### Severity & convergence (runner contract)

- **high** — unresolved/new `⚠️ CONFLICT:`, factual contradiction across pages, wrong or broken citation, fabricated/unsupported claim.
- **low** — `*(needs second source)*` added, missing cross-link, minor format/style, stale-library note.
- The runner loops up to **3 passes**, stopping early the first time a pass returns `high=0 low=0` → `STATUS=COMPLETE`. If the 3rd pass still has **any high, or low > 2**, the runner sets `STATUS=STOP_NEEDS_WORK` + a `NOTES:` line; the dispatcher surfaces it — the topic needs more sources or manual attention.

---

## Inline mode

Caller supplies `wiki_pages=[...]`. No `task.md`, no `progress.md`.

1. Read each page.
2. Run the same checklist as above.
3. Fix issues in place.
4. Print a summary to stdout in the same shape as `review_notes.md` would have (REVIEW DATE / PAGES REVIEWED / ISSUES FIXED / FLAGS ADDED / OPEN QUESTIONS). Do not write a `review_notes.md` file.
