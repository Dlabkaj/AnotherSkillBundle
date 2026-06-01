# Skills Index

Map of skills + scripts and how they wire together. Keep this file in sync when adding new skills or moving scripts.

> Path placeholders (`{{RAW_ROOT}}`, `{{WIKI_ROOT}}`, `{{LONGTERM_ROOT}}`, `{{CLAUDE_EXPERIENCE_ROOT}}`) resolve from `skillSettings.json` at the project root. See [../README.md](../README.md).

---

## Skills

| Skill file | Purpose | Modes |
| --- | --- | --- |
| [AutoresearchSkill.md](AutoresearchSkill.md) | Orchestrator for autonomous research runs. BOOTSTRAP only — interview + write brief + delegate. Background loop chains FETCH → INGEST → REVIEW. | BOOTSTRAP |
| [SourceScrapeSkill.md](SourceScrapeSkill.md) | Find + fetch web sources. Builds `candidates.md`, downloads to `raw/*.txt`. | DISCOVER, FETCH, inline |
| [IngestionSkill.md](IngestionSkill.md) | Read raw sources, extract facts with verification, write into Wiki. One source per loop. | WORKER (INGEST), inline |
| [IngestionReviewSkill.md](IngestionReviewSkill.md) | One-shot cross-wiki consistency pass after ingestion. Fix citation errors, flag conflicts/single-source superlatives. | WORKER (REVIEW), inline |
| [LongTermTaskSkill.md](LongTermTaskSkill.md) | Goals too big for one session. Decompose → partial tasks → step-driven WORKER subprocesses. Reference docs (file formats, state-script API, runner internals) in sibling [details.md](LongTermTaskSkill/details.md). | CREATE, WORKER, MANUAL |
| [YouTubeTranscriptSkill.md](YouTubeTranscriptSkill.md) | Fetch YouTube transcripts in autoresearch-compatible raw format. | standalone |
| [ClaudeAdviceSkill.md](ClaudeAdviceSkill.md) | Always-active. Scans turn for anti-patterns (from `{{CLAUDE_EXPERIENCE_ROOT}}/AntiPatterns/`), surfaces one-line nudge with wiki link. | always-active |

---

## Scripts

### Owned (live in their skill's folder)

| Script | Owner skill | Called by |
| --- | --- | --- |
| [AutoresearchSkill/Run-Autoresearch.ps1](AutoresearchSkill/Run-Autoresearch.ps1) | AutoresearchSkill | user / Task Scheduler relaunch |
| [SourceScrapeSkill/Run-SourceScrape.ps1](SourceScrapeSkill/Run-SourceScrape.ps1) | SourceScrapeSkill | Run-Autoresearch.ps1 (FETCH phase) |
| [IngestionSkill/Run-Ingestion.ps1](IngestionSkill/Run-Ingestion.ps1) | IngestionSkill | Run-Autoresearch.ps1 (INGEST phase), user (inline mode) |
| [IngestionReviewSkill/Run-IngestionReview.ps1](IngestionReviewSkill/Run-IngestionReview.ps1) | IngestionReviewSkill | Run-Autoresearch.ps1 (REVIEW phase), user (inline mode) |
| [LongTermTaskSkill/Run-LongTermTask.ps1](LongTermTaskSkill/Run-LongTermTask.ps1) | LongTermTaskSkill | user / Task Scheduler relaunch |
| [LongTermTaskSkill/longterm_state.py](LongTermTaskSkill/longterm_state.py) | LongTermTaskSkill | Run-LongTermTask.ps1, WORKER prompts |

### Shared (live in `Skills/SharedScripts/`, used by ≥2 skills)

| Script | Used by | Role |
| --- | --- | --- |
| [SharedScripts/_runner-helpers.ps1](SharedScripts/_runner-helpers.ps1) | all 5 Run-*.ps1 | UsageLimit detection, `Register-RelaunchTask`, `Invoke-UsageLimitHandler`, `Invoke-WorkerSession`. Dot-sourced. |
| [SharedScripts/WORKER-rules.md](SharedScripts/WORKER-rules.md) | AutoresearchSkill + LongTermTaskSkill | Universal hard rules for any WORKER session (no AskUserQuestion, no commits, context budget, STOP.md). Skill .md files link here instead of duplicating. |
| [SharedScripts/research_state.py](SharedScripts/research_state.py) | SourceScrape, Ingestion, IngestionReview (via prompts), Run-Ingestion.ps1 | State CLI for autoresearch task dirs (`status / mark / update / check-stop`). |
| [SharedScripts/fetch_youtube_transcript.py](SharedScripts/fetch_youtube_transcript.py) | Run-SourceScrape.ps1, YouTubeTranscriptSkill (standalone) | Pull YouTube transcript → autoresearch raw format. |

---

## Autoresearch flow

`Run-Autoresearch.ps1` reads `PHASE` from `progress.md` and chains the matching sub-runner. Each sub-runner runs WORKER sessions (`claude -p`) until it exits or flips PHASE.

```
                          AutoresearchSkill (BOOTSTRAP)
                                    │
                                    ▼  writes task.md + progress.md
                          [user launches dispatcher]
                                    │
                                    ▼
            ┌──────── Run-Autoresearch.ps1 ────────┐
            │  reads PHASE, calls sub-runner       │
            └──────────────────────────────────────┘
                │            │                │
       PHASE=FETCH   PHASE=INGEST       PHASE=REVIEW
                │            │                │
                ▼            ▼                ▼
    Run-SourceScrape   Run-Ingestion   Run-IngestionReview
        (loop)            (loop)          (one-shot)
                │            │                │
                └──── all ───┴────── call ────┘
                            │
                            ▼
                    SharedScripts/research_state.py    ← state CLI
                    SharedScripts/_runner-helpers.ps1  ← dot-sourced helpers
                    SharedScripts/fetch_youtube_       ← only Run-SourceScrape
                                  transcript.py
```

Phase progression: `FETCH ⇄ INGEST → REVIEW → COMPLETE`. INGEST can bounce back to FETCH if it discovers new candidates.

All task state lives under `{{RAW_ROOT}}/<topic-slug>/` (`task.md`, `progress.md`, `candidates.md`, `raw/`, optional `STOP.md`).

---

## LongTermTask flow

Independent system. Same architecture pattern but for arbitrary multi-session goals — not research-specific.

```
        LongTermTaskSkill (CREATE)
              │
              ▼  writes task.md + partial-tasks.md + partial/<NN-slug>/*
        [user launches runner]
              │
              ▼
    Run-LongTermTask.ps1 (dispatcher)
              │
              │  loop: read state → spawn claude -p (WORKER) → repeat
              ▼
       claude -p WORKER session
              │
              └─→ LongTermTaskSkill/longterm_state.py     (state CLI: status /
                                                            mark-step / mark-partial /
                                                            reset-steps / ...)
              └─→ SharedScripts/_runner-helpers.ps1       (dot-sourced by runner)
```

Task state lives under `{{LONGTERM_ROOT}}/<task-slug>/`.

---

## Conventions

- **Skill .md** at `Skills/<Name>Skill.md` (PascalCase + `Skill` suffix).
- **Owned scripts** at `Skills/<Name>Skill/` — folder matches skill filename.
- **Shared scripts** at `Skills/SharedScripts/`.
- **`Run-*.ps1`** = orchestrators / dispatchers. **`*_state.py`** = state CLI. **`_runner-helpers.ps1`** = shared PS helpers (underscore prefix = not a runnable script).
- New runner inside a skill subfolder must reference shared scripts via `$PSScriptRoot\..\SharedScripts\<script>`.
