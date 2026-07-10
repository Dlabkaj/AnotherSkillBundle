---
name: IngestionReviewSkill
disable-model-invocation: true
description: One-shot cross-wiki consistency check after autoresearch ingestion. Reads recently-touched wiki pages, fixes citation errors, flags conflicts and single-source superlatives, writes review_notes.md. Used by AutoresearchSkill as the final REVIEW phase. Can be invoked manually on any set of wiki pages.
---

# Ingestion Review Skill

Cross-wiki consistency pass run as the final phase of an autoresearch task. Single session, no iteration. Fixes clear errors in place, flags uncertain claims with markers.

State script: `Skills/SharedScripts/research_state.py` (read-only — `status` to get `WIKI_PAGES_TOUCHED`).

> `{{WIKI_ROOT}}` resolves from `skillSettings.json`. See repo `README.md`.

## Invocation modes (auto-detect)

- **Orchestrated (per-page)** — prompt contains `Mode: WORKER` AND `task.md` + `progress.md` with `PHASE=REVIEW` AND names **one page** to review → run the checklist on that page, fix in place, refresh `review_notes.md`, maintain that page's `## BLOCKED:` section in `review_blocked_report.md`, and emit a `REVIEW_PASS_RESULT:` line. The runner (`Run-IngestionReview.ps1`) drives this: it enumerates every page under `WIKI_TARGET`, calls the worker up to `-MaxPasses` (default 2) passes **per page** until that page is clean, and only after ALL pages are processed sets the final STATUS itself (`COMPLETE`, or `STOP_NEEDS_WORK` if any page blocked). **The worker must NOT set STATUS.** The runner owns page enumeration (from the `WIKI_TARGET` folder, NOT the unreliable `WIKI_PAGES_TOUCHED` counter) and skips marker-free pages without a session.
- **Inline** — caller provides `wiki_pages=[...]` directly → run checklist on those pages, print summary, no `review_notes.md`.

