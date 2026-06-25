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
    [string]$Model = "",
    [string]$Agent = "intern",
    [string]$DigestModel = "",
    [int]$MaxRawChars = 100000,   # max chars per raw chunk file (~25-30k tokens). A
                                  # source larger than this is split into <slug>.partNN
                                  # files, each its own candidate row, so the whole
                                  # source is ingested without overflowing a worker.
    [switch]$LogTokens,
    [switch]$NoPreDownload
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8
$ErrorActionPreference    = "Continue"

. "$PSScriptRoot\..\SharedScripts\_runner-helpers.ps1"

# ── Helper: hard-wrap one over-long line at word boundaries ───────────────────
# Read truncates any single line over ~2000 chars, so no wrapped line may exceed
# $Width. Breaks at the last space before $Width; hard-cuts a giant token (e.g. a
# base64 blob) only when no usable space exists.
function Format-WrappedLine {
    param([string]$Line, [int]$Width = 1500)
    if ($Line.Length -le $Width) { return $Line }
    $out = [System.Collections.Generic.List[string]]::new()
    while ($Line.Length -gt $Width) {
        $cut = $Line.LastIndexOf(' ', $Width - 1)
        if ($cut -lt [int]($Width * 0.5)) { $cut = $Width }   # no good break -> hard cut
        $out.Add($Line.Substring(0, $cut).TrimEnd())
        $Line = $Line.Substring($cut).TrimStart()
    }
    if ($Line) { $out.Add($Line) }
    return ($out -join "`n")
}

# ── Helper: strip HTML to plain text, PRESERVING line structure ───────────────
# Full whitespace-collapse (old behaviour) flattened the page to one line, which
# Read then truncated to ~2000 chars -- i.e. most of every source was silently
# lost. Instead: turn block-level tags into newlines, strip the rest, collapse
# only intra-line runs, then wrap any remaining over-long line.
function Get-PlainText {
    param([string]$Html)
    $t = $Html -replace '(?s)<script[^>]*>.*?</script>', ' '
    $t = $t    -replace '(?s)<style[^>]*>.*?</style>',  ' '
    # Block-level boundaries -> newline, so paragraphs/headings/list items survive.
    $t = $t    -replace '(?i)<br\s*/?>', "`n"
    $t = $t    -replace '(?i)</(p|div|h[1-6]|li|tr|section|article|header|footer|blockquote)>', "`n"
    $t = $t    -replace '<[^>]+>', ' '
    $t = $t    -replace '&amp;',  '&'  -replace '&lt;',   '<' -replace '&gt;',  '>'
    $t = $t    -replace '&quot;', '"'  -replace '&nbsp;', ' ' -replace '&#39;', "'"
    $t = $t    -replace '[ \t]+', ' '             # collapse intra-line runs only
    $lines = $t -split '\r?\n' | ForEach-Object { $_.Trim() }
    $lines = $lines | ForEach-Object { Format-WrappedLine $_ }   # wrap, may emit \n
    $text  = ($lines -join "`n")
    $text  = $text -replace '(\r?\n){3,}', "`n`n"  # collapse blank-line runs
    return $text.Trim()
}

# ── Helper: wrap every line of a plain-text body (for non-HTML, e.g. YT) ──────
function Format-WrappedText {
    param([string]$Text, [int]$Width = 1500)
    return (($Text -split '\r?\n' | ForEach-Object { Format-WrappedLine $_ $Width }) -join "`n")
}

