# Sub-runner for IngestionReviewSkill (REVIEW phase).
# Orchestrated mode: enumerates EVERY page under WIKI_TARGET and reviews them one at
# a time, up to -MaxPasses passes per page, converging a page when a pass reports no
# issues. Only after ALL pages are processed does it set the task status: COMPLETE if
# every page converged, else STOP_NEEDS_WORK with a per-page block report so the
# dispatcher can flag exactly which pages (and why) need manual work.
#
# Why per-page (not global passes over WIKI_PAGES_TOUCHED): that counter is written
# by INGEST and has proven unreliable (under-recorded 15/16 pages once), so a global
# loop burned its whole pass budget on a single page and never touched the rest.
# Globbing WIKI_TARGET makes coverage independent of the bookkeeping.
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
    [int]$MaxPasses = 2,                 # passes PER PAGE (was global). Most pages converge in 1.
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

$absTaskDir    = (Resolve-Path $TaskDir).Path
$progressFile  = Join-Path $absTaskDir "progress.md"
$taskMd        = Join-Path $absTaskDir "task.md"
$logFile       = Join-Path $absTaskDir "iter-log.txt"
$blockedReport = Join-Path $absTaskDir "review_blocked_report.md"

if (-not (Test-Path $progressFile)) { Write-Host "ERROR: progress.md missing in $absTaskDir"; exit 1 }
if (Test-StopFile $absTaskDir) { Write-Host "STOP.md detected. Exiting."; exit 0 }

$status = Get-ProgressField $progressFile "STATUS"
$phase  = Get-ProgressField $progressFile "PHASE"
if ($status -match "^(COMPLETE|DONE|STOP_)") { Write-Host "STATUS=$status -- nothing to review."; exit 0 }
if ($phase -ne "REVIEW") { Write-Host "PHASE=$phase -- not REVIEW, exiting."; exit 0 }

$stateScript    = Join-Path $PSScriptRoot "..\SharedScripts\research_state.py"
$StateScriptRel = "Skills/AnotherSkillBundle/Skills/SharedScripts/research_state.py"

# Repo root = four levels up (…/Skills/AnotherSkillBundle/Skills/IngestionReviewSkill).
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path

