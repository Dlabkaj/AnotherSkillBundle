# Top-level runner for LongTermTaskSkill.
# Loops: read state -> spawn claude -p with WORKER prompt for next partial -> repeat
# until COMPLETE / STOP_* / STOP.md / iter limit / usage limit.
#
# Usage:
#   powershell -File Skills/LongTermTaskSkill/Run-LongTermTask.ps1 -TaskDir <task_dir>
#
# Optional:
#   -MaxIterations 30      safety ceiling on dispatcher loops (default 30)
#   -DelaySeconds 5        pause between dispatches (default 5)
#   -ClaudeCmd claude      override CLI binary
#   -DryRun                print what would happen, don't spawn claude

param(
    [Parameter(Mandatory=$true)][string]$TaskDir,
    [int]$MaxIterations = 30,
    [int]$DelaySeconds = 5,
    [string]$ClaudeCmd = "claude",
    [switch]$DryRun
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
$stateScript  = Join-Path $PSScriptRoot "longterm_state.py"

if (-not (Test-Path $progressFile)) { Write-Host "ERROR: progress.md missing in $absTaskDir. Run 'python $stateScript init $absTaskDir' first."; exit 1 }
if (-not (Test-Path $stateScript)) { Write-Host "ERROR: state script missing: $stateScript"; exit 1 }

function Get-LongTermState {
    try {
        $json = & python $stateScript status $absTaskDir 2>$null | Out-String
        if (-not $json.Trim()) { return $null }
        return $json | ConvertFrom-Json
    } catch { return $null }
}

function Handle-UsageLimit {
    $autoRelaunch = (Get-TaskField $taskMd "AUTO_RELAUNCH" "false").ToLower() -eq "true"
    Invoke-UsageLimitHandler `
        -TaskDir              $absTaskDir `
        -ProgressFile         $progressFile `
        -LogFile              $logFile `
        -RelaunchScript       $PSCommandPath `
        -RelaunchEnabled      $autoRelaunch `
        -TaskNamePrefix       "LongTermTask-Relaunch" `
        -RelaunchDescription  "Auto-relaunch long-term task after token reset" `
        -FlagSummary          "auto_relaunch=$autoRelaunch" | Out-Null
}

# Build the WORKER prompt for a given partial
function Build-WorkerPrompt {
    param([string]$PartialSlug, [string]$PartialIdx)
    @"
Mode: WORKER.
Task dir: $absTaskDir
Partial: [$PartialIdx] $PartialSlug
Partial dir: $absTaskDir\partial\$PartialIdx-$PartialSlug

Follow Skills/LongTermTaskSkill.md WORKER protocol exactly. No user prompts. No commits.
"@
}

Write-Host "Run-LongTermTask starting."
Write-Host "  Task dir:    $absTaskDir"
Write-Host "  Max iters:   $MaxIterations"
Write-Host "  DryRun:      $DryRun"
Write-Host "  Stop:        New-Item '$stopFile' (or Ctrl+C)"
Write-Host ""

# --- main loop ---
$lastError = $null
for ($i = 1; $i -le $MaxIterations; $i++) {
    if (Test-StopFile $absTaskDir) {
        Write-Host "STOP.md detected. Exiting."
        & python $stateScript update $absTaskDir "STATUS=STOP_USER" | Out-Null
        break
    }

    $state = Get-LongTermState
    if (-not $state) {
        Write-Host "ERROR: failed to read state. Exiting."
        exit 1
    }

    if ($state.should_exit) {
        Write-Host "Runner stop condition: $($state.stop_reason)"
        $reason = $state.stop_reason
        # if not already terminal, set the right STOP status
        if (-not ($state.status -match "^(COMPLETE|STOP_)")) {
            $newStatus = if ($reason -match "iter_limit") { "STOP_ITER_LIMIT" }
                         elseif ($reason -match "STOP.md") { "STOP_USER" }
                         elseif ($reason -match "status=error") { "STOP_ERROR" }
                         elseif ($reason -match "all partials done") { "COMPLETE" }
                         else { "STOP_BLOCKED" }
            & python $stateScript update $absTaskDir "STATUS=$newStatus" | Out-Null
        }
        break
    }

    $next = $state.next_partial
    if (-not $next) {
        Write-Host "No next partial but not should_exit -- treating as complete."
        & python $stateScript update $absTaskDir "STATUS=COMPLETE" | Out-Null
        break
    }

    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host ""
    Write-Host "=== [$stamp] Dispatcher iter $i / $MaxIterations ==="
    Write-Host "  Partial : [$($next.idx)] $($next.slug) -- $($next.summary)"
    Write-Host "  Status  : $($next.status) (iter $($next.iter_count)/$($next.iter_limit), repeatable=$($next.repeatable))"

    "`n=== [${stamp}] LTT iter ${i}: partial=$($next.slug) iter_count=$($next.iter_count) ===" |
        Out-File -FilePath $logFile -Append -Encoding utf8

    & python $stateScript update $absTaskDir "ITER+=1" "CURRENT_PARTIAL=$($next.slug)" | Out-Null

    if ($DryRun) {
        Write-Host "  [DRY RUN] would invoke claude -p with WORKER prompt for partial $($next.slug)"
        # simulate progress: skip to next partial by marking this one done
        & python $stateScript mark-partial $absTaskDir $next.slug "done" | Out-Null
        continue
    }

    $prompt = Build-WorkerPrompt -PartialSlug $next.slug -PartialIdx $next.idx
    Write-Host "  --- worker session ---"
    $res = Invoke-WorkerSession -ClaudeCmd $ClaudeCmd -Prompt $prompt -LogFile $logFile
    if ($res.LimitHit) {
        Write-Host "  --- worker session end (LIMIT HIT) ---"
        Handle-UsageLimit
        exit 42
    }
    Write-Host "  --- worker session end ---"

    $postState = Get-LongTermState
    if ($postState) {
        $postPartials = $postState.partial_counts | ConvertTo-Json -Compress
        Write-Host "  After   : $postPartials"
        if ($postState.last_error) {
            Write-Host "  ERROR   : $($postState.last_error)"
            if (-not $lastError) {
                $lastError = $postState.last_error
            }
        }
    }

    if ($i -lt $MaxIterations) { Start-Sleep -Seconds $DelaySeconds }
}

# --- final summary ---
Write-Host ""
Write-Host "=== Run-LongTermTask summary ==="
$final = Get-LongTermState
if ($final) {
    Write-Host "  Status        : $($final.status)"
    Write-Host "  Iter          : $($final.iter) / $($final.iter_limit)"
    Write-Host "  Partials      : $($final.partial_counts | ConvertTo-Json -Compress)"
    if ($final.last_error) { Write-Host "  Last error    : $($final.last_error)" }
    if ($final.stop_reason) { Write-Host "  Stop reason   : $($final.stop_reason)" }
}
Write-Host "Run-LongTermTask exiting."
