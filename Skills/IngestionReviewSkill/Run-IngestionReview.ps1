# Sub-runner for IngestionReviewSkill (REVIEW phase).
# Orchestrated mode: runs up to -MaxPasses review passes, converging when a pass
# reports no issues. If the final pass still has residual issues above threshold,
# sets STATUS=STOP_NEEDS_WORK so the dispatcher flags the topic for manual work.
#
# Usage (orchestrated):
#   .\Skills\IngestionReviewSkill\Run-IngestionReview.ps1 -TaskDir <task_dir>
# Usage (inline, no state files):
#   .\Skills\IngestionReviewSkill\Run-IngestionReview.ps1 -WikiPages @('Wiki/Foo/Index.md','Wiki/Foo/Bar.md')

param(
    [string]$TaskDir,
    [string[]]$WikiPages,
    [string]$ClaudeCmd = "claude",
    [string]$Model = "",
    [int]$MaxPasses = 3,
    [int]$NeedsWorkLowThreshold = 2,
    [switch]$LogTokens
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
    $res = Invoke-WorkerSession -ClaudeCmd $ClaudeCmd -Prompt $prompt -LogFile $null -Model $Model -LogTokens:$LogTokens
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

$stateScript = Join-Path $PSScriptRoot "..\SharedScripts\research_state.py"

$stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "=== [$stamp] IngestionReview (multi-pass, max $MaxPasses) ==="

$finalStatus = $null
$lastHigh = 0
$lastLow  = 0

for ($pass = 1; $pass -le $MaxPasses; $pass++) {
    if (Test-StopFile $absTaskDir) { Write-Host "STOP.md detected. Exiting."; exit 0 }

    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host ""
    Write-Host "=== [$stamp] REVIEW pass $pass / $MaxPasses ==="
    "`n=== [$stamp] REVIEW pass $pass / $MaxPasses ===" | Out-File -FilePath $logFile -Append -Encoding utf8

    $prompt = "Run wiki review PASS in $absTaskDir. Mode: WORKER. Follow IngestionReviewSkill protocol (orchestrated multi-pass). This is pass $pass of max $MaxPasses. Read WIKI_PAGES_TOUCHED from progress.md, apply the full checklist INCLUDING deferred verification of *(unverified)* atoms, fix issues in place. Do NOT set STATUS -- the runner decides. Refresh review_notes.md, then print EXACTLY one final line: REVIEW_PASS_RESULT: high=<count> low=<count> fixed=<count> note=<short>. Count only issues you found and acted on THIS pass (high = conflicts/contradictions/bad citations/fabrications; low = needs-second-source/missing cross-link/minor format). No user prompts."

    $passHigh = $null
    $passLow  = $null
    try {
        $res = Invoke-WorkerSession -ClaudeCmd $ClaudeCmd -Prompt $prompt -LogFile $logFile -Model $Model -LogTokens:$LogTokens
        if ($res.LimitHit) {
            Write-Host $UsageLimitSentinel
            $UsageLimitSentinel | Out-File -FilePath $logFile -Append -Encoding utf8
            exit 42
        }
        $mm = [regex]::Matches($res.Output, 'REVIEW_PASS_RESULT:\s*high=(\d+)\s+low=(\d+)')
        if ($mm.Count -gt 0) {
            $last = $mm[$mm.Count - 1]
            $passHigh = [int]$last.Groups[1].Value
            $passLow  = [int]$last.Groups[2].Value
        }
    } catch {
        "REVIEW ERROR (pass $pass): $_" | Out-File -FilePath $logFile -Append -Encoding utf8
        Write-Host "Review pass $pass errored: $_"
    }

    if ($null -eq $passHigh) {
        # Couldn't read the result line: treat as unconverged so we don't
        # falsely mark COMPLETE. Forces NEEDS_WORK if this was the final pass.
        Write-Host "  Pass $pass : REVIEW_PASS_RESULT not found -- treating as unconverged."
        $passHigh = 1
        $passLow  = 0
        $parsedOk = $false
    } else {
        Write-Host "  Pass $pass : high=$passHigh low=$passLow"
        $parsedOk = $true
    }
    $lastHigh = $passHigh
    $lastLow  = $passLow

    if ($parsedOk -and $passHigh -eq 0 -and $passLow -eq 0) {
        $finalStatus = "COMPLETE"
        Write-Host "  Converged clean on pass $pass."
        break
    }

    if ($pass -eq $MaxPasses) {
        if ($passHigh -ge 1 -or $passLow -gt $NeedsWorkLowThreshold) {
            $finalStatus = "STOP_NEEDS_WORK"
        } else {
            $finalStatus = "COMPLETE"
        }
    }
}

if (-not $finalStatus) { $finalStatus = "COMPLETE" }

if ($finalStatus -eq "STOP_NEEDS_WORK") {
    $note = "Review did not converge after $MaxPasses passes. Residual on final pass high=$lastHigh low=$lastLow (flag rule: any high, or low>$NeedsWorkLowThreshold). Topic needs more sources or manual attention -- see review_notes.md."
    & python $stateScript update $absTaskDir "STATUS=STOP_NEEDS_WORK" "PHASE=REVIEW" "NOTES=$note" | Out-Null
    Write-Host ""
    Write-Host "=== REVIEW: NEEDS MORE WORK ==="
    Write-Host $note
    Write-Host "==============================="
    $note | Out-File -FilePath $logFile -Append -Encoding utf8
} else {
    & python $stateScript update $absTaskDir "STATUS=COMPLETE" "PHASE=REVIEW" | Out-Null
    Write-Host "REVIEW complete (converged within $MaxPasses passes)."
}

Write-Host "Run-IngestionReview exiting."
