<#
.SYNOPSIS
  Fetch qvac/TranslatePsy-AfriSLM-0.8B and emit a compact GGUF for the app.

.DESCRIPTION
  Single-runtime setup. The app loads one GGUF via llama.cpp — there is no
  NLLB ONNX or LiteRT/Qwen chat model on this path.

  Pipeline:
    1. For Q4_K_M / Q8_0: hf download of the official published GGUF (preferred).
    2. For other quants (default Q5_K_M): hf download of full-precision HF
       weights, then llama.cpp convert_hf_to_gguf.py → llama-quantize.
    3. Copy to assets/models/afrislm-0.8b-<quant>.gguf (gitignored)

  Needs internet on the *dev* machine. The app still runs fully offline.

.PARAMETER Quant
  llama-quantize type. Q5_K_M is the default for 8 GB laptops / 4 GB phones.
  Use Q4_K_M if the file busts storage.

.PARAMETER OutFile
  Destination GGUF. Defaults to assets/models/afrislm-0.8b-q5_k_m.gguf
  (or …-q4_k_m.gguf when -Quant is Q4_K_M).

.PARAMETER SkipDownload
  Reuse weights already under tools/.cache/TranslatePsy-AfriSLM-0.8B.

.EXAMPLE
  .\tools\setup_afrislm.ps1
  .\tools\setup_afrislm.ps1 -Quant Q4_K_M
#>
[CmdletBinding()]
param(
  [string]$Quant = 'Q5_K_M',
  [string]$OutFile,
  [switch]$SkipDownload
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$hfId = 'qvac/TranslatePsy-AfriSLM-0.8B'
$cache = Join-Path $PSScriptRoot '.cache'
$srcDir = Join-Path $cache 'TranslatePsy-AfriSLM-0.8B'

if (-not $OutFile) {
  $suffix = $Quant.ToLower()
  $OutFile = Join-Path $repoRoot "assets\models\afrislm-0.8b-$suffix.gguf"
}

Write-Host ("AfriSLM setup -> {0} ({1})" -f $OutFile, $Quant) -ForegroundColor Cyan

function Ensure-HfCli {
  $hf = Get-Command hf -ErrorAction SilentlyContinue
  if (-not $hf) {
    Write-Host "Installing huggingface_hub (hf CLI)..." -ForegroundColor Cyan
    python -m pip install -U huggingface_hub
    $hf = Get-Command hf -ErrorAction SilentlyContinue
  }
  if (-not $hf) { throw "hf CLI not found after installing huggingface_hub." }
}

# Official GGUF repos — skip convert when Hugging Face already ships this quant.
$publishedGguf = @{
  'Q4_K_M' = @{
    Repo = 'qvac/TranslatePsy-AfriSLM-0.8B-Q4-GGUF'
    File = 'TranslatePsy-AfriSLM-0.8B-Q4_K_M-imat.gguf'
  }
  'Q8_0' = @{
    Repo = 'qvac/TranslatePsy-AfriSLM-0.8B-Q8-GGUF'
    File = 'TranslatePsy-AfriSLM-0.8B-Q8_0-imat.gguf'
  }
}

function Download-PublishedGguf {
  param([string]$QuantType, [string]$Dest)
  $spec = $publishedGguf[$QuantType]
  if (-not $spec) { throw "No published GGUF mapping for $QuantType" }
  Ensure-HfCli
  $ggufCache = Join-Path $cache "published-$QuantType"
  New-Item -ItemType Directory -Force -Path $ggufCache | Out-Null
  Write-Host "Downloading $($spec.Repo) / $($spec.File)..." -ForegroundColor Cyan
  & hf download $spec.Repo $spec.File --local-dir $ggufCache
  if ($LASTEXITCODE -ne 0) { throw "hf download failed (exit $LASTEXITCODE)" }
  $src = Join-Path $ggufCache $spec.File
  if (-not (Test-Path $src)) { throw "Downloaded GGUF missing: $src" }
  New-Item -ItemType Directory -Force -Path (Split-Path $Dest -Parent) | Out-Null
  Copy-Item $src $Dest -Force
  $sizeMB = [math]::Round((Get-Item $Dest).Length / 1MB, 1)
  if ($sizeMB -lt 250) {
    throw ("Downloaded GGUF is only {0} MB - likely truncated." -f $sizeMB)
  }
  Write-Host ("Wrote {0} ({1} MB, {2})" -f $Dest, $sizeMB, $QuantType) -ForegroundColor Green
}

if ($publishedGguf.ContainsKey($Quant)) {
  Download-PublishedGguf -QuantType $Quant -Dest $OutFile
} else {
  if (-not $SkipDownload) {
    Ensure-HfCli
    Write-Host "Downloading $hfId (full-precision weights)..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $srcDir | Out-Null
    & hf download $hfId --local-dir $srcDir
    if ($LASTEXITCODE -ne 0) { throw "hf download failed (exit $LASTEXITCODE)" }
  }

  if (-not (Test-Path (Join-Path $srcDir 'config.json'))) {
    throw "No config.json in $srcDir. Re-run without -SkipDownload, or unpack HF weights there."
  }

  try {
    & (Join-Path $PSScriptRoot 'quantize_translate_model.ps1') `
      -SourceDir $srcDir `
      -OutFile $OutFile `
      -Quant $Quant `
      -MaxSizeMB 1200
  } catch {
    Write-Warning "Convert/quantize failed: $_"
    $fallback = Join-Path $repoRoot 'assets\models\afrislm-0.8b-q4_k_m.gguf'
    Write-Host ("Falling back to official Q4_K_M GGUF -> {0}" -f $fallback) -ForegroundColor Yellow
    Download-PublishedGguf -QuantType 'Q4_K_M' -Dest $fallback
    $OutFile = $fallback
  }
}

Write-Host ("`nInstall: copy {0} next to the exe under models\, or Settings -> Install from file." -f $OutFile) -ForegroundColor Gray
Write-Host "Canonical name the app looks for first: afrislm-0.8b-q5_k_m.gguf" -ForegroundColor Gray
Write-Host "Accepted alternate: afrislm-0.8b-q4_k_m.gguf" -ForegroundColor Gray
