# Proves the generated projects really work: every generated backend installs
# and passes its own tests, and every generated frontend script (including
# the merged scripts of each real template) parses. Run after changing
# anything under lib/features/projects/scaffold/.
#
#   powershell -ExecutionPolicy Bypass -File tools/verify_scaffolds.ps1
#
# Needs Python 3.10+ (and Node for the JavaScript check) plus an internet
# connection for the one pip install - a developer check, the app itself
# never runs this.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path ([System.IO.Path]::GetTempPath()) "otic-scaffold-check"
if (Test-Path $out) { Remove-Item -Recurse -Force $out }

Push-Location $root
try {
  dart run tools/write_sample_projects.dart $out
  if ($LASTEXITCODE -ne 0) { throw "Writing the sample projects failed." }
} finally { Pop-Location }

$venv = Join-Path $out ".venv"
python -m venv $venv
$py = Join-Path $venv "Scripts\python.exe"
if (-not (Test-Path $py)) { $py = Join-Path $venv "bin/python" }

# Every project pins the same requirements, so one install covers them all.
& $py -m pip install --quiet -r (Join-Path $out "website\backend\requirements.txt")
if ($LASTEXITCODE -ne 0) { throw "pip install failed." }

$failed = @()

if (Get-Command node -ErrorAction SilentlyContinue) {
  $scripts = Get-ChildItem $out -Recurse -Filter *.js |
    Where-Object { $_.FullName -notlike "*\.venv\*" }
  foreach ($js in $scripts) {
    node --check $js.FullName
    if ($LASTEXITCODE -ne 0) { $failed += $js.FullName }
  }
  Write-Host ("Checked " + $scripts.Count + " frontend scripts.")
} else {
  Write-Warning "node not found - skipping the frontend JavaScript syntax check."
}

$backends = Get-ChildItem $out -Directory | Where-Object { $_.Name -notin @(".venv", "_frontends") }
if ($backends.Count -eq 0) { throw "No sample projects were written." }
foreach ($project in $backends) {
  Push-Location (Join-Path $project.FullName "backend")
  try {
    & $py -m pytest -q
    if ($LASTEXITCODE -ne 0) { $failed += $project.Name }
  } finally { Pop-Location }
}

if ($failed.Count -gt 0) {
  throw ("Scaffold checks failed for: " + ($failed -join ", "))
}
Write-Host ("All " + $backends.Count + " generated backends passed their tests and every frontend script parses.")