When in WORKER mode, follow the hard rules in [AutoresearchSkill.md § Hard rules](AutoresearchSkill.md#hard-rules--worker-mode).

---

## REVIEW loop (orchestrated per-page mode)

The runner names **one page** per session (`Review ONLY this page: <path>`). Do not enumerate or touch other pages except to Read them as corroboration for cross-checks.

1. **Read the named page.** Read sibling pages under the same folder and `raw/` files in the task dir only as needed to corroborate atoms.
2. **Run review checklist** on the named page:
   - **Local-ingest draft cleanup** (only if the page contains `<!-- local-ingest:` markers — drafts appended by [LocalModelIngestionSkill](LocalModelIngestionSkill.md)): the block after each marker is raw local-model output, generated per-chunk with no cross-chunk memory. Integrate it into the page format FIRST, before the verification pass: dedupe repeated headings/framing across chunks, merge overlapping bullets, replace citations that echo the literal word "SOURCE_URL" with the real URL from the marker, fix stray wrong-language fragments, tag crisp atoms `*(unverified)*` where the draft didn't, then delete the marker comment. Cleanup itself counts as **low**; a fabricated/unsupported claim found in a draft counts as **high** (drop it or flag `⚠️ CONFLICT:`).
   - **Deferred verification pass** (INGEST tags atoms `*(unverified)*` instead of cross-checking, to save turns): for every `*(unverified)*` atom → cross-check against ≥2 independent sources (other wiki pages + raw files in `<task_dir>/raw/`). If corroborated → remove the tag. If only one source supports it → replace with `*(needs second source)*`. If contradicted → add `⚠️ CONFLICT:`. This is REVIEW's main job now; read raw files as needed for corroboration.
   - **Citation format**: any `(source: raw/...)` citation using a raw `.txt` filename → replace with the original URL from the `SOURCE_URL:` line of that raw file.
   - **Port/number conflicts**: if the same port, date, or numeric constant appears with different values across pages → add `⚠️ CONFLICT:` inline on both occurrences, note which source says what.
   - **Single-source superlatives**: any "first/largest/only/always/never" claim added during this run that has only one source and no `*(needs second source)*` marker → add the marker.
   - **Cross-page fact consistency**: same entity (library name, API call, constant) described differently on two pages → reconcile or flag.
   - **Stale library references**: if a deprecated library (e.g. `ib_insync`) is recommended without noting the current successor → add a note.
   - **Legal citation currency** (`*(law-verify)*` tags): for each tagged legal provision (law name + article/section), WebSearch for the current official text. Apply:
     - Still valid and matches → remove the `*(law-verify)*` tag.
     - Amended or renumbered but substance intact → correct the reference inline, note the change in a parenthetical, remove the tag → counts as **low**.
     - Repealed or invalidated → mark `⚠️ REPEALED:` inline, add to OPEN QUESTIONS → counts as **high**.
     - Cannot confirm from available sources → replace with `*(needs law verification)*` → counts as **low**.
   Use official sources: government portals, EUR-Lex, official gazettes. Do not rely on secondary commentary alone.
3. **Fix issues in-place** in the wiki file. Prefer minimal edits — correct the error, add the flag. Don't rewrite sections that have no issue.
4. **Refresh review summary** at `<task_dir>/review_notes.md` (record this pass's findings):
   ```
   REVIEW DATE: <ISO date>
   PASS: <n>
   PAGES REVIEWED: <the one page>
   ISSUES FIXED: <list of fixes with file:line or section>
   FLAGS ADDED: <list of *(needs second source)* and CONFLICT markers added>
   OPEN QUESTIONS: <anything that needs human judgment / more sources>
   ```
5. **Maintain this page's block report.** After your fixes, judge whether the page still blocks:
   - **Blocks** if it has any **high**-severity unresolved issue (unresolved `⚠️ CONFLICT:`/contradiction/fabrication/broken citation) **OR** more than the runner's low threshold (passed in the prompt, default 2) of unresolved `*(needs second source)*` / `*(needs law verification)*` flags.
   - **If it blocks** → write or refresh a section titled **exactly** `## BLOCKED: <page rel path>` in `<task_dir>/review_blocked_report.md` with these fields, filled with specifics (never generic):
     ```
     ## BLOCKED: <page rel path>
     - Reason: <one line — why this page can't be signed off>
     - Specific cause: <the exact atom / number / claim>
     - Diverging info: <source A says X (url) vs source B says Y (url); or "single-source, no corroboration">
     - Open question: <what a human or more sources must resolve>
     ```
   - **If it does not block** (resolved, or only ≤ threshold minor single-source flags remain) → **remove** any `## BLOCKED: <this page>` section from that file.
6. **Do NOT set STATUS.** The runner decides `COMPLETE` vs `STOP_NEEDS_WORK` once all pages are processed.
7. **Emit exactly one final line** so the runner can measure this page's convergence:
   ```
   REVIEW_PASS_RESULT: high=<count> low=<count> fixed=<count> note=<short>
   ```
   Count only issues you found and acted on **this pass**. A pass reporting `high=0 low=0` = this page converged.
8. Exit.

### Severity & convergence (runner contract)

- **high** — unresolved/new `⚠️ CONFLICT:`, factual contradiction across pages, wrong or broken citation, fabricated/unsupported claim.
- **low** — `*(needs second source)*` added, missing cross-link, minor format/style, stale-library note.
- The runner reviews **every page under `WIKI_TARGET`, one at a time**, looping up to `-MaxPasses` passes **per page** (default 2), stopping a page early the first time a pass returns `high=0 low=0`. A page is **blocked** if its last pass still has **any high, or low > 2**. Only after **all** pages are processed does the runner set `STATUS`: `COMPLETE` if every page is clean/auto-passed, else `STOP_NEEDS_WORK` + a `NOTES:` line pointing at `review_blocked_report.md`. The dispatcher surfaces it — the named pages need more sources or manual attention. Marker-free pages (no `*(unverified)*` / `CONFLICT:` / `*(needs …)*`) are auto-passed with no worker session.

---

## Inline mode

Caller supplies `wiki_pages=[...]`. No `task.md`, no `progress.md`.

1. Read each page.
2. Run the same checklist as above.
3. Fix issues in place.
4. Print a summary to stdout in the same shape as `review_notes.md` would have (REVIEW DATE / PAGES REVIEWED / ISSUES FIXED / FLAGS ADDED / OPEN QUESTIONS). Do not write a `review_notes.md` file.
