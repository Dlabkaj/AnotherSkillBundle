#Requires -Version 5.0
<#
.SYNOPSIS
    Ingest one raw source file with a local Ollama model: chunk, generate, append to wiki, report.

.DESCRIPTION
    Called from the autoresearch INGEST loop (or by Jerry) when a task uses a local
    model instead of Claude for per-source extraction. Loads localAIModels.json,
    chunks the raw file to fit the model's num_ctx, POSTs each chunk to Ollama
    /api/generate with the caller's extraction prompt, appends the combined output
    to the target wiki page under a marker, and prints a parseable status block.

    Claude stays the orchestrator: it selects the candidate, composes the prompt,
    reads this status, then marks done / updates progress itself. This script does
    NOT touch progress.md or research_state.py.

.EXAMPLE
    .\Run-LocalIngestion.ps1 -RawFile .\raw\foo.txt -WikiTarget .\Wiki\Foo\Index.md `
        -Prompt "Extract facts about heat pumps. Output Czech wiki bullets. Cite the SOURCE_URL. Tag crisp atoms *(unverified)*."

# qa-dry: powershell -NoProfile -File .\Run-LocalIngestion.ps1 -RawFile .\fixtures\sample.txt -WikiTarget .\fixtures\out.md -Prompt "extract" -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$RawFile,

    [Parameter(Mandatory = $true)]
    [string]$WikiTarget,

    [string]$Prompt,

    [string]$PromptFile,

    [string]$Model,

    [string]$ConfigPath,

    [int]$TimeoutSec = 600
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8
$ErrorActionPreference    = "Stop"

$Utf8NoBom     = New-Object System.Text.UTF8Encoding($false)
$CharsPerToken = 4        # rough heuristic for chunk sizing
$InputBudget   = 0.5      # fraction of num_ctx reserved for prompt+input; rest for output+overhead

function Write-ErrExit {
    param([string]$Message, [int]$Code = 1)
    Write-Host "ERROR: $Message"
    exit $Code
}

# --- Resolve inputs -------------------------------------------------------
if (-not (Test-Path -LiteralPath $RawFile)) {
    Write-ErrExit "Raw file not found: '$RawFile'. Expected a readable .txt source."
}

if (-not $Prompt -and -not $PromptFile) {
    Write-ErrExit "Provide -Prompt or -PromptFile (the extraction instructions)."
}
if ($PromptFile) {
    if (-not (Test-Path -LiteralPath $PromptFile)) {
        Write-ErrExit "PromptFile not found: '$PromptFile'."
    }
    $Prompt = Get-Content -LiteralPath $PromptFile -Raw -Encoding UTF8
}

if (-not $ConfigPath) {
    # default: localAIModels.json at repo root, four levels up from this script
    # (Skills/AnotherSkillBundle/Skills/LocalModelIngestionSkill/ -> repo root)
    $ConfigPath = Join-Path $PSScriptRoot "..\..\..\..\localAIModels.json"
}
if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Write-ErrExit "Config not found: '$ConfigPath'. Expected localAIModels.json at the repo root."
}

# --- Load config ----------------------------------------------------------
try {
    $config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Write-ErrExit "Failed to parse config '$ConfigPath': $_"
}

$endpoint = if ($config.endpoint) { $config.endpoint } else { "http://localhost:11434" }
$endpoint = $endpoint.TrimEnd('/')

$modelName = if ($Model) { $Model } elseif ($config.defaultModel) { $config.defaultModel } else { "" }
if (-not $modelName) {
    Write-ErrExit "No model specified and no defaultModel in config."
}

$modelEntry = $config.models | Where-Object { $_.name -eq $modelName } | Select-Object -First 1
if (-not $modelEntry) {
    Write-ErrExit "Model '$modelName' not in config models[]. Add it to '$ConfigPath'."
}

$numCtx = 8192
if ($modelEntry.options -and $modelEntry.options.num_ctx) {
    $numCtx = [int]$modelEntry.options.num_ctx
}
$streamCfg = $false
if ($modelEntry.PSObject.Properties.Name -contains "stream") { $streamCfg = [bool]$modelEntry.stream }
if ($streamCfg) {
    Write-Host "NOTE: stream=true in config is not implemented; using non-streaming request."
}

# --- Parse raw file: SOURCE_URL header + body -----------------------------
$rawText = Get-Content -LiteralPath $RawFile -Raw -Encoding UTF8
$sourceUrl = "(unknown)"
$body = $rawText
$firstNewline = $rawText.IndexOf("`n")
$firstLine = if ($firstNewline -ge 0) { $rawText.Substring(0, $firstNewline) } else { $rawText }
$firstLine = $firstLine.TrimStart([char]0xFEFF).Trim()
if ($firstLine -match '^SOURCE_URL:\s*(.+)$') {
    $sourceUrl = $Matches[1].Trim()
    $body = if ($firstNewline -ge 0) { $rawText.Substring($firstNewline + 1) } else { "" }
    # drop a leading "---" separator line if present
    $body = $body -replace '^\s*---\s*\r?\n', ''
}

