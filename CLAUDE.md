# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

AI Connect Africa is a **fully offline AI-powered Learning Operating System**. It runs entirely on-device — no internet, no cloud, no external APIs, ever. Two on-device models are bundled and run locally.

**One runtime per platform, never mixed** (`lib/ai_core/model/model_runtime_policy.dart`):

- **Android → LiteRT-LM only.** Both models are `.litertlm` files.
  - Each role gets its own engine (`LiteRtLmEngineImpl`, built with
    `LiteRtLmEngine().createModel`, not flutter_gemma's single active slot).
  - Hardware order is NPU (Qualcomm QNN / MediaTek / Tensor) → GPU → LiteRT
    CPU. The backend that worked is remembered per role.
  - LiteRT-LM has **no NNAPI**; Google deprecated it in Android 15, and the
    vendor NPU dispatch replaces it.
  - llama.cpp's native libraries are excluded from the APK
    (`android/app/build.gradle.kts`).
  - On 4 GB phones the GPU often can't fit the model, so LiteRT lands on its
    CPU backend. Settings → AI engine shows the backend actually in use.
- **Windows / Linux → llama.cpp GGUF only.** LiteRT is never started.
- **A model file in the other platform's format is not "installed".**
  Every engine is built by `createBrainEngine` / `createTranslatorEngine`
  in `ai_provider.dart`.

- **Brain — Qwen2.5-Coder-1.5B-Instruct** (int4 `.litertlm` on Android, GGUF on desktop) → the one reasoning model. It does **all** reasoning and answer generation: tutoring, practice, learning paths, *and* code for the labs and builders (programming subjects just get the programming contract, `kProgrammingTutorContract`, on the same engine). See `lib/ai_core/model/model_manager.dart` and `dualModelRuntimeProvider` in `lib/ai_core/providers/ai_provider.dart`. Apache-2.0. **There is no Qwen3-0.6B any more** — it was removed on 2026-09-23 so one model does both jobs; don't reintroduce a separate chat or coder model.
- **Translation — TranslatePsy-AfriSLM** (int8 `.litertlm` on Android, converted by `.github/workflows/convert-afrislm-litertlm.yml` behind a round-trip quality gate — see `tools/litert/`; Q4 GGUF on desktop) → translates English ↔ 19 Sub-Saharan African languages so students can learn in their own language while the tutor reasons in English. In-process on both runtimes, no server. `/no_think` is sent to AfriSLM (a Qwen3.5 fine-tune) but not to the Qwen2.5 brain (`appendNoThink` on both engine classes). On Android every translation is a fresh conversation (`isolatedTurns`), never a pinned chat. See `lib/ai_core/translate/afrislm_model_manager.dart`.

Decoding is greedy everywhere (exact, repeatable code/JSON/translation)
**except the chat bubble**: `TutorPipeline.respond` and `QwenChatService`
run inside `runAsProse` (`decode_profile.dart`), which gives light seeded
sampling, a repeat penalty on llama.cpp, and `RepetitionGuard`, which cuts a
reply off before a repeated sentence is shown. Greedy decoding on the 1.5B
brain wrote the same paragraph until it ran out of tokens.

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
~500-char rows in `topic_resources`. The original file is not kept. That
split is for the tutor's search only. People see, share and delete **one
note per uploaded file** (`topic_resources.document_title`). Never list the
per-heading sections or chunks in the UI.
`topic_resources_fts` is an external-content **FTS5** index: porter
tokenizer, BM25 ranking, kept in sync by triggers. It comes from the SQLite
that `sqlite3_flutter_libs` ships. It is created by raw SQL in
`OticDatabase._createResourceSearchIndex`, because drift has no FTS5 table
class, so `createAll` doesn't know about it.

**PDFs, including scans.** `ResourceImportService` reads a PDF page by
page with PDFium (`pdfrx`, bundled at build time, never downloaded at
runtime; `lib/services/pdf/`). The hand-rolled `extractPdfText` is only
the fallback for files PDFium can't open.
- A page with real embedded text uses it. Any other page is rendered and
  read by on-device OCR (`lib/services/ocr/`):
  - Android: ML Kit, with the Latin model bundled in the APK.
  - Windows: built-in `Windows.Media.Ocr` through the `otic/ocr` channel
    (`windows/runner/ocr_channel.cpp`, on a worker thread).
  - Linux: the system `tesseract`, if it's installed.
- OCR text passes the same `looksLikeRealText` gate, so garbage is dropped.
  The teacher is told how many pages were scanned, marked or unreadable.
  Cancel stores nothing.
- **Diagrams:** the tutor can't see pictures. A caption line ("Figure 3.2
  …") or a picture region (ink that no text covers) becomes a marker
  paragraph, e.g. `[DIAGRAM: Figure 3.2 The heart | page 14 of the PDF
  "Biology Term 1"]`.
  - The marker travels in the chunk text, through FTS and class sync.
    `chunkContent` never splits one.
  - When a retrieved marker relates to the question, `TutorPipeline`
    appends "Diagram: see …, page 14 of the PDF … open the PDF on your phone
    or look in the printed copy".
  - That line is shown once per topic, is added after `_remember` so it
    never enters memory, and is added before translation.
  - Page numbers are PDF page numbers, so the caption comes first. The
    original PDF is still not kept or synced.

`TutorPipeline` searches it on every turn using the matched curriculum
lesson's title and key terms plus the student's words. The notes share the
existing 700-char notes slot, because the question sits at the end of the
prompt and the engines clip from the end. Notes *supplement* the model; they
do not override it. There are no embeddings: a third model does not fit
4 GB Android.

### Class sync (teacher ↔ students ↔ classmates over the local Wi-Fi)

Notes are shared only within one **school + class/stream + subject**.
The code is in `lib/collaboration/sync/` (one server, `ClassShareServer`,
with a teacher role and a classmate role), with tests in
`test/class_sync_e2e_test.dart` and `test/class_crypto_test.dart`. Don't
loosen any of these rules:

- **The sharer approves every join.** After a correct code, the joining
  device waits (2 min) while the teacher — or the sharing student — sees
  its learner's name and taps Accept/Decline (`JoinRequestsCard`). Decline
  or no answer hands over nothing.

- **School.** It's set in Admin → School on the teacher's device. A student
  device adopts it at its first join and refuses classes from any other
  school.
- **Joining.** The teacher's Class sync screen (Teacher → Class sync,
  PIN-gated) shows a join code (30 min, locked after 20 wrong tries). The
  student types it on **Class sync** in the main menu (`/class-sync`,
  `ClassSyncScreen`), deliberately outside `/teacher*` so no PIN is needed.
  Either side can be any Android phone or Windows/Linux PC.
  - The teacher's device is found by UDP broadcast + mDNS. Phone hotspots
    often block both, so the teacher screen also shows its IP address and
    the student screen accepts it typed in (`sync_address.dart`).
  - The code never crosses the network. A PBKDF2-stretched proof does. One
    random code per sharing session (`Random.secure`), 30 minutes.
  - The reply gives the device the class key and pins the teacher device's
    Ed25519 public key. The class is created locally with the teacher's
    `groupUuid`.
