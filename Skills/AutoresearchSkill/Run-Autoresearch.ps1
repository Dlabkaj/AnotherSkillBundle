# Top-level dispatcher for AutoresearchSkill.
# Reads PHASE from progress.md, chains the matching sub-runner until STATUS hits
# COMPLETE / STOP_* / STOP.md, or a sub-runner signals USAGE_LIMIT_HIT.
#
# Usage:
#   powershell -File Skills/AutoresearchSkill/Run-Autoresearch.ps1 -TaskDir <task_dir>
#   (or just .\Skills\AutoresearchSkill\Run-Autoresearch.ps1 from a PowerShell prompt)
#
# Optional:
#   -MaxPhaseTransitions 30   safety ceiling on phase flips (default 30)
#   -ClaudeCmd claude         override CLI binary

param(
    [Parameter(Mandatory=$true)][string]$TaskDir,
    [int]$MaxPhaseTransitions = 30,
    [string]$ClaudeCmd = "claude"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8
$ErrorActionPreference    = "Continue"

. "$PSScriptRoot\..\SharedScripts\_runner-helpers.ps1"

if (-not (Test-Path $TaskDir)) { Write-Host "ERROR: Task dir not found: $TaskDir"; exit 1 }
$absTaskDir   = (Resolve-Path $TaskDir).Path
$progressFile = Join-Path $absTaskDir "progress.md"
$stopFile     = Join-Path $absTaskDir "STOP.md"
$logFile      = Join-Path $absTaskDir "iter-log.txt"
$taskMd       = Join-Path $absTaskDir "task.md"

if (-not (Test-Path $progressFile)) { Write-Host "ERROR: progress.md missing in $absTaskDir"; exit 1 }

$scrapeRunner = Join-Path $PSScriptRoot "..\SourceScrapeSkill\Run-SourceScrape.ps1"
$ingestRunner = Join-Path $PSScriptRoot "..\IngestionSkill\Run-Ingestion.ps1"
$reviewRunner = Join-Path $PSScriptRoot "..\IngestionReviewSkill\Run-IngestionReview.ps1"

Write-Host "Autoresearch dispatcher starting."
Write-Host "  Task dir:    $absTaskDir"
Write-Host "  Max flips:   $MaxPhaseTransitions"
Write-Host "  Stop:        New-Item '$stopFile' (or Ctrl+C)"
Write-Host ""

function Handle-UsageLimit {
    param([string]$AbsTaskDir, [string]$TaskMd, [string]$ProgressFile, [string]$LogFile)

    $onLimit = (Get-TaskField $TaskMd "ON_LIMIT" "stop").ToLower()
    Invoke-UsageLimitHandler `
        -TaskDir              $AbsTaskDir `
        -ProgressFile         $ProgressFile `
        -LogFile              $LogFile `
        -RelaunchScript       $PSCommandPath `
        -RelaunchEnabled      ($onLimit -eq 'relaunch') `
        -TaskNamePrefix       "Autoresearch-Relaunch" `
        -RelaunchDescription  "Auto-relaunch autoresearch task after token reset" `
        -FlagSummary          "on_limit=$onLimit" | Out-Null
}

# ── Main dispatcher loop ──────────────────────────────────────────────────────
for ($flip = 1; $flip -le $MaxPhaseTransitions; $flip++) {
    if (Test-Path $stopFile) { Write-Host "STOP.md detected. Exiting."; break }

    $progress = [System.IO.File]::ReadAllText($progressFile, [System.Text.Encoding]::UTF8)
    if ($progress -match "STATUS:\s*(COMPLETE|DONE|STOP_)") {
        Write-Host "Done. progress.md status: $($Matches[0])"
        $notesIdx = $progress.IndexOf("NOTES:")
        if ($notesIdx -ge 0) {
            Write-Host ""
            Write-Host "=== EXIT REASON (from progress.md) ==="
            Write-Host $progress.Substring($notesIdx).Trim()
            Write-Host "======================================="
        }
        break
    }

    $phase = "UNKNOWN"
    if ($progress -match "PHASE:\s*(\w+)") { $phase = $Matches[1] }

    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "=== [$stamp] Dispatcher flip $flip / $MaxPhaseTransitions  [PHASE: $phase] ==="

    switch ($phase) {
        "FETCH"  { $runner = $scrapeRunner }
        "INGEST" { $runner = $ingestRunner }
        "REVIEW" { $runner = $reviewRunner }
        default  { Write-Host "Unknown PHASE: $phase -- exiting."; break }
    }

    if (-not (Test-Path $runner)) { Write-Host "ERROR: sub-runner missing: $runner"; break }

    & $runner -TaskDir $absTaskDir -ClaudeCmd $ClaudeCmd
    $subExit = $LASTEXITCODE

    if ($subExit -eq 42) {
        Handle-UsageLimit -AbsTaskDir $absTaskDir -TaskMd $taskMd -ProgressFile $progressFile -LogFile $logFile
        break
    }
}

Write-Host ""
Write-Host "Dispatcher ended. Check $absTaskDir for progress.md, candidates.md, and iter-log.txt."