# --- Chunk ----------------------------------------------------------------
$promptTokens  = [math]::Ceiling($Prompt.Length / $CharsPerToken)
$inputTokens   = [math]::Floor($numCtx * $InputBudget)
$chunkTokens   = $inputTokens - $promptTokens
if ($chunkTokens -lt 256) {
    Write-ErrExit "Prompt too large for num_ctx=$numCtx (leaves $chunkTokens input tokens). Shorten prompt or raise num_ctx."
}
$maxChunkChars = [int]($chunkTokens * $CharsPerToken)

function Split-IntoChunks {
    param([string]$Text, [int]$MaxChars)
    $chunks = New-Object System.Collections.Generic.List[string]
    $sb = New-Object System.Text.StringBuilder
    foreach ($line in ($Text -split "\r?\n")) {
        if ($sb.Length -gt 0 -and ($sb.Length + $line.Length + 1) -gt $MaxChars) {
            $chunks.Add($sb.ToString())
            $sb = New-Object System.Text.StringBuilder
        }
        [void]$sb.AppendLine($line)
    }
    if ($sb.Length -gt 0) { $chunks.Add($sb.ToString()) }
    return $chunks
}

$chunks = Split-IntoChunks -Text $body -MaxChars $maxChunkChars
$chunkCount = $chunks.Count

Write-Host "Plan: model=$modelName num_ctx=$numCtx endpoint=$endpoint"
Write-Host "      raw=$RawFile url=$sourceUrl"
Write-Host "      body chars=$($body.Length) max-chunk-chars=$maxChunkChars chunks=$chunkCount"
Write-Host "      wiki target=$WikiTarget"

# --- Generate loop --------------------------------------------------------
$genUri   = "$endpoint/api/generate"
$outputs  = New-Object System.Collections.Generic.List[string]
$errors   = 0

for ($i = 0; $i -lt $chunkCount; $i++) {
    $n = $i + 1
    $reqPromptLines = @(
        $Prompt,
        "",
        "SOURCE_URL: $sourceUrl",
        "--- SOURCE TEXT (chunk $n of $chunkCount) ---",
        $chunks[$i]
    )
    $reqPrompt = $reqPromptLines -join "`n"

    $reqBody = [ordered]@{
        model   = $modelName
        prompt  = $reqPrompt
        stream  = $false
        options = $modelEntry.options
    }
    $json  = $reqBody | ConvertTo-Json -Depth 6
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)

    if (-not $PSCmdlet.ShouldProcess("$genUri (chunk $n/$chunkCount)", "POST generate")) {
        continue
    }

    try {
        $resp = Invoke-RestMethod -Uri $genUri -Method Post -Body $bytes `
            -ContentType "application/json" -TimeoutSec $TimeoutSec
        if ($resp.response) {
            $outputs.Add($resp.response)
            Write-Host "  chunk $n/$chunkCount OK (out chars=$($resp.response.Length))"
        } else {
            $errors++
            Write-Host "  chunk $n/$chunkCount returned empty response"
        }
    } catch {
        $errors++
        $msg = "$_"
        if ($msg -match "actively refused|Unable to connect|No connection") {
            Write-Host "  chunk $n/$chunkCount FAILED: cannot reach Ollama at $endpoint. Is it running? Start the tray app or run 'ollama serve'."
        } elseif ($msg -match "404|not found") {
            Write-Host "  chunk $n/$chunkCount FAILED: model '$modelName' not available. Pull it: ollama pull $modelName"
        } else {
            Write-Host "  chunk $n/$chunkCount FAILED: $msg"
        }
    }
}

# --- Append to wiki -------------------------------------------------------
$charsAppended = 0
$combined = ($outputs -join "`n`n").Trim()

if ($combined.Length -gt 0) {
    $stamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    $marker = "<!-- local-ingest: $sourceUrl @ $stamp model=$modelName chunks=$chunkCount -->"
    $blockLines = @("", $marker, $combined, "")
    $block = $blockLines -join "`n"

    if ($PSCmdlet.ShouldProcess($WikiTarget, "append $($combined.Length) chars")) {
        $wikiDir = Split-Path -Parent $WikiTarget
        if ($wikiDir -and -not (Test-Path -LiteralPath $wikiDir)) {
            New-Item -ItemType Directory -Path $wikiDir -Force | Out-Null
        }
        [System.IO.File]::AppendAllText($WikiTarget, $block, $Utf8NoBom)
        $charsAppended = $combined.Length
    }
}

# --- Status report --------------------------------------------------------
$result = if ($WhatIfPreference) { "DRY-RUN" }
          elseif ($errors -eq 0 -and $charsAppended -gt 0) { "OK" }
          elseif ($charsAppended -gt 0) { "PARTIAL" }
          else { "FAILED" }

Write-Host ""
Write-Host "=== LocalIngestion status ==="
Write-Host "MODEL: $modelName"
Write-Host "RAW: $RawFile"
Write-Host "URL: $sourceUrl"
Write-Host "WIKI_TARGET: $WikiTarget"
Write-Host "CHUNKS: $chunkCount"
Write-Host "CHARS_APPENDED: $charsAppended"
Write-Host "ERRORS: $errors"
Write-Host "RESULT: $result"

if ($result -eq "FAILED") { exit 1 }
exit 0
# (DRY-RUN and PARTIAL exit 0; only a run that produced nothing is a hard failure)