- **Serving.** `ClassSyncDao.sharedChunks` is the only rule. A chunk is
  served only if it was written on this device (`class_group_uuid IS NULL`)
  *and* has a `resource_shares` row for that class.
  - Notes are never shared until the teacher ticks a class (Lesson
    materials → Share with classes).
  - Received notes are never served *as this device's own* (teacher role).
- **Teacher-signed manifests.** Every channel (class+subject) carries the
  teacher's Ed25519 signature over school, class, subject, digest and a
  **version that only goes up** (`served_channels`, bumped on every digest
  change including an unshare). Receivers keep it in `sync_state`.
- **Classmates pass notes on — verbatim only.** A student device that
  joined through the teacher can share that class's received notes
  (Class sync → Share with classmates, own code + Accept). Rules:
  - Only to devices that **already joined the class through the teacher**
    (`joinClassmate` refuses otherwise). A classmate can't admit anyone.
  - A relayed subject is taken only if its manifest verifies against the
    **pinned teacher key**, its chunks hash to the signed digest, and its
    version is **strictly newer** than this device's (including a
    tombstone left when the teacher unshared it). A classmate can't edit,
    invent or remove anything, and can't roll back a subject this device
    already synced. Known gap: a device that hasn't synced with the teacher
    since an unshare has no tombstone yet, so it still accepts that subject
    from a classmate until its next teacher sync.
  - A classmate sync never deletes; only a teacher sync drops subjects.
  - Pulling from a classmate needs the session token they handed over at
    Accept (requests are MAC'd with it), not just the class key.
- **Every request** is MAC'd (class key; classmate role: session token) and
  names the school. Anything wrong gets the same bare 404.
- **Every reply** is AES-GCM encrypted with the class key and bound to the
  requester's nonce. Teacher replies are also signed with the teacher key,
  so a classmate can't pose as the teacher and old replies can't be
  replayed.
- **Receiving.** Each subject is replaced whole, in one transaction, and
  only if every chunk verifies. Edits and removals from the teacher
  propagate; removed subjects leave a tombstone row.
- **Progress back to the teacher.** On every sync *with the teacher*, the
  student device sends an encrypted report per learner of that class on
  the device (`progress_report.dart`): totals, per-topic mastery,
  strengths/weaknesses — never chats. The teacher stores the latest per
  learner in `member_reports` and shows it in Teacher → Class sync →
  Class progress. Deleting the class clears it.
- **Shared devices.** Tutor retrieval sees this device's own notes plus
  received notes for the **active learner's** class only
  (`TopicResourceDao._visibleTo`).
- **Protocol v3 only.** Devices on older builds can't sync with upgraded
  ones.

## Student Memory Engine

Store compressed summaries only — never full conversation logs. Stored fields: age, interests, learning style, strengths, weaknesses, projects, achievements, certificates, progress, goals. Storage is local SQLite per device.

## Voice Learning

- Use offline STT/TTS only (no cloud speech APIs)
- Store converted text only — never store audio recordings

## AI Model Files

Model files are large and are never committed to git — always gitignored. Two distribution paths now exist:

1. **USB / local school server** (original, still supported) — the model file is transferred by hand and dropped into the platform's expected folder (see `ModelManager`/`AfriSlmModelManager`). No internet needed anywhere in this path.
2. **Bundled in the GitHub Release zip** (Windows, added for a plug-and-play download) — the release zip ships with a `models/` folder next to the executable, containing the brain (`qwen2.5-coder-1.5b-instruct.gguf`) and `afrislm-0.8b-q4_k_m.gguf`. Both model managers check this bundled path automatically (`<exe dir>/models/...`), so the app works immediately after extracting, no manual install step. The app itself still runs fully offline once downloaded — this only changes how the model bytes are *obtained*, not the offline runtime constraint.

Bundling a model into a public release requires its license to permit redistribution — verify before adding a new model here (Qwen2.5-Coder-1.5B is confirmed Apache-2.0).

| Role | Platform | Format | Model | Size |
|------|----------|--------|-------|------|
| Brain (tutor + code) | Android | `.litertlm` int4 (LiteRT-LM) | Qwen2.5-Coder-1.5B-Instruct | ~1.1 GB |
| Translation | Android | `.litertlm` int8 (LiteRT-LM) | AfriSLM 0.8B (converted) | ~0.9 GB |
| Brain (tutor + code) | Windows, Linux | GGUF 4-bit (llama.cpp) | Qwen2.5-Coder-1.5B-Instruct | ~1.1 GB |
| Translation | Windows, Linux | GGUF 4-bit (llama.cpp) | AfriSLM 0.8B Q4 | ~0.6 GB |

The app must detect whether the model file is present at startup (checking the bundled path before falling back to the USB-installed path) and show a clear "Model not installed — transfer via USB" screen rather than failing silently when neither is found.

Translation needs no external server. On desktop `llm_llamacpp` loads the AfriSLM GGUF in-process; on Android LiteRT-LM loads its `.litertlm`. There is no separate runtime to install.

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
student must clear dependent rows explicitly — `LearnerDataWiper`
(`lib/services/learner_data_wiper.dart`) is the one place that does this for
every table actually scoped to a student; route both the Admin per-learner
delete and the Admin "Reset all student data" action through it rather than
deleting a student row directly. Its `wipedTableNames` set is checked against
the database's own table list in `test/learner_data_wiper_test.dart`, so a
newly added student-scoped table fails that test until it's classified as
wiped or kept (kept = shared resources: `topic_resources`, `custom_subjects`,
`class_groups`, the translation cache, `sync_state`).

## Create → Projects (full-stack project folders)

Every creation is a **real folder**, and the disk is the source of truth. There
is no index table. `ProjectStore` (`lib/services/projects/project_store.dart`)
writes `<root>/<learner>-<id>/<Websites|Applications|Python|Guided>/<slug>/`,
each folder with an `otic-project.json` manifest. `root` depends on the
platform:

- **Windows / Linux:** `Documents/OTIC/Projects`, which opens in Explorer or
  VS Code.
- **Android:** `<app docs>/projects`, which is private, so Projects exports
  zips or shares them instead.

Folders cut, deleted or pasted in Explorer show up on the next list.

- **Describe first, pick from a list second.** The App and Website chat
  builders open on a free-text prompt ("describe the app you want").
  - The coder model writes the **page** from that description
    (`generateAppHtml` / `generateSiteHtml` in `ai_coder_service.dart`).
    If it's missing, refuses or fails, the build falls back to the template
    for the classified type — never a blank screen.
  - The description is also classified **locally, with no model call**
    (`classifyAppType` / `classifySiteTemplate`, scored keywords). That picks
    the app type whose backend resources and fallback template the build
    uses. Attached pictures go into a gallery afterwards; the model never
    sees them.
  - The ☰ list picker runs the original guided questions and pure template
    build, with no model call.
- **The project scaffold is never model-written.** The code lives in
  `lib/features/projects/scaffold/`.
  - It turns the builder's page into `frontend/` (split CSS/JS, embedded
    pictures extracted to `frontend/images/`).
  - It adds a FastAPI + SQLAlchemy + SQLite `backend/` with CRUD routes per
    app type (`resource_spec.dart`), plus a pytest suite. The backend schema
    always comes from that fixed table — the model never invents resources
    or fields.
  - It adds README / DEPLOY.md (free hosts), a Dockerfile, `render.yaml`
    and `.vscode/`.
  - After changing any scaffold, run `tools/verify_scaffolds.ps1`: it
    installs and runs every generated backend's tests.
