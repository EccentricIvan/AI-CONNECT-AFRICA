# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

AI Connect Africa is a **fully offline AI-powered Learning Operating System**. It runs entirely on-device — no internet, no cloud, no external APIs, ever. Two on-device models are bundled and run locally:

- **Chat/tutor — Qwen3-0.6B** → **Android**: LiteRT-LM (`.litertlm`, via `flutter_gemma`/`flutter_gemma_litertlm`) with NNAPI/GPU acceleration — see `lib/ai_core/inference/litert_lm_engine.dart`. **Windows/Linux**: the same Qwen3-0.6B as a GGUF running in-process via llama.cpp (`llm_llamacpp`), CPU-only — see `lib/ai_core/inference/llama_cpp_engine.dart`. Apache-2.0, no license click-through needed (`litert-community/Qwen3-0.6B` on Hugging Face).
- **Translation — TranslatePsy-AfriSLM (GGUF)** → translates English ↔ 19 Sub-Saharan African languages so students can learn in their own language while the tutor reasons in English. Runs in-process via llama.cpp (`llm_llamacpp`) on **every platform** (Android, Windows, Linux) — one engine, no Ollama server, no separate runtime install. See `lib/ai_core/translate/afrislm_model_manager.dart` and `lib/ai_core/inference/llama_cpp_engine.dart`.

Both models expose the same Dart inference interface from `lib/ai_core/inference/inference_engine.dart`. Chat and translation are both wired up and shipping. On Windows, llama.cpp's `ggml.dll` carries a load-time import on `ggml-vulkan.dll` → `vulkan-1.dll` even though inference runs CPU-only (`nGpuLayers: 0`); the build ships a bundled Vulkan loader (`tools/fetch_vulkan_loader.ps1`, `windows/CMakeLists.txt`) so machines without a Vulkan-capable display driver can still load llama.cpp at all.

Target platforms: Android (4 GB RAM / 32 GB storage minimum), Windows (8 GB RAM), Ubuntu (8 GB RAM).

## Core Constraint: Offline-First

Every feature must work with zero network connectivity. Before adding any dependency or API call, verify it works fully offline. This means:

- No calls to OpenAI, Anthropic, Google, or any hosted LLM API
- No Firebase, Supabase, or cloud sync
- SQLite or local file storage only (no cloud databases)
- Offline STT/TTS only (e.g., Vosk, Coqui, or platform-native offline engines)
- Certificate/badge PDF generation must work locally (e.g., jsPDF, PDFKit)
- Updates deploy via USB drive or local school server, not the internet

## Planned Architecture

When code exists, it will follow this structure:

```
ai-connect-africa/
  apps/
    desktop/          # Electron app (Windows + Ubuntu)
    android/          # React Native or Flutter app
  packages/
    ai-core/          # Local LLM inference wrapper — LiteRT-LM on Android, llama.cpp on desktop
    learning-engine/  # Learning paths, adaptive logic, mode routing
    memory-engine/    # Student profile, compressed summaries, local storage
    voice/            # Offline STT + TTS integration
    simulation/       # Domain simulations (science, math, business, etc.)
    gamification/     # Points, badges, streaks, achievements
    certification/    # Offline PDF certificate generation
    collaboration/    # Local network peer collaboration (no internet)
    safety/           # Emotional safety detection, prompt safety
  data/
    models/           # GGUF model files (gitignored, distributed separately)
    knowledge/        # Seed curriculum content
```

## AI Tutor Behavior Contract

Every AI response must follow this pipeline — do not short-circuit it:

```
Answer → Clarify → Practice → Apply → Create → Reflect
```

OTIC is a mentor, not a search engine. It must never stop at answering.

## Learning Modes

Four modes are routed through the same AI pipeline:

| Mode     | Purpose                        | Outcome            |
|----------|--------------------------------|--------------------|
| Learn    | Understand concepts            | Conceptual clarity |
| Practice | Exercises, challenges          | Retention          |
| Apply    | Real-world scenarios           | Practical competence |
| Create   | Build projects                 | Creation           |

A fifth "Teach back" mode (student explains → OTIC scores) was removed — it was
a bolt-on that bypassed the tutor pipeline entirely, calling the engine with its
own prompt. Don't confuse it with the Teacher *role*/dashboard, which stays.

## User Roles

`Guest` → `Student` → `Teacher` → `Admin`

- Guests: no saved state, no certificates, demonstration only
- Students: full learning features, memory, certificates
- Teachers: read student data, create groups/quizzes, cannot modify platform
- Admins: device/user/update management, no learning features

### Shared devices, classes and the teacher PIN

Devices are **shared**: learners take turns on one classroom PC/tablet.

- **Active learner** is the id saved in `SharedPreferences` (`active_student_id`),
  resolved by `resolveActiveStudent`. It falls back to the most recently
  active profile on installs that predate it. Every screen reads it through
  `activeStudentProvider`.
- **Switching** (`LearnerSwitcher.switchTo`, `/learners`) is a privacy
  boundary. It resets the chat thread, the tutor memory and the engine KV
  session. It also takes the new learner's language and re-locks the teacher
  area.
- **Adding a learner** uses `StudentNotifier.addLearner`, which always inserts
  and never switches. `createProfile` stays onboarding-only and keeps its
  "update instead of insert" guard.
- **Classes/streams** live in the `class_groups` table plus
  `students.class_group_id`. A learner is in at most one; a stream is a
  separate row, e.g. "S2 East". Progress rollups are computed on read from
  `topic_progress` and never stored. Subjects stay device-wide.
- **Teacher PIN** (`teacher_pin.dart`) gates `/teacher*` and `/admin*`. It
  stores only a salted hash, and with no PIN set nothing is gated. It keeps
  learners out; it is not real security.

