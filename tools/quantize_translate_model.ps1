<#
.SYNOPSIS
  Converts local TranslatePsy-AfriSLM weights to the 4-bit GGUF the app loads.

.DESCRIPTION
  Produces translate-afrislm.gguf: HF safetensors -> f16 GGUF
  (convert_hf_to_gguf.py) -> 4-bit (llama-quantize). That is the only
  quantization this repo needs, and the only output llama.cpp can open.

  NOT AWQ. AWQ writes AWQ-packed safetensors; LlamaCppEngineImpl opens GGUF
  and LiteRtLmEngineImpl opens .litertlm. Neither runtime can load an AWQ
  directory, so quantizing that way yields a model the app silently falls
  back to English around.

  The chat model (Qwen2.5-Coder-1.5B-Instruct) is not handled here either —
  it ships pre-quantized as a GGUF (Apache-2.0, safe to redistribute; see
  CLAUDE.md). No .litertlm export of it is published yet, so Android runs
  it on llama.cpp CPU like every other platform, same as this file.

  Build-time tool. It fetches llama.cpp on a dev machine with internet; the
  app it feeds still runs fully offline. Nothing here touches the device.

.PARAMETER SourceDir
  Local folder of unquantized HF weights (config.json + *.safetensors).

.PARAMETER OutFile
  Destination .gguf. Defaults to assets\models\afrislm-0.8b-q5_k_m.gguf.

.PARAMETER Quant
  llama-quantize type. Q4_K_M is the default: best quality per byte at 4 bits.
  Drop to Q4_0 or Q3_K_M only if the result busts the size budget below.

.PARAMETER MaxSizeMB
  Fails the build if the output is larger. Defaults to 1024 MB — the ceiling
  in CLAUDE.md's model table, and what commit b161396 ("Halve translation
  memory so the app fits a 4 GB phone") left room for.

.EXAMPLE
  .\tools\quantize_translate_model.ps1 -SourceDir C:\Models\TranslatePsy-AfriSLM
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$SourceDir,
  [string]$OutFile,
  [string]$Quant = 'Q4_K_M',
  [int]$MaxSizeMB = 1024
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
if (-not $OutFile) { $OutFile = Join-Path $repoRoot 'assets\models\afrislm-0.8b-q5_k_m.gguf' }

if (-not (Test-Path $SourceDir)) { throw "SourceDir not found: $SourceDir" }
if (-not (Test-Path (Join-Path $SourceDir 'config.json'))) {
  throw "No config.json in $SourceDir - point -SourceDir at unquantized HF weights, not a GGUF."
}

$cache = Join-Path $PSScriptRoot '.cache'
$srcDir = Join-Path $cache 'llama.cpp'
$binDir = Join-Path $cache 'llama.cpp-bin'
New-Item -ItemType Directory -Force -Path $cache | Out-Null

# ── llama.cpp sources: convert_hf_to_gguf.py ships only in the repo, not in
# the release zips, so both are needed.
if (Test-Path (Join-Path $srcDir '.git')) {
  Write-Host "Updating llama.cpp sources..." -ForegroundColor Cyan
  git -C $srcDir pull --ff-only --quiet
} else {
  Write-Host "Cloning llama.cpp sources..." -ForegroundColor Cyan
  git clone --depth 1 https://github.com/ggml-org/llama.cpp $srcDir
}
$converter = Join-Path $srcDir 'convert_hf_to_gguf.py'
if (-not (Test-Path $converter)) { throw "convert_hf_to_gguf.py missing from $srcDir" }

# ── llama-quantize: prebuilt, from the latest release. The natives seeded by
# ensure_llm_llamacpp_prebuilt.ps1 are the runtime (llama.dll) only and carry
# no tools, so this is a separate download.
$quantExe = Join-Path $binDir 'llama-quantize.exe'
if (-not (Test-Path $quantExe)) {
  Write-Host "Fetching llama.cpp release binaries..." -ForegroundColor Cyan
  $rel = Invoke-RestMethod -UseBasicParsing `
    -Uri 'https://api.github.com/repos/ggml-org/llama.cpp/releases/latest' `
    -Headers @{ 'User-Agent' = 'otic-studio' }
  $asset = $rel.assets | Where-Object { $_.name -match 'bin-win-cpu-x64.*\.zip$' } | Select-Object -First 1
  if (-not $asset) {
    $asset = $rel.assets | Where-Object { $_.name -match 'bin-win-.*x64.*\.zip$' } | Select-Object -First 1
  }
  if (-not $asset) { throw "No Windows x64 asset in llama.cpp release $($rel.tag_name)" }

  $zip = Join-Path $cache $asset.name
  if (-not (Test-Path $zip)) {
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing
  }
  if (Test-Path $binDir) { Remove-Item $binDir -Recurse -Force }
  Expand-Archive -Path $zip -DestinationPath $binDir -Force

  # Some release zips nest everything one level down.
  if (-not (Test-Path $quantExe)) {
    $found = Get-ChildItem $binDir -Recurse -Filter 'llama-quantize.exe' | Select-Object -First 1
    if (-not $found) { throw "llama-quantize.exe not found in $($asset.name)" }
    Get-ChildItem $found.Directory -File | ForEach-Object {
      Copy-Item $_.FullName (Join-Path $binDir $_.Name) -Force
    }
  }
}

# ── Python env for the converter.
$venv = Join-Path $cache 'venv'
$py = Join-Path $venv 'Scripts\python.exe'
if (-not (Test-Path $py)) {
  Write-Host "Creating Python venv for the converter..." -ForegroundColor Cyan
  python -m venv $venv
  & $py -m pip install --upgrade pip --quiet
  $reqs = Join-Path $srcDir 'requirements\requirements-convert_hf_to_gguf.txt'
  if (-not (Test-Path $reqs)) { $reqs = Join-Path $srcDir 'requirements.txt' }
  & $py -m pip install -r $reqs --quiet
  if ($LASTEXITCODE -ne 0) { throw "pip install failed for $reqs" }
}

# ── Step 1: HF -> f16 GGUF.
$f16 = Join-Path $cache 'translate-afrislm-f16.gguf'
Write-Host "`n[1/2] Converting weights to f16 GGUF..." -ForegroundColor Cyan
& $py $converter $SourceDir --outfile $f16 --outtype f16
if ($LASTEXITCODE -ne 0) { throw "convert_hf_to_gguf.py failed (exit $LASTEXITCODE)" }

# ── Step 2: f16 -> 4-bit.
Write-Host "`n[2/2] Quantizing to $Quant..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path (Split-Path $OutFile -Parent) | Out-Null
& $quantExe $f16 $OutFile $Quant
if ($LASTEXITCODE -ne 0) { throw "llama-quantize failed (exit $LASTEXITCODE)" }

$sizeMB = [math]::Round((Get-Item $OutFile).Length / 1MB, 1)
Write-Host "`nWrote $OutFile ($sizeMB MB, $Quant)" -ForegroundColor Green

# AfriSlmModelManager rejects anything under 300 MB as a truncated download.
if ($sizeMB -lt 300) {
  Write-Warning "Under 300 MB - AfriSlmModelManager will reject this as truncated. Check the source weights."
}
if ($sizeMB -gt $MaxSizeMB) {
  throw "Output is $sizeMB MB, over the $MaxSizeMB MB budget. Re-run with -Quant Q4_0 or -Quant Q3_K_M."
}

Write-Host "Install it with Settings > Translation model, or copy to dist\models\ for a release zip." -ForegroundColor Gray
