# Releasing

How to build, sign, and publish an AI Connect Africa release that includes a
**single Android download with the AI models inside**, plus the Windows zip.

---

## 0. Prerequisites

- Flutter on PATH, `flutter doctor` green for Windows + Android.
- Android keystore wired through `android/key.properties` (gitignored). `storeFile`
  is resolved by Gradle relative to **`android/app/`**, not `android/` — a keystore
  kept at `android/release-keystore.jks` must be written as
  `storeFile=../release-keystore.jks`. Getting this wrong fails the build at
  `:app:validateSigningRelease` only after the full ~50-minute compile, and the
  "falls back to debug signing" path in `build.gradle.kts` does **not** rescue it:
  that fallback fires only when `key.properties` is missing entirely.
- `gh` authenticated once (`gh auth login`).
- Model pack on disk (never commit these):

```
dist\models\chat-model.litertlm
dist\models\translate-afrislm.gguf
```

---

## 1. Bump the version

In `pubspec.yaml`:

```yaml
version: 1.3.0+4        # marketingVersion+buildNumber — bump both
```

Add a [CHANGELOG.md](../CHANGELOG.md) entry. Commit.

---

## 1b. Refresh the translation keys

Any new `tr()` / `trFill()` string is English-only until it reaches the
generator, and `tr()` falls back silently — so the miss shows up as English on
a Kinyarwanda device, never as an error. Before a release:

```powershell
dart run tools/scan_l10n_keys.dart          # rewrite tools/l10n_keys.json
dart run tools/scan_l10n_keys.dart --check  # non-zero if it is stale
flutter test tools/generate_ui_strings.dart # hours — writes ui_strings_generated.dart
```

The generator needs `dist\models\translate-afrislm.gguf` and checkpoints to
`tools/.l10n_progress.json` after each language, so an interrupted run resumes.

---

## 1c. Play Store artifact

Play needs an **AAB**, not the APK these steps produce, and CI has no keystore
— build it on the machine that holds `android/release-keystore.jks`:

```powershell
flutter build appbundle --release   # build\app\outputs\bundle\release\app-release.aab
```

See [PLAY_STORE_ASSET_DELIVERY.md](PLAY_STORE_ASSET_DELIVERY.md). The APK below
stays the sideload / USB / download-link artifact.

---

## 2. Build with models (recommended)

```powershell
.\tools\build_release_with_models.ps1 -Version 1.2.0
```

This injects the model pack into `android/app/src/main/assets/models/`, builds
a fat arm64 APK, clears the injected files from the tree, and builds a Windows
zip with a `models/` folder next to the exe.

Outputs in `dist\`:

- `AI Connect Africa v1.2.0-with-models.apk`  (~1–1.5 GB)
- `AI Connect Africa Windows v1.2.0.zip`

---

## 3. Publish — get the download link

```powershell
.\tools\publish_release.ps1 -Version 1.2.0 -WithModels
```

The script prints the **direct Android URL**, for example:

```
https://github.com/<owner>/<repo>/releases/download/v1.2.0/AI%20Connect%20Africa%20v1.2.0-with-models.apk
```

Share that link. Installers get chat + translation with no extra model step.
First app launch unpacks the assets once (~1 GB free space on the phone).

---

## 4. One-time: CI model pack (optional rolling fat APK)

So GitHub Actions can rebuild a with-models APK without checking models into git:

```powershell
gh release create model-pack `
  dist\models\chat-model.litertlm `
  dist\models\translate-afrislm.gguf `
  --title "Model pack (not an app release)" `
  --notes "Source assets for fat Android APK builds. Not for end users."
```

Then run **Actions → Build Release Artifacts → Run workflow** with
**bundle_models = true**. That uploads
`ai-connect-africa-latest-with-models.apk` to the `latest-build` release.

Default pushes to `main` still publish a **slim** APK (fast CI).

---

## 5. Offline USB bundle

```powershell
.\tools\make_update_package.ps1 -WithModels -Version 1.2.0
```

---

## Quick reference

| Step | Command |
|---|---|
| Build fat Android + Windows | `.\tools\build_release_with_models.ps1 -Version X.Y.Z` |
| Publish + print download URL | `.\tools\publish_release.ps1 -Version X.Y.Z -WithModels` |
| USB bundle with models | `.\tools\make_update_package.ps1 -WithModels -Version X.Y.Z` |
| Auth (once) | `gh auth login` |

---

## Troubleshooting: "Bad Image ... error status 0xC0E90002" on Windows

A tester reports the app refusing to start, with a `Bad Image` dialog naming
one plugin DLL after another (`flutter_tts_plugin.dll`,
`webview_flutter_windows_plugin.dll`, `share_plus_plugin.dll`, ...).

**This is not a corrupt download or a broken build.** `0xC0E90002` is a Code
Integrity policy violation: Windows 11's **Smart App Control** (or S mode)
refuses to load unsigned DLLs. A Flutter release folder ships
`flutter_windows.dll` plus one unsigned DLL per plugin, so on a machine with
SAC enabled *none* of it loads. Dropping plugins does not help.

Confirm it on the affected machine: Event Viewer -> Applications and Services
Logs -> Microsoft -> Windows -> **CodeIntegrity -> Operational**, look for
event **3077** naming the blocked DLLs.

### What the user can do now

1. Right-click the downloaded `.zip` -> Properties -> tick **Unblock** ->
   *then* extract. Clears Mark-of-the-Web. Free to try, not guaranteed.
2. Copy the app from a USB stick instead of downloading it - files that never
   came from the internet carry no Mark-of-the-Web.
3. Turn Smart App Control off (Windows Security -> App & browser control).
   This works, but **it cannot be turned back on without reinstalling
   Windows** - do not suggest this to a school casually.

### The actual fix: sign the build

`tools/sign_windows_build.ps1` signs every `.exe`/`.dll` in the release
folder with SHA-256 plus an RFC-3161 timestamp. It is already wired into the
Windows CI job and no-ops when no certificate is configured, so unsigned
builds keep working.

Locally:

```powershell
flutter build windows --release
.\tools\sign_windows_build.ps1 -PfxPath C:\certs\aca.pfx -PfxPassword $env:CERT_PW
```

In CI, set two repository secrets and the job signs automatically:

| Secret | Value |
|--------|-------|
| `WINDOWS_CERT_PFX_BASE64` | the `.pfx` file, base64-encoded |
| `WINDOWS_CERT_PASSWORD`   | its password |

To produce the base64 blob:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\certs\aca.pfx')) | Set-Clipboard
```

**Certificate choice matters.** Smart App Control trusts certificates with
established reputation. A brand-new **OV** certificate can still be blocked
until it earns that reputation, which takes time and download volume. An
**EV** code-signing certificate is trusted immediately and is the reliable
choice if schools must be able to install on day one.