### Teacher notes → tutor (offline knowledge base)

Uploaded files become plain text, which is split into sections and then into
~500-char rows in `topic_resources`. The original file is not kept.
`topic_resources_fts` is an external-content **FTS5** index: porter
tokenizer, BM25 ranking, kept in sync by triggers. It comes from the SQLite
that `sqlite3_flutter_libs` ships. It is created by raw SQL in
`OticDatabase._createResourceSearchIndex`, because drift has no FTS5 table
class, so `createAll` doesn't know about it.

`TutorPipeline` searches it on every turn using the matched curriculum
lesson's title and key terms plus the student's words. The notes share the
existing 700-char notes slot, because the question sits at the end of the
prompt and the engines clip from the end. Notes *supplement* the model; they
do not override it. There are no embeddings: a third model does not fit
4 GB Android.

## Student Memory Engine

Store compressed summaries only — never full conversation logs. Stored fields: age, interests, learning style, strengths, weaknesses, projects, achievements, certificates, progress, goals. Storage is local SQLite per device.

## Voice Learning

- Use offline STT/TTS only (no cloud speech APIs)
- Store converted text only — never store audio recordings

## AI Model Files

Model files are large and are never committed to git — always gitignored. Two distribution paths now exist:

1. **USB / local school server** (original, still supported) — the model file is transferred by hand and dropped into the platform's expected folder (see `ModelManager`/`AfriSlmModelManager`). No internet needed anywhere in this path.
2. **Bundled in the GitHub Release zip** (Windows, added for a plug-and-play download) — the release zip ships with a `models/` folder next to the executable, containing the Qwen chat GGUF (`qwen-0.6b-instruct.gguf` on Windows/Linux; `chat-model.litertlm` is the Android-only LiteRT name) and `afrislm-0.8b-q4_k_m.gguf`. Both model managers check this bundled path automatically (`<exe dir>/models/...`), so the app works immediately after extracting, no manual install step. The app itself still runs fully offline once downloaded — this only changes how the model bytes are *obtained*, not the offline runtime constraint.

Bundling a model into a public release requires its license to permit redistribution — verify before adding a new model here (Qwen3-0.6B is confirmed Apache-2.0).

| Role | Platform | Format | Model | Size |
|------|----------|--------|-------|------|
| Chat/tutor | Android | `.litertlm` (LiteRT-LM) | Qwen3-0.6B | ~330–590 MB |
| Chat/tutor | Windows / Linux | GGUF 4-bit (llama.cpp) | Qwen3-0.6B | ~330–590 MB |
| Translation | Android, Windows, Linux | GGUF 4-bit (llama.cpp) | AfriSLM 0.8B Q4 | ~0.5–1 GB |

The app must detect whether the model file is present at startup (checking the bundled path before falling back to the USB-installed path) and show a clear "Model not installed — transfer via USB" screen rather than failing silently when neither is found.

Translation needs no external server — `llm_llamacpp` loads the AfriSLM GGUF in-process on every platform, the same way the desktop chat brain loads Qwen. There is no separate runtime to install.

## Local History (Student Memory)

Use SQLite via the `drift` Flutter package. Store compressed summaries only — never full conversation logs. One database file per device, never synced.

Stored fields: `userId`, `age`, `interests`, `learningStyle`, `strengths`, `weaknesses`, `activeProjects`, `achievements`, `certificates`, `progressByTopic`, `goals`, `lastActive`.

### Chat recall (Recent chats)

Reopening a past chat is backed by **one small JSON file per session** in
`<app storage>/otic_sessions/`, indexed by the `chat_sessions` drift table
(`ChatSessionDao`). The split matters: the sidebar lists chats from the index
alone, so listing never opens a file, and a session body is read only when
that chat is actually reopened.

Each file (~2–8 KB, hard-capped) holds a **compressed recall, never a
transcript** — a clipped question/answer gist plus a `ConversationMemory`
snapshot, which is what lets a reopened chat resume at the right stage
instead of cold-starting. `SessionRecall` enforces the clipping, so the file
cannot grow into a conversation log however long the chat runs.

`SessionSummaries` is unchanged and still writes one row per assistant reply —
topic progress and the teacher dashboard are built on it. It is no longer what
the Recent chats sidebar reads.

Note: nothing in this app issues `PRAGMA foreign_keys = ON`, so the
`onDelete: cascade` declared on child tables is never enforced. Deleting a
student must clear dependent rows explicitly (see `ChatSessionDao.deleteForStudent`).

## Update Mechanism

Updates ship as packages deployable via USB flash drive or a local school LAN server. The app must support applying an update bundle without internet access.

## Development Commands

```powershell
# Get dependencies
flutter pub get

# Run on Windows desktop (primary dev target)
flutter run -d windows

# Run on Android device/emulator
flutter run -d android

# Build release
flutter build windows
flutter build apk

# Analyze code
flutter analyze

# Run tests
flutter test

# After adding a new package to pubspec.yaml
flutter pub get
```

Flutter SDK is installed at the path managed by winget (`Google.Flutter`).
After install, PATH must include the Flutter `bin` directory — open a new terminal if `flutter` is not found.

## What to Build First

Follow this order — do not jump ahead to gamification or certificates before the core tutor works:

1. Local LLM integration (Qwen3-0.6B loading + inference via LiteRT-LM)
2. Basic Learn mode (ask question → get mentor response)
3. Student memory (profile creation + summary storage)
4. Learning paths (auto-generate curriculum for a topic)
5. Practice + Apply modes
6. Voice learning
7. Simulation engine
8. Create mode
9. Gamification + Certification
10. Teacher dashboard
11. Admin dashboard
12. Collaboration (local network)
13. Emotional safety engine
14. Android app
15. Update deployment tooling
