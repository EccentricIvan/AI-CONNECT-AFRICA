# Changelog

All notable changes to AI Connect Africa are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.2.0] — 2026-09-04

### Added
- Localized UI for the 19 AfriSLM languages plus English.
- Dart school-math solver (MathGPT-style) for conversions, percent, linear equations, arithmetic, and rectangle measures.
- Worked-solution step cards, hints, and practice follow-ups in Learn.
- Conversation thread recap so later questions build on earlier teaching without repeating the first reply.

### Changed
- Tutor answers the current question; cached math and lesson notes no longer replay across unrelated turns.

---

## [1.3.0] — 2026-09-07

### Added
- Redesigned home dashboard and a shared `StudioAppBar` header used across every screen.
- `tools/scan_l10n_keys.dart` — derives `tools/l10n_keys.json` from the actual
  `tr()` call sites instead of a hand-maintained list, with a `--check` mode.
  The generator's header had always referred to "the scanner"; it did not exist,
  so new UI strings silently fell back to English.

### Fixed
- Home reported "Today's Progress" from lifetime lesson counts against a goal
  clamped to 5, so it read "5 / 5" every day once a student had ever completed
  five lessons. It now reports the active path's real progress.
- The chat FAB sat at `top: -18` in a 72px bar, putting its top 18px outside the
  nav bar's render box — visible but not tappable. The box is now taller than
  the bar, so the whole button takes taps.
- Restored the CREATE and MORE home sections. The redesign dropped eight
  destinations (`/sitechat`, `/weblab`, `/pythonlab`, `/applab`, `/projects`,
  `/achievements`, `/certificates`, `/settings`), none of which has a bottom-nav tab.
- The labs and site/website builders had no way to open the drawer after the
  shell's floating menu button was removed; they now carry a `StudioDrawerButton`.
- The sidebar build stamp was hand-reverted to `v1.1` while pubspec said 1.2.0.
  It now reads the real package version.
- Home, admin, path detail, unit, lesson and chat headers no longer hardcode
  English; the new dashboard strings reuse existing translated keys where one
  exists.
- `flutter analyze` failed on main over an unused import in
  `test/fetch_packages_tile_test.dart`, which blocked every release build.

---

## [Unreleased]

### Added
- Fat Android release APK that embeds chat + translation models; first launch streams them into app storage.
- `tools/build_release_with_models.ps1` and `publish_release.ps1 -WithModels` so GitHub Releases get one download link with everything.
- Optional CI `bundle_models` workflow input (uses a one-time `model-pack` release).

### Changed
- Updated Flutter web install metadata so hosted builds present AI Connect Africa branding instead of default project boilerplate.
- CI now installs the Android NDK/CMake versions required by `fllama` before building the release APK.
- CI normalizes `fllama`'s Android Kotlin language level so the release APK can compile with the package's declared Kotlin plugin.
- Added `fllama` as an isolated dependency alongside the existing `flutter_gemma` MediaPipe/LiteRT-LM integration.
- Android `minSdk` is now at least 23 for `fllama`; production Android keeps the existing Gemma path.
- Added production `INTERNET` permission for the explicit Llama test-model download flow.

### Notes
- The Llama path is additive and is not wired into the production tutor providers.
- `fllama` documents Android support for `arm64-v8a`, `armeabi-v7a`, and `x86_64`.

---

## [1.1.0] — 2026-06-12

### Added
- **Website Builder** — a new drag-and-drop page builder (`/website`).
  - Seven block types: header, text, image, button, list, quote, divider.
  - Drag from the palette onto a live WYSIWYG canvas; drop on a block to insert above it; reorder by dragging.
  - Per-block inspector for text, links, list items, and alignment.
  - **Ask OTIC** writes block content using the same on-device model.
  - Six theme colors; a "View HTML code" dialog so students see the real markup.
  - **Exports a standalone `.html` file** that opens in any browser, fully offline.
  - Websites persist per student and can be reopened and edited.
  - Implemented in [lib/features/website/](lib/features/website/); persistence via the new `website_projects` table (schema v4).
- Tests for the block model and HTML generator ([test/website_builder_test.dart](test/website_builder_test.dart)): JSON round-trips, HTML escaping, and link/color sanitization.

### Security
- Generated HTML escapes all student-entered text, strips `javascript:`/non-allowlisted link schemes, and validates theme colors — exported files cannot carry injected scripts.

### Changed
- Database `schemaVersion` 3 → 4 with an additive migration; existing student data is preserved.
- Version bumped to `1.1.0+2`; in-app footer now reads "Offline · v1.1".

---

## [1.0.0] — 2026-06-12

First production release. Both Android (APK) and Windows (zip) builds published.

### Added
- **On-device AI core** — Gemma 3 1B via LiteRT-LM (Android) and llama.cpp (desktop) behind a shared `InferenceEngine`, with a `MockEngine` fallback when no model is present.
- **Tutor pipeline** — every response advances Answer → Clarify → Practice → Apply → Create → Reflect.
- **Five learning modes** — Learn, Practice, Apply, Create, Teach.
- **Learning Paths** — AI-generated multi-unit curriculum per topic with lesson tracking.
- **Student memory** — local SQLite (Drift) profile storing compressed session summaries, never full logs.
- **Gamification** — points, badges, streaks, achievements.
- **Offline certificates** — locally generated PDF certificates.
- **Teacher dashboard** — per-student progress and session history.
- **Admin tools** — device info, model status, profile management.
- **LAN collaboration** — peer discovery on the local network, no server.
- **Emotional safety engine** — offline frustration/distress detection; crisis messages bypass the model.
- **Model setup** — in-app **Install from file…** flow with validation and a progress bar.
- **Offline update tooling** — [tools/make_update_package.ps1](tools/make_update_package.ps1) builds a USB/LAN update bundle.
- **Android release signing** — signed with the AI Connect Africa keystore; ProGuard rules for MediaPipe/LiteRT-LM.

### Changed
- Replaced `google_fonts` (which fetched fonts over the network) with bundled font files to guarantee identical offline rendering.
- Removed 9 unused dependencies.
- Android `compileSdk` set to 36 with a plugin override.

### Dropped from scope
- **Voice learning** (offline STT/TTS) — deliberately removed; the product jumps from text learning straight to later phases.

[1.1.0]: https://github.com/malinzijeremiah01-lab/Otic-Studio/releases/tag/v1.1.0
[1.0.0]: https://github.com/malinzijeremiah01-lab/Otic-Studio/releases/tag/v1.0.0