# ── Helper: split a body into <=MaxChars chunks at line boundaries ────────────
# No chunk exceeds MaxChars, so each part loads whole into a worker's context
# (no truncation, no silent session loss). A single line longer than MaxChars is
# hard-split as a last resort -- doesn't happen after Format-Wrapped* (<=1500/line).
function Split-IntoChunks {
    param([string]$Text, [int]$MaxChars)
    if ($MaxChars -le 0 -or $Text.Length -le $MaxChars) { return ,@($Text) }
    $chunks = [System.Collections.Generic.List[string]]::new()
    $sb = [System.Text.StringBuilder]::new()
    foreach ($ln in ($Text -split "`n")) {
        $piece = $ln + "`n"
        while ($piece.Length -gt $MaxChars) {
            if ($sb.Length -gt 0) { $chunks.Add($sb.ToString().TrimEnd("`n")); [void]$sb.Clear() }
            $chunks.Add($piece.Substring(0, $MaxChars))
            $piece = $piece.Substring($MaxChars)
        }
        if ($sb.Length -gt 0 -and ($sb.Length + $piece.Length) -gt $MaxChars) {
            $chunks.Add($sb.ToString().TrimEnd("`n")); [void]$sb.Clear()
        }
        [void]$sb.Append($piece)
    }
    if ($sb.Length -gt 0) { $chunks.Add($sb.ToString().TrimEnd("`n")) }
    return ,$chunks.ToArray()
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

# ── Helper: fetch one URL to raw chunk file(s). Returns the part file names. ──
# Returns @{ Saved; Slug; Url; Parts=@(basename...) }. One source <=MaxRawChars
# yields a single <slug>.txt; a larger one yields <slug>.part01.txt..partNN.txt.
# Each file carries the clean SOURCE_URL header (citations stay clean); the caller
# registers parts 2..N as their own candidate rows.
function Invoke-SingleFetch {
    param([string]$Url, [string]$RawDir)
    $isYouTube = ($Url -match 'youtube\.com/watch' -or $Url -match 'youtu\.be/')
    $slug      = Get-UrlSlug $Url

    # Cache: any existing <slug>*.txt (single or chunked) -> reuse, don't re-fetch.
    $existing = @(Get-ChildItem -Path $RawDir -Filter "$slug*.txt" -File -ErrorAction SilentlyContinue |
                  Sort-Object Name)
    if ($existing.Count -gt 0) {
        Write-Host "  [DL] already cached: $($existing.Count) file(s) for $slug"
        return @{ Saved = $true; Slug = $slug; Url = $Url; Parts = @($existing.Name) }
    }

    # 1) Get plain, wrapped content (no header).
    $content = $null
    if ($isYouTube) {
        Write-Host "  [YT] $Url"
        $pyScript = Join-Path $PSScriptRoot "..\SharedScripts\fetch_youtube_transcript.py"
        $tmp      = Join-Path $RawDir "$slug.fetch.tmp"
        $result   = python $pyScript $Url $tmp 2>&1
        Write-Host "       $result"
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tmp)) {
            return @{ Saved = $false; Slug = $slug; Url = $Url; Parts = @() }
        }
        $body = [System.IO.File]::ReadAllText($tmp, [System.Text.Encoding]::UTF8)
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        $content = $body -replace '(?s)^SOURCE_URL:[^\n]*\r?\n---\r?\n', ''   # strip header
        $content = Format-WrappedText $content
    } else {
        Write-Host "  [DL] $Url"
        try {
            $resp    = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 25 -ErrorAction Stop
            $content = Get-PlainText $resp.Content
        } catch {
            Write-Host "       failed: $($_.Exception.Message)"
            return @{ Saved = $false; Slug = $slug; Url = $Url; Parts = @() }
        }
    }

    # 2) Chunk + write part files.
    $chunks = Split-IntoChunks -Text $content -MaxChars $MaxRawChars
    $n      = $chunks.Count
    $parts  = [System.Collections.Generic.List[string]]::new()
    for ($k = 0; $k -lt $n; $k++) {
        if ($n -eq 1) {
            $name   = "$slug.txt"
            $header = "SOURCE_URL: $Url`n---`n"
        } else {
            $name   = ("{0}.part{1:D2}.txt" -f $slug, ($k + 1))
            $header = "SOURCE_URL: $Url`nPART: $($k + 1)/$n`n---`n"
        }
        [System.IO.File]::WriteAllText((Join-Path $RawDir $name), $header + $chunks[$k], [System.Text.Encoding]::UTF8)
        $parts.Add($name)
    }
    if ($n -gt 1) { Write-Host "       saved $n parts ($($content.Length) chars > $MaxRawChars)" }
    else          { Write-Host "       saved -> $slug.txt" }
    return @{ Saved = $true; Slug = $slug; Url = $Url; Parts = @($parts.ToArray()) }
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
                $parts       = @($fetchResult.Parts)
                if ($saved) { $fetched++ } else { $failed++ }   # count the source once, not per chunk

                # Part 1 reuses the original candidate row (clean URL).
                $firstRaw = if ($parts.Count -gt 0) { "raw/$($parts[0])" } else { "" }
                $newBlock = [System.Collections.Generic.List[string]]::new()
                foreach ($bl in $block) {
                    if ($bl -match '^\s+status:\s*pending') {
                        if ($saved) {
                            $newBlock.Add(($bl -replace 'pending', 'fetched'))
                            $newBlock.Add("  raw: $firstRaw")
                        } else {
                            $newBlock.Add(($bl -replace 'pending', 'skipped-fetch'))
                        }
                    } else {
                        $newBlock.Add($bl)
                    }
                }
                $out.AddRange($newBlock)

                # Parts 2..N become their own candidate rows. The url carries a unique
                # #partK token so cmd_mark (match-by-substring) targets the right row;
                # the raw file's SOURCE_URL header stays clean for citations.
                if ($saved -and $parts.Count -gt 1) {
                    $entryType = 'web'; $entryTitle = $url
                    if ($line -match '^- \[(\w+)\]\s*(.+?)\s+(?:--|—)\s+') { $entryType = $Matches[1]; $entryTitle = $Matches[2].Trim() }
                    for ($p = 1; $p -lt $parts.Count; $p++) {
                        $pn = $p + 1
                        $out.Add("- [$entryType] $entryTitle (part $pn/$($parts.Count)) -- $url#part$pn")
                        $out.Add("  status: fetched")
                        $out.Add("  raw: raw/$($parts[$p])")
                    }
                }
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