# ── Build the page set from WIKI_TARGET (robust; see header note) ──────────────
$wikiTargetRel = Get-TaskField $taskMd "WIKI_TARGET"
$pages = @()
if ($wikiTargetRel) {
    $wikiTargetAbs = Join-Path $repoRoot ($wikiTargetRel -replace '/', '\')
    if (Test-Path $wikiTargetAbs) {
        $pages = @(Get-ChildItem $wikiTargetAbs -Recurse -Filter *.md -File | ForEach-Object { $_.FullName } | Sort-Object)
    }
}

if ($pages.Count -eq 0) {
    $note = "REVIEW found no pages under WIKI_TARGET=$wikiTargetRel -- INGEST may have written nothing, or WIKI_TARGET in task.md is wrong. Check task.md and the ingest output."
    Write-Host $note
    "# REVIEW blocked report -- $(Split-Path $absTaskDir -Leaf)`n`n$note`n" | Out-File -FilePath $blockedReport -Encoding utf8
    & python $stateScript update $absTaskDir "STATUS=STOP_NEEDS_WORK" "PHASE=REVIEW" "NOTES=$note See review_blocked_report.md." | Out-Null
    exit 0
}

# Marker regex: a page carrying any of these has open review work. A page with none
# is presumptively clean (INGEST tags every atom needing a check, so no markers =
# nothing to verify) and is auto-passed WITHOUT a worker session -- this bounds cost
# to the pages that actually need review. ASCII-only patterns to dodge PS 5.1
# emoji-encoding pitfalls: the worker always writes "CONFLICT:" / "REPEALED:" beside
# the ⚠️ flag, so those keywords are the reliable signal.
$markerRe = '\*\(unverified\)\*|\*\(needs |\*\(law-verify\)\*|CONFLICT:|REPEALED:'

# Fresh aggregated block report (worker appends one section per unresolved page).
$reportHeader = @"
# REVIEW blocked report -- $(Split-Path $absTaskDir -Leaf)

Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm'). One section per page REVIEW could not
converge. Each section: reason, specific cause, diverging info (source A vs B), open question.
"@
Set-Content -Path $blockedReport -Value $reportHeader -Encoding utf8

# Hardened-worker allowlist (REVIEW). Reads raw + wiki, fixes wiki in place, writes
# review_notes.md + review_blocked_report.md into the task dir (under MemoryVault/Raw),
# drives state. WebSearch allowed for *(law-verify)* currency checks. State script
# scoped + injected into the prompt.
$ReviewAllowedTools = @('Read','Glob','Grep','WebSearch','Write(MemoryVault/Raw/**)','Write(MemoryVault/Wiki/**)','Edit(MemoryVault/Wiki/**)','Edit(MemoryVault/Raw/**)',"Bash(python $StateScriptRel`:*)")

$stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "=== [$stamp] IngestionReview (per-page, $($pages.Count) pages, max $MaxPasses passes/page) ==="

$cleanPages   = @()   # converged or acceptable-residual
$skippedClean = @()   # no markers -> auto-passed
$blockedPages = @()   # unresolved after budget

foreach ($pageAbs in $pages) {
    if (Test-StopFile $absTaskDir) { Write-Host "STOP.md detected. Exiting."; exit 0 }
    $pageRel = $pageAbs.Replace($repoRoot + [IO.Path]::DirectorySeparatorChar, "").Replace("\", "/")

    # Pre-filter: skip pages with no open markers.
    if (-not (Select-String -Path $pageAbs -Pattern $markerRe -Quiet)) {
        Write-Host "  SKIP (clean, no markers): $pageRel"
        $skippedClean += $pageRel
        continue
    }

    $converged = $false
    $lastHigh  = 0
    $lastLow   = 0
    for ($pass = 1; $pass -le $MaxPasses; $pass++) {
        if (Test-StopFile $absTaskDir) { Write-Host "STOP.md detected. Exiting."; exit 0 }
        $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host ""
        Write-Host "=== [$stamp] REVIEW $pageRel -- pass $pass / $MaxPasses ==="
        "`n=== [$stamp] REVIEW $pageRel -- pass $pass / $MaxPasses ===" | Out-File -FilePath $logFile -Append -Encoding utf8

        $prompt = "Run wiki review on ONE page in $absTaskDir. Mode: WORKER. Follow IngestionReviewSkill protocol (orchestrated per-page). Review ONLY this page: $pageRel. This is pass $pass of max $MaxPasses for this page. Apply the full checklist INCLUDING deferred verification of every *(unverified)* atom; read sibling wiki pages under the same folder and raw/ files in the task dir as needed for cross-checks. Fix what you can in place. THEN decide this page's block state: if after your fixes the page still has any HIGH-severity unresolved issue (unresolved CONFLICT/contradiction/fabrication/broken citation) OR more than $NeedsWorkLowThreshold unresolved *(needs second source)*/*(needs law verification)* flags, write or refresh a section titled exactly '## BLOCKED: $pageRel' in $absTaskDir/review_blocked_report.md with these fields -- Reason: (one line); Specific cause: (which atom/number/claim); Diverging info: (source A says X vs source B says Y, with values and URLs, or 'single-source, no corroboration'); Open question: (what a human/more sources must resolve). If you resolved everything (or only <= $NeedsWorkLowThreshold minor single-source flags remain), REMOVE any '## BLOCKED: $pageRel' section from that file. Refresh review_notes.md with this pass's fixes. Do NOT set STATUS. Print EXACTLY one final line: REVIEW_PASS_RESULT: high=<count> low=<count> fixed=<count> note=<short>. Count only issues you found and acted on THIS pass. No user prompts. State script: python $StateScriptRel <cmd> ..."

        $passHigh = $null; $passLow = $null; $passNote = ""; $passBlocked = $false
        try {
            $res = Invoke-WorkerSession -ClaudeCmd $ClaudeCmd -Prompt $prompt -LogFile $logFile -Model $Model -AllowedTools $ReviewAllowedTools -LogTokens:$LogTokens
            if ($res.LimitHit) {
                # Usage limit mid-run: bubble to caller. On relaunch the runner restarts
                # from page 1; already-clean pages carry no markers and are skipped, so
                # the re-scan is cheap.
                Write-Host $UsageLimitSentinel
                $UsageLimitSentinel | Out-File -FilePath $logFile -Append -Encoding utf8
                exit 42
            }
            $mm = [regex]::Matches($res.Output, 'REVIEW_PASS_RESULT:\s*high=(\d+)\s+low=(\d+)(?:\s+fixed=(\d+))?(?:\s+note=(.*))?')
            if ($mm.Count -gt 0) {
                $last = $mm[$mm.Count - 1]
                $passHigh = [int]$last.Groups[1].Value
                $passLow  = [int]$last.Groups[2].Value
                if ($last.Groups[4].Success) { $passNote = $last.Groups[4].Value }
            }
            if ($res.Output -match '(?i)permission[- ]?wall|are all denied|denied in this session|cannot (apply|write|edit)') { $passBlocked = $true }
            if ($passNote -match '(?i)permission|denied|tool wall') { $passBlocked = $true }
        } catch {
            "REVIEW ERROR ($pageRel pass $pass): $_" | Out-File -FilePath $logFile -Append -Encoding utf8
            Write-Host "  Pass $pass errored: $_"
        }

        if ($passBlocked) {
            # Permission/tool wall: the worker applied nothing. Relaunching won't help
            # until the allowlist + cwd are fixed -- abort the whole REVIEW and flag it
            # as a TOOLING failure (distinct from a sources failure) so it isn't mistaken
            # for a converged/clean run.
            Write-Host "  Pass $pass : BLOCKED (permission/tool wall, note='$passNote'). Aborting REVIEW."
            $note = "REVIEW tooling failure on $pageRel -- worker hit a permission/tool wall (note='$passNote') and applied 0 edits, so the wiki was NOT actually reviewed. Check the worker allowlist and that the runner cwd is the repo root, then re-run REVIEW."
            $note | Out-File -FilePath $logFile -Append -Encoding utf8
            @"

## BLOCKED: $pageRel
- Reason: tooling failure (permission/tool wall) -- NOT a sources problem.
- Specific cause: worker reported denied tools (note='$passNote'); 0 edits applied.
- Diverging info: n/a
- Open question: fix the REVIEW worker allowlist + runner cwd (repo root), then re-run REVIEW.
"@ | Out-File -FilePath $blockedReport -Append -Encoding utf8
            & python $stateScript update $absTaskDir "STATUS=STOP_NEEDS_WORK" "PHASE=REVIEW" "NOTES=$note" | Out-Null
            Write-Host "Run-IngestionReview exiting (tooling block)."
            exit 0
        }

        if ($null -eq $passHigh) {
            Write-Host "  Pass $pass : REVIEW_PASS_RESULT not found -- treating as unconverged."
            $passHigh = 1; $passLow = 0
        } else {
            Write-Host "  Pass $pass : high=$passHigh low=$passLow"
        }
        $lastHigh = $passHigh
        $lastLow  = $passLow

        if ($passHigh -eq 0 -and $passLow -eq 0) { $converged = $true; break }
    }

    # Acceptable = clean, or only minor residual (high=0 and low<=threshold on the last
    # pass) -- matches the previous COMPLETE bar, just applied per page. Anything with a
    # residual high, or low over threshold, is a real block.
    $acceptable = $converged -or ($lastHigh -eq 0 -and $lastLow -le $NeedsWorkLowThreshold)
    if ($acceptable) {
        Write-Host "  -> OK: $pageRel"
        $cleanPages += $pageRel
    } else {
        Write-Host "  -> BLOCKED (residual high=$lastHigh low=$lastLow): $pageRel"
        $blockedPages += $pageRel
    }
}

# ── Decide task status once ALL pages are processed ───────────────────────────
$summary = "REVIEW processed $($pages.Count) pages: $($cleanPages.Count) reviewed-ok, $($skippedClean.Count) auto-passed (no markers), $($blockedPages.Count) blocked."
Write-Host ""
Write-Host $summary
$summary | Out-File -FilePath $logFile -Append -Encoding utf8

if ($blockedPages.Count -gt 0) {
    $note = "$summary Blocked pages: $($blockedPages -join ', '). Per-page reason/cause/diverging-info in review_blocked_report.md."
    & python $stateScript update $absTaskDir "STATUS=STOP_NEEDS_WORK" "PHASE=REVIEW" "NOTES=$note" | Out-Null
    Write-Host ""
    Write-Host "=== REVIEW: NEEDS MORE WORK ($($blockedPages.Count) page(s) blocked) ==="
    Write-Host $note
    Write-Host "Report: $blockedReport"
    Write-Host "==============================="
    $note | Out-File -FilePath $logFile -Append -Encoding utf8
} else {
    # No blocks -> the report holds only its header; drop it to avoid a stale empty file.
    if (Test-Path $blockedReport) { Remove-Item $blockedReport -Force }
    & python $stateScript update $absTaskDir "STATUS=COMPLETE" "PHASE=REVIEW" | Out-Null
    Write-Host "REVIEW complete (all pages reviewed-ok / auto-passed)."
}

Write-Host "Run-IngestionReview exiting."
