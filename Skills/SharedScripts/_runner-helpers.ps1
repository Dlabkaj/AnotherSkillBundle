# Shared helpers for Run-Autoresearch / Run-SourceScrape / Run-Ingestion / Run-IngestionReview / Run-LongTermTask.
# Dot-source: . "$PSScriptRoot\_runner-helpers.ps1"

# Sentinel used by sub-runners to signal usage-limit hit to the outer dispatcher
$script:UsageLimitSentinel = "USAGE_LIMIT_HIT"

function Test-UsageLimitHit {
    param([string]$Output)
    return ($Output -match "hit your limit|usage limit|rate limit|token limit|Claude AI usage|limit reached|exceeded.*limit|limit.*exceeded")
}

function Test-StopFile {
    param([string]$TaskDir)
    if (-not $TaskDir) { return $false }
    return (Test-Path (Join-Path $TaskDir "STOP.md"))
}

function Get-TaskField {
    param([string]$TaskMdPath, [string]$FieldName, [string]$Default = "")
    if (-not (Test-Path $TaskMdPath)) { return $Default }
    $content = [System.IO.File]::ReadAllText($TaskMdPath, [System.Text.Encoding]::UTF8)
    foreach ($line in ($content -split "`n")) {
        if ($line -match "^\s*${FieldName}:\s*(.+?)\s*$") { return $Matches[1].Trim() }
    }
    return $Default
}

function Set-ProgressPhase {
    param([string]$ProgressFile, [string]$Phase, [string]$Status)
    $prog = [System.IO.File]::ReadAllText($ProgressFile, [System.Text.Encoding]::UTF8)
    $prog = $prog -replace 'PHASE:\s*\w+',  "PHASE: $Phase"
    $prog = $prog -replace 'STATUS:\s*\S+', "STATUS: $Status"
    [System.IO.File]::WriteAllText($ProgressFile, $prog, [System.Text.Encoding]::UTF8)
}

function Get-ProgressField {
    param([string]$ProgressFile, [string]$FieldName, [string]$Default = "")
    if (-not (Test-Path $ProgressFile)) { return $Default }
    $content = [System.IO.File]::ReadAllText($ProgressFile, [System.Text.Encoding]::UTF8)
    if ($content -match "${FieldName}:\s*(\S+)") { return $Matches[1] }
    return $Default
}

function Get-ResetTime {
    param([string]$Output)
    # Use the LAST match in the input, not the first. The log tail can contain
    # stale "resets <time>" lines from earlier usage-limit hits; matching the
    # first one would schedule against an already-past reset and bump +1 day.
    $rxAmPm = [regex]'resets?\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)'
    $m = $rxAmPm.Matches($Output)
    if ($m.Count -gt 0) {
        $last = $m[$m.Count - 1]
        $hour = [int]$last.Groups[1].Value
        $min  = if ($last.Groups[2].Success) { [int]$last.Groups[2].Value } else { 0 }
        $ampm = $last.Groups[3].Value.ToLower()
        if ($ampm -eq 'pm' -and $hour -lt 12) { $hour += 12 }
        if ($ampm -eq 'am' -and $hour -eq 12) { $hour = 0 }
        $now   = Get-Date
        $reset = [datetime]::new($now.Year, $now.Month, $now.Day, $hour, $min, 0)
        if ($reset -le $now) { $reset = $reset.AddDays(1) }
        return $reset
    }
    $rxIso = [regex]'resets?\s+at\s+(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2})'
    $m = $rxIso.Matches($Output)
    if ($m.Count -gt 0) {
        $last = $m[$m.Count - 1]
        try { return [datetime]::Parse($last.Groups[1].Value) } catch { return $null }
    }
    return $null
}