# ── Helper: Haiku pre-digest pass (token reduction before INGEST) ─────────────
# Condenses each fetched raw/<slug>.txt to focus-relevant content using a cheap
# model, so the (expensive) INGEST model reads far fewer input tokens per source.
# Keep-by-default: strips chrome only, preserves facts/numbers/citations. The
# original is backed up to raw/<slug>.orig.txt so REVIEW can fall back if a fact
# was over-trimmed. Idempotent: a file that already has a .orig.txt sibling is
# treated as already digested and skipped. Returns @{ LimitHit = $bool }.
function Invoke-RawDigest {
    param(
        [string]$RawDir,
        [string]$TaskMd,
        [string]$LogFile,
        [string]$DigestModel,
        [string]$ClaudeCmd,
        [bool]$LogTokens
    )
    if (-not (Test-Path $RawDir)) { return @{ LimitHit = $false } }
    $focus = Get-TaskField $TaskMd "RESEARCH_FOCUS" ""
    $files = Get-ChildItem -Path $RawDir -Filter *.txt -File |
             Where-Object { $_.Name -notmatch '\.orig\.txt$' }
    foreach ($f in $files) {
        $orig = Join-Path $RawDir ($f.BaseName + ".orig.txt")
        if (Test-Path $orig) { continue }  # already digested
        Write-Host "  [DIGEST] $($f.Name)"
        $prompt = "Mode: WORKER. Token-reduction pre-digest of ONE file. Read: $($f.FullName) (it starts with a SOURCE_URL line). Rewrite it as a condensed digest that KEEPS: the SOURCE_URL line verbatim, every number/date/price/measurement, named entities, direct claims, and anything relevant to RESEARCH_FOCUS: '$focus'. STRIP only: navigation, menus, cookie/consent text, ads, footers, repeated boilerplate, unrelated article links. Do NOT summarize away facts -- keep them, just remove the chrome. Steps: (1) if $orig does not already exist, write a copy of $($f.FullName) to $orig; (2) overwrite $($f.FullName) with the digest. Touch no other files. No user prompts."
        # Digest only reads + rewrites raw files; no state script, no network.
        $digestAllow = @('Read','Glob','Write(MemoryVault/Raw/**)','Edit(MemoryVault/Raw/**)')
        $res = Invoke-WorkerSession -ClaudeCmd $ClaudeCmd -Prompt $prompt -LogFile $LogFile -Model $DigestModel -AllowedTools $digestAllow -LogTokens:$LogTokens
        if ($res.LimitHit) { return @{ LimitHit = $true } }
    }
    return @{ LimitHit = $false }
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

# Hardened-worker allowlist (FETCH). Least privilege: fetch leftover URLs, write
# raw files, drive state. No arbitrary Bash -- closes the prompt-injection -> shell
# hole that --dangerously-skip-permissions left open. Bash scoped to the state script
# only; its path is also injected into the prompt so the worker's command matches.
$StateScriptRel    = "Skills/AnotherSkillBundle/Skills/SharedScripts/research_state.py"
$FetchAllowedTools = @('Read','Glob','WebFetch','Write(MemoryVault/Raw/**)','Edit(MemoryVault/Raw/**)',"Bash(python $StateScriptRel`:*)")

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
            if ($DigestModel) {
                Write-Host "  Pre-digesting raw files with '$DigestModel' (token reduction before INGEST)..."
                $taskMdPath = Join-Path $absTaskDir "task.md"
                $dg = Invoke-RawDigest -RawDir $rawDir -TaskMd $taskMdPath -LogFile $logFile `
                        -DigestModel $DigestModel -ClaudeCmd $ClaudeCmd -LogTokens $LogTokens
                if ($dg.LimitHit) {
                    Write-Host $UsageLimitSentinel
                    $UsageLimitSentinel | Out-File -FilePath $logFile -Append -Encoding utf8
                    exit 42
                }
            }
            Write-Host "  All candidates fetched. Transitioning FETCH -> INGEST."
            Set-ProgressPhase -ProgressFile $progressFile -Phase "INGEST" -Status "READY_INGEST"
            "=== [$stamp] SourceScrape iter $i [PS pre-download: FETCH->INGEST transition] ===" |
                Out-File -FilePath $logFile -Append -Encoding utf8
            break
        }
        Write-Host "  $remaining candidates still pending -- handing to Claude."
    }

    $prompt = "Continue source scrape in $absTaskDir. Mode: WORKER. Follow SourceScrapeSkill protocol (FETCH loop). No user prompts. Pre-downloaded candidates have status 'fetched' with raw: path -- skip WebFetch for those. Handle remaining pending. If no more pending, set PHASE=INGEST STATUS=READY_INGEST and exit. Run the state script via: python $StateScriptRel <cmd> ..."

    "`n=== [$stamp] SourceScrape iter $i ===" | Out-File -FilePath $logFile -Append -Encoding utf8

    try {
        $res = Invoke-WorkerSession -ClaudeCmd $ClaudeCmd -Prompt $prompt -LogFile $logFile -Model $Model -Agent $Agent -AllowedTools $FetchAllowedTools -LogTokens:$LogTokens
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
