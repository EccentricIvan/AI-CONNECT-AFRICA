<#
.SYNOPSIS
  Fetch the official TranslatePsy-AfriSLM 0.8B Q4_K_M GGUF into assets/models.

.EXAMPLE
  .\tools\fetch_afrislm_q4.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$out = Join-Path $repoRoot 'assets\models\afrislm-0.8b-q4_k_m.gguf'

# Official pre-quantized file (importance-matrix Q4_K_M). Equivalent one-liner:
#   hf download qvac/TranslatePsy-AfriSLM-0.8B-Q4-GGUF `
#     TranslatePsy-AfriSLM-0.8B-Q4_K_M-imat.gguf `
#     --local-dir tools\.cache\published-Q4_K_M
#   copy to assets\models\afrislm-0.8b-q4_k_m.gguf
& (Join-Path $PSScriptRoot 'setup_afrislm.ps1') -Quant Q4_K_M -OutFile $out
