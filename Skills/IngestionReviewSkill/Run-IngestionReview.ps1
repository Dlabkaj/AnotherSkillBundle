# Sub-runner for IngestionReviewSkill (REVIEW phase). One-shot — single claude -p session.
#
# Usage (orchestrated):
#   .\Skills\IngestionReviewSkill\Run-IngestionReview.ps1 -TaskDir <task_dir>
# Usage (inline, no state files):
#   .\Skills\IngestionReviewSkill\Run-IngestionReview.ps1 -WikiPages @('Wiki/Foo/Index.md','Wiki/Foo/Bar.md')

param(
    [string]$TaskDir,
    [string[]]$WikiPages,
    [string]$ClaudeCmd = "claude"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8
$ErrorActionPreference    = "Continue"

. "$PSScriptRoot\..\SharedScripts\_runner-helpers.ps1"

# ── Inline mode ───────────────────────────────────────────────────────────────
if ($WikiPages -and $WikiPages.Count -gt 0) {
    $pagesJoined = ($WikiPages | ForEach-Object { "`"$_`"" }) -join ", "
    $prompt = "Mode: WORKER. Follow IngestionReviewSkill protocol (inline mode). Review these wiki pages: $pagesJoined. Run full checklist (citation format, port/number conflicts, single-source superlatives, cross-page consistency, stale libraries). Fix issues in place. Print summary to stdout in review_notes.md shape -- do NOT write a review_notes.md file. No user prompts."

    Write-Host "Run-IngestionReview inline mode: $($WikiPages.Count) pages"
    $res = Invoke-WorkerSession -ClaudeCmd $ClaudeCmd -Prompt $prompt -LogFile $null
    if ($res.LimitHit) { Write-Host $UsageLimitSentinel; exit 42 }
    exit 0
}

# ── Orchestrated mode ────────────────────────────────────────────────────────
if (-not $TaskDir) { Write-Host "ERROR: -TaskDir or -WikiPages required"; exit 1 }
if (-not (Test-Path $TaskDir)) { Write-Host "ERROR: Task dir not found: $TaskDir"; exit 1 }

$absTaskDir   = (Resolve-Path $TaskDir).Path
$progressFile = Join-Path $absTaskDir "progress.md"
$logFile      = Join-Path $absTaskDir "iter-log.txt"

if (-not (Test-Path $progressFile)) { Write-Host "ERROR: progress.md missing in $absTaskDir"; exit 1 }

if (Test-StopFile $absTaskDir) { Write-Host "STOP.md detected. Exiting."; exit 0 }

$status = Get-ProgressField $progressFile "STATUS"
$phase  = Get-ProgressField $progressFile "PHASE"

if ($status -match "^(COMPLETE|DONE|STOP_)") { Write-Host "STATUS=$status -- nothing to review."; exit 0 }
if ($phase -ne "REVIEW") { Write-Host "PHASE=$phase -- not REVIEW, exiting."; exit 0 }

$stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "=== [$stamp] IngestionReview (one-shot) ==="

$prompt = "Run wiki review in $absTaskDir. Mode: WORKER. Follow IngestionReviewSkill protocol (REVIEW loop). No user prompts. Read WIKI_PAGES_TOUCHED from progress.md, apply checklist, fix issues, write review_notes.md, set STATUS=COMPLETE via research_state.py update."

"`n=== [$stamp] IngestionReview (one-shot) ===" | Out-File -FilePath $logFile -Append -Encoding utf8

try {
    $res = Invoke-WorkerSession -ClaudeCmd $ClaudeCmd -Prompt $prompt -LogFile $logFile
    if ($res.LimitHit) {
        Write-Host $UsageLimitSentinel
        $UsageLimitSentinel | Out-File -FilePath $logFile -Append -Encoding utf8
        exit 42
    }
} catch {
    "REVIEW ERROR: $_" | Out-File -FilePath $logFile -Append -Encoding utf8
    Write-Host "Review errored: $_"
}

Write-Host "Run-IngestionReview exiting."
