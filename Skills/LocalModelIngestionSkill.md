---
name: LocalModelIngestionSkill
description: Offload per-source fact extraction to a local Ollama model instead of Claude. Called from the autoresearch INGEST loop when a task sets INGEST_BACKEND=local:<model>, or by Jerry when asked to ingest with a local model. Chunks the raw file, calls Ollama /api/generate, appends the draft to the target wiki page, returns a status report.
disable-model-invocation: false
---

# Local Model Ingestion Skill

Delegate the token-heavy read+extract of one raw source to a local model via the Ollama API, so Claude spends no context on it. Claude stays the orchestrator (candidate selection, `progress.md`, `research_state.py`, `STOP.md`); this skill only produces a wiki draft and reports back.

Runner: `{{SKILLS_ROOT}}/LocalModelIngestionSkill/Run-LocalIngestion.ps1` (`{{SKILLS_ROOT}}` from `skillSettings.json`; run from repo root). Config: `localAIModels.json` at repo root.

> Quality is lower than Claude ingestion — verification tagging, wiki-links, and translation are rougher. Output is a **draft**; the REVIEW phase ([IngestionReviewSkill](IngestionReviewSkill.md)) cleans it up. Use for volume where cost beats per-source polish.

## When to use

- Task `task.md` has `INGEST_BACKEND: local:<model>` → [IngestionSkill](IngestionSkill.md) INGEST step 5 delegates here instead of extracting inline.
- Jerry is asked to ingest a raw file with a local model ad-hoc.

## How Jerry calls it

Per source, Claude:
1. **Composes the extraction prompt** — research focus, target language, tag crisp atoms `*(unverified)*`, desired output shape (wiki bullets/prose). This is the `-Prompt` (or `-PromptFile` for long prompts). **Inject the literal URL** for citations (e.g. `cite as (zdroj: https://...)`) — a small local model echoes the placeholder word "SOURCE_URL" if you just say "cite the SOURCE_URL". The marker carries the real URL regardless, so REVIEW can fix stragglers.
2. **Runs the script:**
   ```
   powershell -NoProfile -File {{SKILLS_ROOT}}/LocalModelIngestionSkill/Run-LocalIngestion.ps1 `
     -RawFile <next_candidate.raw> -WikiTarget <target sub-page> `
     -Prompt "<composed prompt>" [-Model <name>]
   ```
3. **Reads the `=== LocalIngestion status ===` block** (MODEL / CHUNKS / CHARS_APPENDED / ERRORS / RESULT).
4. **Resumes bookkeeping itself** — `mark <url> done` (or `skipped-ingest` if RESULT=FAILED / 0 chars), `update SOURCES_INGESTED+=1 RECENT_EDIT_CHARS+=<CHARS_APPENDED> ...`. The script never touches state files.

The script writes the draft under a marker `<!-- local-ingest: <url> @ <ts> -->` in the wiki page so REVIEW can find it.

## Config (`localAIModels.json`, repo root)

```json
{ "endpoint": "http://localhost:11434", "defaultModel": "qwen3-30b-a3b",
  "models": [ { "name": "qwen3-30b-a3b", "stream": false,
               "options": { "num_ctx": 16384, "temperature": 0.2 } } ] }
```

- **`options.num_ctx`** — context window (single source of truth; also drives chunk sizing). 16k is the **tested sweet spot**: it splits an ~8K-token source into 2 grounded ~4K-token passes. **Do NOT raise it to force fewer/bigger chunks** — see Prompt discipline below (bigger single passes hallucinate on this model).
- **`options.temperature`** — keep low (`0.2`) so extraction stays faithful, not creative.
- **`stream`** — reserved; the script always uses non-streaming (`stream:false`) and warns if config says true.

## Prompt discipline (anti-hallucination)

A small local model **invents plausible content when asked for structure it can't fill** — verified: a transcript's outro chunk backfilled an entire generic Node/K8s/Kafka stack that contradicted the real (Convex) stack from an earlier chunk. Chunks are generated **independently, with no cross-chunk memory**, so:

- Tell it to **extract ONLY facts explicitly stated in the given text; omit any section with no material; never add general knowledge or invent specifics.** If a chunk is thin, its output should be thin.
- **Do NOT ask each chunk for a full global document structure** (headings like "Tech Stack", "Architecture") — every chunk then reinvents (and duplicates) all sections. Ask for grounded bullets; let the REVIEW phase (Claude) impose structure, dedupe, and reconcile across chunks.
- **Multi-chunk output will have duplicate headings / repeated framing.** That's expected raw material for REVIEW, not a finished page.
- **Keep passes small — the failure mode is input SIZE per pass, not chunk boundaries.** Tested on qwen3-30b-a3b: ~4K-token passes stay grounded; feeding a whole ~8K-token source in ONE pass (num_ctx 32k) produced pure generic hallucination — a fabricated Node/Docker/K8s stack, zero real terms, a different fake stack each re-run. This MoE (3B active) disengages from long input and pattern-completes off the prompt's focus line. **For big sources, prefer MORE small chunks over fewer big ones** — accept the boundary seams; REVIEW dedupes them.

## Gotchas

- **num_ctx is the only lever.** There is no `OLLAMA_CONTEXT_LENGTH` env dance — env set in a script never reaches the running Ollama tray server. Per-request `options.num_ctx` is what takes effect.
- **Server must be up + model pulled.** Script gives actionable errors: "start the tray app / `ollama serve`" and "`ollama pull <model>`".
- **First request at a new num_ctx reloads the model** (slow, seconds). Normal.

## Success criteria

- Dry-run (`-WhatIf`) prints the chunk plan, writes nothing, exits 0.
- Live run on a raw `.txt` appends extraction under the marker in `-WikiTarget`, prints a status block, exits 0 (non-zero only if nothing was produced).
- No `exceed_context_size_error` — each request stays under `num_ctx`.
- Claude reads the status and completes state bookkeeping unchanged.

## Research needed

- Chunk heuristic (4 chars/token, 50% input reserve) — partly validated: on qwen3-30b-a3b, ~4K-token passes ground well, ~8K single-pass hallucinates. Sweet spot ~4K tok/pass; re-test if switching models.
- Wiki-write ownership: currently the script appends. If structure/page-selection suffers, switch to script-returns-text / Claude-writes.
- A single line longer than the chunk budget becomes one oversized chunk (rare for prose); hard-split not yet implemented.