- **One save path.** Every builder saves through `saveCreation`
  (`project_providers.dart`), which awards badges and refreshes
  `studentProjectFoldersProvider`. Achievements counts from that provider.
- **Legacy rows are synced into folders.** Older DB-row saves are
  `app_builder_projects`, the removed Block canvas's `website_projects`
  and the guided chat's `student_projects`. `LegacyProjectSync` gives each one a
  folder once, and a ledger stops deleted ones from coming back.
- **Style and pictures need no model.** Style requests ("make the text
  red") are applied through `quick_style_edit.dart` in a
  `<style id="otic-style">` block. Pictures are embedded as data URIs while
  editing (`html_images.dart`) and become real files on save.
- **A picture in the Tell-AI bar** comes with what to do with it. The model
  can't see images, so none of this sends the picture to the model:
  - "make the UI like this" → `ui_look.dart` measures the screenshot's
    pixels (theme, colours, bar, card colour, corner radius, columns) and
    restyles the page in one `<style id="otic-look">` block. It never
    copies layout or fonts.
  - "make it the logo / the background / put it in the about section /
    make it round" → `image_instruction.dart` places and styles it.
  - Only styling those can't express goes to the coder, as a CSS patch
    aimed at the placed picture (`image_instruction_runner.dart`).
- **Deleting a learner.** `LearnerDataWiper` also deletes the learner's
  project folder.

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

1. Local LLM integration (brain loading + inference via llama.cpp)
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
