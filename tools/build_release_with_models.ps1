<#
.SYNOPSIS
  Builds a plug-and-play Android APK that embeds the two models (the
  Qwen2.5-Coder-1.5B brain + the AfriSLM translator),
  and optionally a Windows zip with a models/ folder beside the exe.

.DESCRIPTION
  Copies model files from -ModelPackDir into:
    - android/app/src/main/assets/models/  (APK AssetManager path)
    - build\windows\...\Release\models\   (after Windows build)

  Models are NEVER committed to git. After the APK build, injected assets are
  removed so the working tree stays clean.

.PARAMETER ModelPackDir
  Folder containing qwen2.5-coder-1.5b-instruct.gguf and translate-afrislm.gguf
  (default: <repo>\dist\models)

.PARAMETER Version
  Marketing version used in output filenames, e.g. 1.2.0

.PARAMETER Target
  android | windows | both

.EXAMPLE
  .\tools\build_release_with_models.ps1 -Version 1.2.0
#>

param(
  [string] $ModelPackDir = '',
  [Parameter(Mandatory = $true)] [string] $Version,
  [ValidateSet('android', 'windows', 'both')]
  [string] $Target = 'both',
  [string] $OutDir = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
if (-not $ModelPackDir) { $ModelPackDir = Join-Path $repoRoot 'dist\models' }
if (-not $OutDir) { $OutDir = Join-Path $repoRoot 'dist' }

# The one brain: reasoning, tutoring and code.
$chatName = 'qwen2.5-coder-1.5b-instruct.gguf'
$translateName = 'translate-afrislm.gguf'
$chatSrc = Join-Path $ModelPackDir $chatName
$translateSrc = Join-Path $ModelPackDir $translateName

foreach ($f in @($chatSrc, $translateSrc)) {
  if (-not (Test-Path $f)) {
    throw @"
Missing model file: $f

Place both files in $ModelPackDir :
  - $chatName
  - $translateName

Then re-run this script. Models stay gitignored; they are only injected at build time.
"@
  }
}

New-Item -ItemType Directory -Force $OutDir | Out-Null

$androidAssetsModels = Join-Path $repoRoot 'android\app\src\main\assets\models'
function Clear-InjectedAndroidAssets {
  if (Test-Path $androidAssetsModels) {
    Get-ChildItem $androidAssetsModels -File |
      Where-Object { $_.Name -match '\.(litertlm|gguf)$' } |
      Remove-Item -Force
  }
}

function Inject-AndroidAssets {
  New-Item -ItemType Directory -Force $androidAssetsModels | Out-Null
  Clear-InjectedAndroidAssets
  Copy-Item $chatSrc (Join-Path $androidAssetsModels $chatName) -Force
  Copy-Item $translateSrc (Join-Path $androidAssetsModels $translateName) -Force
  Write-Host "Injected models into $androidAssetsModels" -ForegroundColor Cyan
}

Push-Location $repoRoot
try {
  if ($Target -in @('android', 'both')) {
    Write-Host '== Building Android APK with bundled models ==' -ForegroundColor Green
    Inject-AndroidAssets
    try {
      # arm64 only: LiteRT / QNN / llama.cpp natives are arm64-v8a anyway, and
      # --split-per-abi would duplicate the ~1.2 GB model payload into every ABI
      # APK (~4 GB of output) for two APKs we would throw away.
      $flutterApkDir = Join-Path $repoRoot 'build\app\outputs\flutter-apk'
      # Stale APKs from an earlier slim or split build must not be mistaken
      # for this build's output.
      Get-ChildItem $flutterApkDir -Filter '*.apk' -File -ErrorAction SilentlyContinue |
        Remove-Item -Force

      flutter build apk --release --target-platform android-arm64
      if ($LASTEXITCODE -ne 0) { throw 'flutter build apk failed' }

      $apkSrc = Join-Path $flutterApkDir 'app-release.apk'
      if (-not (Test-Path $apkSrc)) {
        $apkSrc = Join-Path $flutterApkDir 'app-arm64-v8a-release.apk'
      }
      if (-not (Test-Path $apkSrc)) { throw "APK not found after build" }

      $apkDest = Join-Path $OutDir "AI Connect Africa v$Version-with-models.apk"
      Copy-Item $apkSrc $apkDest -Force
      $sizeMb = [math]::Round((Get-Item $apkDest).Length / 1MB, 1)
      Write-Host "Android fat APK ready: $apkDest ($sizeMb MB)" -ForegroundColor Green
      Write-Host "Download link after publish:" -ForegroundColor Yellow
      Write-Host "  https://github.com/<owner>/<repo>/releases/download/v$Version/AI%20Connect%20Africa%20v$Version-with-models.apk"
    }
    finally {
      Clear-InjectedAndroidAssets
      Write-Host 'Cleared injected model assets from android/ tree' -ForegroundColor DarkGray
    }
  }

  if ($Target -in @('windows', 'both')) {
    Write-Host '== Building Windows release with models/ ==' -ForegroundColor Green
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'flutter build windows failed' }

    $winRelease = Join-Path $repoRoot 'build\windows\x64\runner\Release'
    $winModels = Join-Path $winRelease 'models'
    New-Item -ItemType Directory -Force $winModels | Out-Null
    Copy-Item $chatSrc (Join-Path $winModels $chatName) -Force
    Copy-Item $translateSrc (Join-Path $winModels $translateName) -Force

    $zipDest = Join-Path $OutDir "AI Connect Africa Windows v$Version.zip"
    if (Test-Path $zipDest) { Remove-Item $zipDest -Force }
    Compress-Archive -Path (Join-Path $winRelease '*') -DestinationPath $zipDest -Force
    $sizeMb = [math]::Round((Get-Item $zipDest).Length / 1MB, 1)
    Write-Host "Windows zip ready: $zipDest ($sizeMb MB)" -ForegroundColor Green
  }
}
finally {
  Pop-Location
}

Write-Host ''
Write-Host 'Next: publish with' -ForegroundColor Cyan
Write-Host "  .\tools\publish_release.ps1 -Version $Version -ArtifactDir `"$OutDir`" -WithModels"