function Register-RelaunchTask {
    param(
        [string]$TaskDir,
        [datetime]$RunAt,
        [string]$ScriptPath,
        [string]$TaskNamePrefix = "Autoresearch-Relaunch",
        [string]$Description    = "Auto-relaunch task after token reset"
    )
    $slug     = Split-Path $TaskDir -Leaf
    $taskName = "$TaskNamePrefix-$slug"

    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }

    $startAt = $RunAt.AddMinutes(1)

    $action   = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -TaskDir `"$TaskDir`""
    $trigger  = New-ScheduledTaskTrigger -Once -At $startAt
    $settings = New-ScheduledTaskSettingsSet -WakeToRun -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

    Register-ScheduledTask `
        -TaskName    $taskName `
        -Action      $action `
        -Trigger     $trigger `
        -Settings    $settings `
        -Description "$Description '$slug'" | Out-Null

    return @{ TaskName = $taskName; StartAt = $startAt }
}

# Shared usage-limit handler. Caller computes whether relaunch is enabled (from its own flag — ON_LIMIT, AUTO_RELAUNCH, etc.) and passes the bool.
# Writes AUTO_RELAUNCH_COUNT bookkeeping, registers a scheduled-task relaunch if possible, logs to LogFile.
function Invoke-UsageLimitHandler {
    param(
        [string]$TaskDir,
        [string]$ProgressFile,
        [string]$LogFile,
        [string]$RelaunchScript,
        [bool]  $RelaunchEnabled,
        [string]$TaskNamePrefix    = "Autoresearch-Relaunch",
        [string]$RelaunchDescription = "Auto-relaunch task after token reset",
        [string]$FlagSummary       = "",
        [int]   $MaxRelaunches     = 3
    )

    Write-Host ""
    Write-Host "=== USAGE LIMIT HIT ==="

    $relaunchCount = 0
    $curProg       = [System.IO.File]::ReadAllText($ProgressFile, [System.Text.Encoding]::UTF8)
    if ($curProg -match 'AUTO_RELAUNCH_COUNT:\s*(\d+)') { $relaunchCount = [int]$Matches[1] }

    $resetTime = $null
    if (Test-Path $LogFile) {
        $tail = Get-Content $LogFile -Tail 200 -ErrorAction SilentlyContinue
        if ($tail) { $resetTime = Get-ResetTime (($tail) -join "`n") }
    }

    $scheduled = $false
    if ($RelaunchEnabled -and $relaunchCount -lt $MaxRelaunches) {
        if ($resetTime) {
            try {
                $result = Register-RelaunchTask `
                    -TaskDir         $TaskDir `
                    -RunAt           $resetTime `
                    -ScriptPath      $RelaunchScript `
                    -TaskNamePrefix  $TaskNamePrefix `
                    -Description     $RelaunchDescription
                if ($curProg -match 'AUTO_RELAUNCH_COUNT:') {
                    $curProg = $curProg -replace 'AUTO_RELAUNCH_COUNT:\s*\d+', "AUTO_RELAUNCH_COUNT: $($relaunchCount + 1)"
                } else {
                    $curProg = $curProg.TrimEnd() + "`nAUTO_RELAUNCH_COUNT: $($relaunchCount + 1)`n"
                }
                [System.IO.File]::WriteAllText($ProgressFile, $curProg, [System.Text.Encoding]::UTF8)
                Write-Host "Auto-relaunch scheduled at $($result.StartAt.ToString('yyyy-MM-dd HH:mm:ss'))"
                Write-Host "Task Scheduler entry: $($result.TaskName)"
                Write-Host "Attempt: $($relaunchCount + 1) / $MaxRelaunches"
                "AUTO-RELAUNCH scheduled at $($result.StartAt) (attempt $($relaunchCount + 1)/$MaxRelaunches)" |
                    Out-File -FilePath $LogFile -Append -Encoding utf8
                $scheduled = $true
            } catch {
                Write-Host "Failed to register scheduled task: $_"
            }
        } else {
            Write-Host "Could not parse reset time. Manual relaunch needed."
        }
    } elseif ($RelaunchEnabled) {
        Write-Host "Auto-relaunch cap reached ($relaunchCount/$MaxRelaunches). Stopping."
    }

    if (-not $scheduled) {
        Write-Host "Wait for reset then relaunch manually:"
        Write-Host "  powershell -File $RelaunchScript -TaskDir $TaskDir"
    }
    Write-Host "======================="
    "USAGE LIMIT HIT -- $FlagSummary, relaunch_count=$relaunchCount, scheduled=$scheduled" |
        Out-File -FilePath $LogFile -Append -Encoding utf8

    return $scheduled
}

# Invoke claude -p with WORKER prompt; returns hashtable @{ Output; LimitHit }
# -Model:     optional CLI model alias/id (haiku|sonnet|opus|<full-id>). Empty = CLI default.
# -LogTokens: when set, run with --output-format json and emit a TOKENS: line
#             (in / cache / out / cost) to host + LogFile. Off by default.
function Invoke-WorkerSession {
    param(
        [string]$ClaudeCmd,
        [string]$Prompt,
        [string]$LogFile,
        [string]$Model = "",
        [switch]$LogTokens
    )
    $cmdArgs = @('-p')
    if ($Model)     { $cmdArgs += @('--model', $Model) }
    if ($LogTokens) { $cmdArgs += @('--output-format', 'json') }
    $cmdArgs += '--dangerously-skip-permissions'
    $cmdArgs += $Prompt

    # Pipe closed stdin so the CLI does not wait 3s for optional piped input.
    # That "no stdin data received" warning is emitted on stderr and, merged
    # via 2>&1, would otherwise prepend non-JSON text to the result blob.
    $output  = $null | & $ClaudeCmd @cmdArgs 2>&1
    $rawText = ($output -join "`n")
    $text    = $rawText

    # With --output-format json claude returns a single JSON blob. Pull the result
    # text back out for display/limit-detection and log a usage line. Limit
    # detection always runs against the raw output so a non-JSON limit message
    # (CLI emits plain text on usage-limit) is still caught.
    if ($LogTokens) {
        $tokenLine = "TOKENS: (parse failed -- output not JSON)"
        # Isolate the result JSON object: any stderr noise merged via 2>&1
        # lands before it, so parse from the first result marker onward.
        $jsonText = $rawText
        $idx = $rawText.IndexOf('{"type":"result"')
        if ($idx -ge 0) { $jsonText = $rawText.Substring($idx) }
        try {
            $j = $jsonText | ConvertFrom-Json
            if ($null -ne $j.result) { $text = [string]$j.result }
            $u = $j.usage
            $tokenLine = "TOKENS: in=$([int]$u.input_tokens) cache_read=$([int]$u.cache_read_input_tokens) cache_create=$([int]$u.cache_creation_input_tokens) out=$([int]$u.output_tokens) cost_usd=$($j.total_cost_usd) turns=$($j.num_turns)"
        } catch { }
        Write-Host $tokenLine
        if ($LogFile) { $tokenLine | Out-File -FilePath $LogFile -Append -Encoding utf8 }
    }

    $text -split "`n" | ForEach-Object { Write-Host $_ }
    if ($LogFile) {
        $text | Out-File -FilePath $LogFile -Append -Encoding utf8
    }
    return @{
        Output   = $text
        LimitHit = (Test-UsageLimitHit $rawText)
    }
}
