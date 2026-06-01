# Sub-runner for SourceScrapeSkill (FETCH phase).
# Pre-downloads pending URLs via Invoke-WebRequest, then loops claude -p sessions
# until PHASE != FETCH, STOP.md, or usage-limit hit.
#
# Usage (orchestrated):
#   .\Skills\SourceScrapeSkill\Run-SourceScrape.ps1 -TaskDir <task_dir>
# Usage (inline, no state files):
#   .\Skills\SourceScrapeSkill\Run-SourceScrape.ps1 -Urls @('https://...') -OutDir foo\

param(
    [string]$TaskDir,
    [string[]]$Urls,
    [string]$OutDir,
    [int]$MaxIterations = 30,
    [int]$DelaySeconds = 5,
    [string]$ClaudeCmd = "claude",
    [switch]$NoPreDownload
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8
$ErrorActionPreference    = "Continue"

. "$PSScriptRoot\..\SharedScripts\_runner-helpers.ps1"

# ── Helper: strip HTML tags to plain text ─────────────────────────────────────
function Get-PlainText {
    param([string]$Html)
    $t = $Html -replace '(?s)<script[^>]*>.*?</script>', ' '
    $t = $t    -replace '(?s)<style[^>]*>.*?</style>',  ' '
    $t = $t    -replace '<[^>]+>', ' '
    $t = $t    -replace '&amp;',  '&'  -replace '&lt;',   '<' -replace '&gt;',  '>'
    $t = $t    -replace '&quot;', '"'  -replace '&nbsp;', ' ' -replace '&#39;', "'"
    $t = $t    -replace '\s+',    ' '
    return $t.Trim()
}

# ── Helper: derive a slug from URL (YouTube video id or sanitized URL) ───────
function Get-UrlSlug {
    param([string]$Url)
    $isYouTube = ($Url -match 'youtube\.com/watch' -or $Url -match 'youtu\.be/')
    if ($isYouTube) {
        $videoId = if ($Url -match '[?&]v=([a-zA-Z0-9_-]{11})') { $Matches[1] }
                   elseif ($Url -match 'youtu\.be/([a-zA-Z0-9_-]{11})') { $Matches[1] }
                   else { $null }
        if ($videoId) { return "youtube-$videoId" }
    }
    $slug = ($Url -replace 'https?://', '' -replace '[^\w]', '-' -replace '-+', '-').Trim('-')
    if ($slug.Length -gt 80) { $slug = $slug.Substring(0, 80) }
    return $slug
}

# ── Helper: fetch a single URL to <RawDir>/<slug>.txt. Returns $true on success. ──
function Invoke-SingleFetch {
    param([string]$Url, [string]$RawDir)
    $isYouTube = ($Url -match 'youtube\.com/watch' -or $Url -match 'youtu\.be/')
    $slug      = Get-UrlSlug $Url
    $outPath   = Join-Path $RawDir "$slug.txt"

    if (Test-Path $outPath) {
        Write-Host "  [DL] already cached: $slug.txt"
        return @{ Saved = $true; Path = $outPath; Slug = $slug }
    }

    if ($isYouTube) {
        Write-Host "  [YT] $Url"
        $pyScript = Join-Path $PSScriptRoot "..\SharedScripts\fetch_youtube_transcript.py"
        $result   = python $pyScript $Url $outPath 2>&1
        Write-Host "       $result"
        if ($LASTEXITCODE -eq 0 -and (Test-Path $outPath)) {
            return @{ Saved = $true; Path = $outPath; Slug = $slug }
        }
        return @{ Saved = $false; Path = $outPath; Slug = $slug }
    }

    Write-Host "  [DL] $Url"
    try {
        $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 25 -ErrorAction Stop
        $text = "SOURCE_URL: $Url`n---`n" + (Get-PlainText $resp.Content)
        [System.IO.File]::WriteAllText($outPath, $text, [System.Text.Encoding]::UTF8)
        Write-Host "       saved -> $outPath"
        return @{ Saved = $true; Path = $outPath; Slug = $slug }
    } catch {
        Write-Host "       failed: $($_.Exception.Message)"
        return @{ Saved = $false; Path = $outPath; Slug = $slug }
    }
}

# ── Helper: pre-download pending URLs in candidates.md (orchestrated mode) ────
function Invoke-BulkDownload {
    param(
        [string]$CandidatesFile,
        [string]$RawDir,
        [string]$ProgressFile
    )

    if (-not (Test-Path $RawDir)) {
        New-Item -ItemType Directory -Force -Path $RawDir | Out-Null
    }

    $lines   = [System.IO.File]::ReadAllLines($CandidatesFile, [System.Text.Encoding]::UTF8)
    $out     = [System.Collections.Generic.List[string]]::new()
    $changed = $false
    $fetched = 0
    $failed  = 0
    $i       = 0

    while ($i -lt $lines.Count) {
        $line = $lines[$i]

        if ($line -match '^- \[' -and $line -match '(https?://[^\s]+)') {
            $url = $Matches[1]

            $block = [System.Collections.Generic.List[string]]::new()
            $block.Add($line)
            $k = $i + 1
            while ($k -lt $lines.Count -and $lines[$k] -match '^\s') {
                $block.Add($lines[$k])
                $k++
            }

            $hasPending = ($block | Where-Object { $_ -match '^\s+status:\s*pending' }).Count -gt 0
            $hasRaw     = ($block | Where-Object { $_ -match '^\s+raw:' }).Count -gt 0

            if ($hasPending -and -not $hasRaw) {
                $fetchResult = Invoke-SingleFetch -Url $url -RawDir $RawDir
                $saved       = $fetchResult.Saved
                $relRawPath  = "raw/$($fetchResult.Slug).txt"
                if ($saved) { $fetched++ } else { $failed++ }

                $newBlock = [System.Collections.Generic.List[string]]::new()
                foreach ($bl in $block) {
                    if ($bl -match '^\s+status:\s*pending') {
                        if ($saved) {
                            $newBlock.Add(($bl -replace 'pending', 'fetched'))
                            $newBlock.Add("  raw: $relRawPath")
                        } else {
                            $newBlock.Add(($bl -replace 'pending', 'skipped-fetch'))
                        }
                    } else {
                        $newBlock.Add($bl)
                    }
                }
                $out.AddRange($newBlock)
                $changed = $true
                $i = $k
                continue
            }

            $out.AddRange($block)
            $i = $k
            continue
        }

        $out.Add($line)
        $i++
    }

    if ($changed) {
        [System.IO.File]::WriteAllLines($CandidatesFile, $out, [System.Text.Encoding]::UTF8)
    }

    if ($fetched -gt 0 -or $failed -gt 0) {
        $prog = [System.IO.File]::ReadAllText($ProgressFile, [System.Text.Encoding]::UTF8)
        if ($fetched -gt 0) {
            $cur = 0; if ($prog -match 'SOURCES_FETCHED:\s*(\d+)') { $cur = [int]$Matches[1] }
            $prog = $prog -replace 'SOURCES_FETCHED:\s*\d+', "SOURCES_FETCHED: $($cur + $fetched)"
        }
        if ($failed -gt 0) {
            $cur = 0; if ($prog -match 'SOURCES_SKIPPED:\s*(\d+)') { $cur = [int]$Matches[1] }
            $prog = $prog -replace 'SOURCES_SKIPPED:\s*\d+', "SOURCES_SKIPPED: $($cur + $failed)"
        }
        [System.IO.File]::WriteAllText($ProgressFile, $prog, [System.Text.Encoding]::UTF8)
    }

    return @{ Fetched = $fetched; Failed = $failed }
}

function Get-PendingCount {
    param([string]$CandidatesFile)
    $count = 0
    if (Test-Path $CandidatesFile) {
        [System.IO.File]::ReadAllLines($CandidatesFile, [System.Text.Encoding]::UTF8) |
            Where-Object { $_ -match '^\s+status:\s*pending' } |
            ForEach-Object { $count++ }
    }
    return $count
}

# ── Inline mode: just fetch the provided URLs and exit ────────────────────────
if ($Urls -and $Urls.Count -gt 0) {
    if (-not $OutDir) { Write-Host "ERROR: -OutDir required for inline mode"; exit 1 }
    $rawDir = Join-Path $OutDir "raw"
    if (-not (Test-Path $rawDir)) { New-Item -ItemType Directory -Force -Path $rawDir | Out-Null }

    Write-Host "SourceScrape inline mode: $($Urls.Count) URLs -> $rawDir"
    $fetched = 0; $failed = 0
    foreach ($u in $Urls) {
        $r = Invoke-SingleFetch -Url $u -RawDir $rawDir
        if ($r.Saved) { $fetched++ } else { $failed++ }
    }
    Write-Host "Done. fetched: $fetched, failed: $failed"
    exit 0
}

# ── Orchestrated mode: drive FETCH loop until PHASE != FETCH ─────────────────
if (-not $TaskDir) { Write-Host "ERROR: -TaskDir or (-Urls + -OutDir) required"; exit 1 }
if (-not (Test-Path $TaskDir)) { Write-Host "ERROR: Task dir not found: $TaskDir"; exit 1 }

$absTaskDir     = (Resolve-Path $TaskDir).Path
$progressFile   = Join-Path $absTaskDir "progress.md"
$candidatesFile = Join-Path $absTaskDir "candidates.md"
$logFile        = Join-Path $absTaskDir "iter-log.txt"
$rawDir         = Join-Path $absTaskDir "raw"

if (-not (Test-Path $progressFile)) { Write-Host "ERROR: progress.md missing in $absTaskDir"; exit 1 }

Write-Host "Run-SourceScrape starting. TaskDir: $absTaskDir"

for ($i = 1; $i -le $MaxIterations; $i++) {
    if (Test-StopFile $absTaskDir) { Write-Host "STOP.md detected. Exiting."; break }

    $status = Get-ProgressField $progressFile "STATUS"
    $phase  = Get-ProgressField $progressFile "PHASE"

    if ($status -match "^(COMPLETE|DONE|STOP_)") { Write-Host "STATUS=$status -- exiting."; break }
    if ($phase -ne "FETCH") { Write-Host "PHASE=$phase -- handing back to dispatcher."; break }

    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "=== [$stamp] SourceScrape iter $i / $MaxIterations ==="

    if (-not $NoPreDownload -and (Test-Path $candidatesFile)) {
        Write-Host "  Pre-downloading pending URLs (no LLM tokens)..."
        $dl = Invoke-BulkDownload -CandidatesFile $candidatesFile -RawDir $rawDir -ProgressFile $progressFile
        Write-Host "  Pre-download: $($dl.Fetched) fetched, $($dl.Failed) failed"

        $remaining = Get-PendingCount $candidatesFile
        if ($remaining -eq 0) {
            Write-Host "  All candidates fetched. Transitioning FETCH -> INGEST."
            Set-ProgressPhase -ProgressFile $progressFile -Phase "INGEST" -Status "READY_INGEST"
            "=== [$stamp] SourceScrape iter $i [PS pre-download: FETCH->INGEST transition] ===" |
                Out-File -FilePath $logFile -Append -Encoding utf8
            break
        }
        Write-Host "  $remaining candidates still pending -- handing to Claude."
    }

    $prompt = "Continue source scrape in $absTaskDir. Mode: WORKER. Follow SourceScrapeSkill protocol (FETCH loop). No user prompts. Pre-downloaded candidates have status 'fetched' with raw: path -- skip WebFetch for those. Handle remaining pending. If no more pending, set PHASE=INGEST STATUS=READY_INGEST and exit."

    "`n=== [$stamp] SourceScrape iter $i ===" | Out-File -FilePath $logFile -Append -Encoding utf8

    try {
        $res = Invoke-WorkerSession -ClaudeCmd $ClaudeCmd -Prompt $prompt -LogFile $logFile
        if ($res.LimitHit) {
            Write-Host $UsageLimitSentinel
            $UsageLimitSentinel | Out-File -FilePath $logFile -Append -Encoding utf8
            exit 42  # signal to dispatcher
        }
    } catch {
        "ITER ERROR: $_" | Out-File -FilePath $logFile -Append -Encoding utf8
        Write-Host "Iter $i errored: $_"
    }

    if ($i -lt $MaxIterations) { Start-Sleep -Seconds $DelaySeconds }
}

Write-Host "Run-SourceScrape exiting."
