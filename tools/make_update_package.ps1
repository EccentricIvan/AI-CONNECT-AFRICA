# AI Connect Africa — offline update package builder
#
# Builds release artifacts and zips them into a dated update package
# you can copy to a USB drive or a local school server. No internet
# is needed on the receiving devices.
#
# For a plug-and-play Android APK that already contains the AI models,
# prefer:  .\tools\build_release_with_models.ps1 -Version X.Y.Z
#
# Usage (from the repo root):
#   powershell -ExecutionPolicy Bypass -File tools\make_update_package.ps1 [-Target windows|apk|both]
#   powershell -ExecutionPolicy Bypass -File tools\make_update_package.ps1 -WithModels

param(
    [ValidateSet('windows', 'apk', 'both')]
    [string]$Target = 'both',
    [switch]$WithModels,
    [string]$ModelPackDir = '',
    [string]$Version = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$stamp = Get-Date -Format 'yyyy-MM-dd'
$outDir = Join-Path $root "dist\otic-update-$stamp"

if ($WithModels) {
    if (-not $Version) { $Version = $stamp }
    Write-Host 'Delegating to build_release_with_models.ps1 …' -ForegroundColor Cyan
    $args = @{
        Version = $Version
        OutDir  = $outDir
        Target  = $(if ($Target -eq 'apk') { 'android' } elseif ($Target -eq 'windows') { 'windows' } else { 'both' })
    }
    if ($ModelPackDir) { $args.ModelPackDir = $ModelPackDir }
    & (Join-Path $PSScriptRoot 'build_release_with_models.ps1') @args
    @"
AI Connect Africa update package — $stamp (WITH MODELS)

ANDROID
  1. Copy "AI Connect Africa v$Version-with-models.apk" to the phone.
  2. Open it and allow Install unknown apps.
  3. First launch unpacks the bundled tutor + translation models (~2 GB free space).
  4. No separate model USB step.

WINDOWS
  1. Extract the Windows zip anywhere.
  2. Run "AI Connect Africa.exe" — models/ next to the exe is used automatically.

No internet connection is required after the download.
"@ | Out-File -Encoding utf8 (Join-Path $outDir 'README.txt')
    Write-Host "`nUpdate package created at: $outDir" -ForegroundColor Green
    return
}

New-Item -ItemType Directory -Force $outDir | Out-Null

if ($Target -in @('windows', 'both')) {
    Write-Host '== Building Windows release ==' -ForegroundColor Cyan
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'Windows build failed' }
    $winOut = Join-Path $root 'build\windows\x64\runner\Release'
    Compress-Archive -Path "$winOut\*" `
        -DestinationPath (Join-Path $outDir "AI Connect Africa Windows $stamp.zip") -Force
    Write-Host "Windows package ready" -ForegroundColor Green
}

if ($Target -in @('apk', 'both')) {
    Write-Host '== Building Android release APK (slim, no models) ==' -ForegroundColor Cyan
    flutter build apk --release
    if ($LASTEXITCODE -ne 0) { throw 'APK build failed' }
    Copy-Item (Join-Path $root 'build\app\outputs\flutter-apk\app-release.apk') `
        (Join-Path $outDir "AI Connect Africa $stamp.apk")
    Write-Host "APK package ready" -ForegroundColor Green
}

@"
AI Connect Africa update package — $stamp

WINDOWS
  1. Copy the zip to the target PC and extract anywhere (e.g. C:\OTIC).
  2. Run "AI Connect Africa.exe". Student data is stored separately in
     Documents and is preserved across updates.

ANDROID
  1. Copy the .apk to the phone (USB cable or SD card).
  2. Open it with the file manager and allow 'Install unknown apps'.
  3. Installing over an older version keeps all student data.

AI MODELS (slim package — install once per device)
  Prefer rebuilding with -WithModels for a single fat APK.
  Otherwise use Install from file in the app:
  - Tutor (all answers and code): qwen2.5-coder-1.5b-instruct.gguf
  - Translation: translate-afrislm.gguf

No internet connection is required for any step.
"@ | Out-File -Encoding utf8 (Join-Path $outDir 'README.txt')

Write-Host "`nUpdate package created at: $outDir" -ForegroundColor Green
