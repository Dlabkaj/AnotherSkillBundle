# Sub-runner for IngestionSkill (INGEST phase).
# Loops claude -p sessions until PHASE != INGEST, STOP.md, or usage-limit hit.
#
# Usage (orchestrated):
#   .\Skills\IngestionSkill\Run-Ingestion.ps1 -TaskDir <task_dir>
# Usage (inline, no state files):
#   .\Skills\IngestionSkill\Run-Ingestion.ps1 -RawFiles @('foo.txt','bar.txt') -WikiTarget Wiki/Bar/ `
#                              -Language English -ResearchFocus "chemical formulas"

param(
    [string]$TaskDir,
    [string[]]$RawFiles,
    [string]$WikiTarget,
    [string]$Language = "English",
    [string]$ResearchFocus,
    [int]$MaxIterations = 30,
    [int]$DelaySeconds = 5,
    [string]$ClaudeCmd = "claude",
    [string]$Model = "",
    [switch]$LogTokens
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8
$ErrorActionPreference    = "Continue"

. "$PSScriptRoot\..\SharedScripts\_runner-helpers.ps1"

function Get-IngestState {
    param([string]$TaskDir)
    try {
        $json = & python "$PSScriptRoot\..\SharedScripts\research_state.py" status $TaskDir 2>$null | Out-String
        if (-not $json.Trim()) { return $null }
        return $json | ConvertFrom-Json
    } catch {
        return $null
    }
}

# ── Inline mode: one Claude session covering all provided files ──────────────
if ($RawFiles -and $RawFiles.Count -gt 0) {
    if (-not $WikiTarget)    { Write-Host "ERROR: -WikiTarget required for inline mode"; exit 1 }
    if (-not $ResearchFocus) { Write-Host "ERROR: -ResearchFocus required for inline mode"; exit 1 }

    $filesJoined = ($RawFiles | ForEach-Object { "`"$_`"" }) -join ", "
    $prompt = "Mode: WORKER. Follow IngestionSkill protocol (inline mode). Ingest these raw files in order: $filesJoined. Wiki target: $WikiTarget. Language: $Language. Research focus: $ResearchFocus. No progress.md, no state script. Apply verification pass and conflict rules. Print one-line chars-added summary per file. No user prompts."

    Write-Host "Run-Ingestion inline mode: $($RawFiles.Count) files -> $WikiTarget"
    $res = Invoke-WorkerSession -ClaudeCmd $ClaudeCmd -Prompt $prompt -LogFile $null -Model $Model -LogTokens:$LogTokens
    if ($res.LimitHit) { Write-Host $UsageLimitSentinel; exit 42 }
    exit 0
}

# ── Orchestrated mode: drive INGEST loop until PHASE != INGEST ───────────────
if (-not $TaskDir) { Write-Host "ERROR: -TaskDir or (-RawFiles + -WikiTarget + -ResearchFocus) required"; exit 1 }
if (-not (Test-Path $TaskDir)) { Write-Host "ERROR: Task dir not found: $TaskDir"; exit 1 }

$absTaskDir   = (Resolve-Path $TaskDir).Path
$progressFile = Join-Path $absTaskDir "progress.md"
$logFile      = Join-Path $absTaskDir "iter-log.txt"

if (-not (Test-Path $progressFile)) { Write-Host "ERROR: progress.md missing in $absTaskDir"; exit 1 }

Write-Host "Run-Ingestion starting. TaskDir: $absTaskDir"

for ($i = 1; $i -le $MaxIterations; $i++) {
    if (Test-StopFile $absTaskDir) { Write-Host "STOP.md detected. Exiting."; break }

    $status = Get-ProgressField $progressFile "STATUS"
    $phase  = Get-ProgressField $progressFile "PHASE"

    if ($status -match "^(COMPLETE|DONE|STOP_)") { Write-Host "STATUS=$status -- exiting."; break }
    if ($phase -ne "INGEST") { Write-Host "PHASE=$phase -- handing back to dispatcher."; break }

    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host ""
    Write-Host "=== [$stamp] Ingestion iter $i / $MaxIterations ==="

    $preState = Get-IngestState $absTaskDir
    if ($preState -and $preState.next_candidate) {
        $c = $preState.next_candidate
        Write-Host "  Source : $($c.title)"
        Write-Host "  URL    : $($c.url)"
        if ($c.raw) { Write-Host "  Raw    : $($c.raw)" }
        Write-Host "  Before : ingested=$($preState.counters.sources_ingested), skipped=$($preState.counters.sources_skipped), fetched=$($preState.counters.sources_fetched)"
    } elseif ($preState) {
        Write-Host "  No next_candidate (counts: $($preState.candidate_counts | ConvertTo-Json -Compress))"
    }

    $prompt = "Continue ingestion in $absTaskDir. Mode: WORKER. Follow IngestionSkill protocol (INGEST loop). No user prompts. Read ONLY the next_candidate raw file (from research_state.py status) plus the single target sub-page; do NOT read other raw files or wiki pages. Extract facts from this source only, tag crisp atoms *(unverified)* (NO cross-source checking -- REVIEW does that), apply local conflict rule, mark done. Stop when context budget hit or PHASE changes."

    "`n=== [$stamp] Ingestion iter $i ===" | Out-File -FilePath $logFile -Append -Encoding utf8
    Write-Host "  --- worker session ---"

    $iterErr = $null
    try {
        $res = Invoke-WorkerSession -ClaudeCmd $ClaudeCmd -Prompt $prompt -LogFile $logFile -Model $Model -LogTokens:$LogTokens
        if ($res.LimitHit) {
            Write-Host "  --- worker session end (LIMIT HIT) ---"
            Write-Host $UsageLimitSentinel
            $UsageLimitSentinel | Out-File -FilePath $logFile -Append -Encoding utf8
            exit 42
        }
    } catch {
        $iterErr = $_
        "ITER ERROR: $_" | Out-File -FilePath $logFile -Append -Encoding utf8
    }
    Write-Host "  --- worker session end ---"

    $postState = Get-IngestState $absTaskDir
    if ($iterErr) {
        Write-Host "  RESULT : ERROR -- $iterErr"
    } elseif ($postState -and $preState) {
        $ingestedDelta = $postState.counters.sources_ingested - $preState.counters.sources_ingested
        $skippedDelta  = $postState.counters.sources_skipped  - $preState.counters.sources_skipped
        $newPages = @()
        if ($postState.wiki_pages_touched) {
            $oldSet = @($preState.wiki_pages_touched)
            $newPages = @($postState.wiki_pages_touched | Where-Object { $oldSet -notcontains $_ })
        }
        $lastChars = 0
        if ($postState.recent_edit_chars -and $postState.recent_edit_chars.Count -gt 0) {
            $lastChars = $postState.recent_edit_chars[-1]
        }

        if ($ingestedDelta -gt 0) {
            Write-Host "  RESULT : ingested +$ingestedDelta  (chars added: $lastChars)"
            if ($newPages.Count -gt 0) { Write-Host "  Pages  : $($newPages -join ', ')" }
        } elseif ($skippedDelta -gt 0) {
            Write-Host "  RESULT : skipped +$skippedDelta"
        } else {
            Write-Host "  RESULT : NO STATE CHANGE -- worker may have errored or hit context budget. Check $logFile."
        }
        Write-Host "  After  : ingested=$($postState.counters.sources_ingested), skipped=$($postState.counters.sources_skipped), phase=$($postState.phase), status=$($postState.status)"
    } else {
        Write-Host "  RESULT : (state script failed -- cannot compute delta)"
    }

    if ($i -lt $MaxIterations) { Start-Sleep -Seconds $DelaySeconds }
}

# Final summary
Write-Host ""
Write-Host "=== Run-Ingestion summary ==="
$finalState = Get-IngestState $absTaskDir
if ($finalState) {
    Write-Host "  Sources ingested : $($finalState.counters.sources_ingested)"
    Write-Host "  Sources skipped  : $($finalState.counters.sources_skipped)"
    Write-Host "  Wiki pages       : $($finalState.wiki_pages_touched.Count)"
    if ($finalState.wiki_pages_touched.Count -gt 0) {
        $finalState.wiki_pages_touched | ForEach-Object { Write-Host "    - $_" }
    }
    Write-Host "  Final STATUS     : $($finalState.status)"
    Write-Host "  Final PHASE      : $($finalState.phase)"
    if ($finalState.stop_reason) { Write-Host "  Stop reason      : $($finalState.stop_reason)" }
}
Write-Host "Run-Ingestion exiting."
