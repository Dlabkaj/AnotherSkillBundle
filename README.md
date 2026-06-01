# AnotherSkillBundle

Reusable skill belt for Claude Code projects. Pull this repo into any project that wants the same automation patterns — autonomous research, long-term task orchestration, anti-pattern advice — without re-deriving them.

## What's in here

| Path | Purpose |
| --- | --- |
| `Skills/` | Skill `.md` files + their owned scripts |
| `Skills/SharedScripts/` | Cross-skill helpers |
| `Skills/Index.md` | Skill map + script ownership + flow diagrams |
| `Wiki/ClaudeExperience/` | Anti-pattern + good-practice knowledge base referenced by `ClaudeAdviceSkill` |
| `skillSettings.example.json` | Template for project-level config (paths to memory, wiki, etc.) |

### Skills included

- **AutoresearchSkill** — orchestrates autonomous research runs (BOOTSTRAP only). Dispatcher chains FETCH → INGEST → REVIEW.
- **SourceScrapeSkill** — finds + fetches web sources (DISCOVER / FETCH sub-protocols).
- **IngestionSkill** — reads raw sources, extracts facts with verification, integrates into Wiki.
- **IngestionReviewSkill** — one-shot cross-wiki consistency pass after ingestion.
- **LongTermTaskSkill** — goals too big for one session. Decomposes into partial tasks + steps, each runs in its own `claude -p` session.
- **YouTubeTranscriptSkill** — fetch YouTube transcripts in autoresearch-compatible raw format.
- **ClaudeAdviceSkill** — always-active anti-pattern nudger (uses `Wiki/ClaudeExperience/`).

## Using these skills in a project

1. **Clone** AnotherSkillBundle into your project. Either:
   - Copy `Skills/` and `Wiki/ClaudeExperience/` into your project root, or
   - Add this repo as a git submodule and symlink / merge the folders.

2. **Copy `skillSettings.example.json` → `skillSettings.json`** at your project root. Edit the paths so they match where your project keeps its raw sources, wiki, and long-term task state.

3. **Tell Claude where to read settings.** In your project's `CLAUDE.md`, add a line like:
   ```
   ## Skill settings
   Read `skillSettings.json` at session start. When skill files reference
   `{{RAW_ROOT}}`, `{{WIKI_ROOT}}`, `{{LONGTERM_ROOT}}`, `{{CLAUDE_EXPERIENCE_ROOT}}`,
   substitute the corresponding value from `skillSettings.json`.
   ```

4. **Permissions.** Some skills write outside the standard write zone. Add to `.claude/settings.json` → `permissions.allow`:
   ```
   "Write(path:MemoryVault/Raw/**)"
   "Edit(path:MemoryVault/Raw/**)"
   "Write(path:MemoryVault/Wiki/**)"
   "Edit(path:MemoryVault/Wiki/**)"
   "Write(path:MemoryVault/LongTermTask/**)"
   "Edit(path:MemoryVault/LongTermTask/**)"
   ```
   (Adjust paths to match your `skillSettings.json`.)

## Placeholder tokens

Skill `.md` files use these tokens instead of hardcoded paths. Define each one in `skillSettings.json`:

| Token | skillSettings key |
| --- | --- |
| `{{RAW_ROOT}}` | `rawRoot` |
| `{{WIKI_ROOT}}` | `wikiRoot` |
| `{{LONGTERM_ROOT}}` | `longTermRoot` |
| `{{CLAUDE_EXPERIENCE_ROOT}}` | `claudeExperienceRoot` |
| `{{SKILLS_ROOT}}` | `skillsRoot` |

The PowerShell + Python scripts are path-agnostic — they take the relevant directory as a parameter (`-TaskDir`, `<task_dir>` argv). The tokens exist for the skill prose so Claude knows where to look when the user invokes a skill conversationally.

## Requirements

- PowerShell 7+ (`pwsh`) — runners are `.ps1`, cross-platform on Windows / macOS / Linux. Windows PowerShell 5.1 also works on Windows.
- Python 3.9+ (state CLIs, transcript fetcher)
- `pip install youtube-transcript-api` (only if YouTubeTranscriptSkill / `[youtube]` candidates are used)
- Claude Code CLI on `PATH` as `claude` (runners spawn `claude -p` WORKER sessions)

### Windows-only feature

Auto-relaunch on usage-limit (`ON_LIMIT: relaunch` in `task.md`) uses **Windows Task Scheduler** via `Register-ScheduledTask` — Windows-only. On macOS / Linux, set `ON_LIMIT: stop` and trigger relaunch via `cron` / `launchd` / `systemd` yourself, or just relaunch manually. Everything else (FETCH / INGEST / REVIEW loops, LTT dispatcher, state CLIs) is platform-agnostic.

## Conventions

- **Skill .md** at `Skills/<Name>Skill.md` (PascalCase + `Skill` suffix).
- **Owned scripts** at `Skills/<Name>Skill/` — folder matches skill filename.
- **Shared scripts** at `Skills/SharedScripts/`.
- **`Run-*.ps1`** = orchestrators / dispatchers. **`*_state.py`** = state CLI. **`_runner-helpers.ps1`** = shared PS helpers (underscore prefix = not a runnable script).

See [Skills/Index.md](Skills/Index.md) for the full map.
