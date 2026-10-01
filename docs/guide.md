# Build and use Speech Wingman

[README](../README.md) · [中文介绍](README.zh-CN.md) · [Rule examples and screenshots](examples.md)

[Requirements](#requirements) · [Build](#getting-started) · [Update](#updating-an-existing-build) · [Rules](#multiple-independent-rules) · [Privacy](#privacy) · [Limitations](#limitations)

## Requirements

| Item | Requirement / guidance |
| --- | --- |
| Platform | Apple Silicon Mac; Intel Macs, Windows, and Linux are not supported by this build |
| macOS | Deployment target: macOS 14 or later; current local verification was on macOS 27 |
| Memory | 16 GB unified memory recommended; lower-memory machines have not been validated |
| Storage | Models are about 2.74 GB; the generated app is about 2.78 GB. Allow at least 10 GB free for downloads, dependencies, build outputs, and the app |
| Developer tools | Swift 6+, Apple Command Line Tools or Xcode, Git, Python 3.9+, and an ARM64-compatible CMake |
| Microphone | An available microphone and macOS microphone permission |
| Network | Needed for the initial source/dependency/model downloads; normal app operation is offline |

The test machine was an Apple M4 Mac with 16 GB memory. This is a tested configuration, not a promise of the same latency on every Apple Silicon Mac. The Python scripts are build/evaluation tools; Python is not needed to run the completed app.

## Getting started

This repository distributes **source code and pinned dependency/model manifests**, not model weights or a notarized installer.

### 1. Prepare the toolchain

Install Apple's Command Line Tools if needed:

```bash
xcode-select --install
```

Verify that `swift --version` reports Swift 6 or later. Use an ARM64 Python 3 with `pip` available; replace `python3` below with its path if necessary.

```bash
git clone https://github.com/AmethystineAlpaca/speech-wingman.git
cd speech-wingman

# Download pinned build tools and ASR libraries; build the native workers.
WINGMAN_PYTHON="$(command -v python3)" bash Scripts/bootstrap-dev.sh

# Download and SHA-256-verify the model resources.
python3 Scripts/setup-model.py

# Build the Swift app, package models/libraries, and sign the local bundle.
bash Scripts/build-app.sh
open 'build/Speech Wingman.app'
```

`bootstrap-dev.sh` installs a pinned CMake into the project-local `.tools/` directory. Alternatively, set `WINGMAN_CMAKE` to an existing compatible CMake executable, run `python3 Scripts/setup-asr-runtime.py`, and then build. The native build pins its llama.cpp revision.

If Speech Wingman is not running, the build script replaces the generated app at `build/Speech Wingman.app`. If it is running, the new bundle is staged at `build/Speech Wingman.next.app` and the current session stays open. The app is locally ad hoc signed and **not Developer ID notarized**.

### Updating an existing build

```bash
git pull --ff-only
bash Scripts/build-app.sh
```

If the script reports a staged update, export any session you want to keep, quit the running app, and run `bash Scripts/build-app.sh` once more to replace the main bundle. Then open `build/Speech Wingman.app`. The new build keeps saved rules and interface preferences; microphone capture starts only when you click. Existing multiline rules now treat each nonempty line as an independent rule, so keep a rule’s exceptions on the same line. Checks use only the current statement assembled from nearby finalized segments; rules that rely on earlier conversation need to be rewritten.


### 2. Set your rule

1. Click the microphone icon in the macOS menu bar.
2. Open **Settings** and enter one rule per line, keeping each rule’s exceptions on that same line. Rules may be written in Chinese or English.
3. Choose **Low**, **Medium**, or **High** sensitivity, then **Save and apply**.
4. Click the floating microphone button or select **Start listening**, and grant microphone permission when macOS asks.
5. Speak normally. No speech-language selector is required.

Example rule to experiment with:

> Alert when I make a firm commitment without a clear deadline or delivery scope. Stay quiet for conditional statements and commitments that already specify both.

The built-in rule retains its original Chinese text. The display-language switch translates interface controls, not user-authored rules, transcripts, or model-generated suggestions. Translating a rule can change model behavior, so test your own wording.

### 3. Control the session

- **Floating microphone / stop button:** start or stop capture without clearing the session. Drag the title or transcript to reposition it.
- **Pause / Resume:** stop collection and restart local processing when ready.
- **Stop and clear:** stop listening and clear this session's transcript and alerts.
- **Mute for one hour:** suppress reminders while transcription continues.
- **Export session:** save the current transcript and alerts as JSON to a location you choose.
- **Save and apply:** applying a rule while listening cancels old work and starts a new audio segment.

All voices picked up by the microphone can affect the result. The app does not identify speakers or separate your voice from other people in the room.

## Multiple independent rules

Write one rule per line, including that rule’s exceptions on the same line:

```text
Alert when I say banana.
Alert if I speak badly of Tom; stay quiet when I praise him.
Alert if I reveal a numeric password.
```

Any matching line can trigger an alert; the conditions do not all need to match. Rules are checked independently; the first match produces one concise reminder per speech segment. More rules can increase latency. Rules share the sensitivity and mute controls, with a total limit of 4,000 characters. Suggestions and popup labels follow the current speech language, independently of the rule and interface languages. Mixed speech uses an estimated dominant language.

Sensitivity selects a local inference strategy: **Low** aims to minimize interruptions, **Medium** balances coverage, and **High** prioritizes recall. The runtime mapping is calibrated separately for the routed and independent rule paths, as described in the [sensitivity calibration notes](validation.md#ultimate-test-case-2026-09-30). Explicit rule exceptions still apply. These are measured strategy choices, not calibrated confidence thresholds: High can still miss matches and increase false alerts. Sensitivity does not change speech recognition. Click **Save and apply** after changing a rule or sensitivity.

The floating desktop button starts listening with one click and stops capture with the next. A compact transcript below the button shows recent speech and the live preview, automatically following the latest line. It stays a fixed height as you speak, keeps finalized text when paused, and collapses after the session is cleared. Stopping with this button keeps the session for resuming. Drag its title or transcript to move it; hide or restore it using **Floating desktop button** in the menu-bar panel or settings. **Stop and clear** still erases the session.

## Features

- **Local inference:** Silero VAD, SenseVoiceSmall ASR, and a quantized Qwen3 4B text model run on the Mac. No runtime API key, account, model download, or cloud fallback.
- **Automatic bilingual speech recognition:** Chinese, English, and mixed speech use the same recognizer. Switching the interface language does not change recognition.
- **A live transcript:** the current preview is replaced as recognition improves; finalized segments enter the session history.
- **Current-speech alerts:** evaluate a bounded current statement, with one explicitly deferred predecessor when applicable. Candidate rules are checked independently; no unbounded conversation history is included. Alert quotes must occur verbatim in the ASR text; malformed model output is rejected.
- **Floating desktop control:** start or stop capture while preserving the session, with recent speech and the live preview in a fixed-height, auto-scrolling transcript. Drag to move; hide or restore it in settings.
- **A quiet menu-bar app:** start manually, pause/resume, dismiss an alert, mute for an hour, or stop and clear the session.
- **English and Chinese UI:** select **Settings → Display language → English / 中文**. The change is immediate and saved across launches.
- **Explicit export and diagnostics:** save transcript, reminders, configurations and evaluation records to JSON only when you choose to. Audio is not recorded to a file by the app.

## How it works

1. **Audio capture:** AVAudioEngine provides microphone audio, converted to 16 kHz mono.
2. **Voice activity detection:** Silero VAD identifies speech and silence.
3. **Transcription:** SenseVoiceSmall runs through sherpa-onnx/ONNX Runtime on CPU. The active short window is re-decoded roughly once a second; this is incremental previewing around a non-streaming ASR model.
4. **Semantic evaluation:** the assembled current statement, independent rules, and the requested alert language are sent to Qwen3-4B-Instruct-2507 (Q4_K_M), using llama.cpp with Metal acceleration.
5. **Validation and alert controls:** a constrained JSON response is validated; matching evidence may produce a floating reminder, subject to mute, event deduplication, and freshness checks.

There is no runtime HTTP service or cloud fallback. Source, model revisions, sizes, and SHA-256 hashes are recorded in `Models/manifest-*.json` and `Resources/asr-runtime.json`.

[Architecture details](../docs/architecture.md) · [Validation and known failures](../docs/validation.md)

## Privacy

- Microphone audio and the live session stay in local process memory during normal operation; the app does not write audio files or automatically save session transcripts.
- Alert rules, sensitivity, display language, floating-control visibility, and panel position are stored locally in macOS preferences.
- A session export writes potentially sensitive transcript content to your chosen location. Share it deliberately.
- The app and its packaged helper processes use App Sandbox without client/server network entitlements. Dependency/model downloads happen in separate developer setup scripts.
- This source repository excludes private recordings, session exports, raw local logs, user preferences, downloaded models, native binaries, and machine-specific development notes. The explicitly fictional Ultimate Test Case and its reviewed evaluation results are published for reproducibility.

These statements describe the app's behavior. They do not claim to control macOS services, backups, diagnostics, or memory management.

## Limitations

- **Near-real-time previews, segment-based judgments.** Silence of roughly 650 ms normally finalizes a segment. Long speech is bounded into approximately 12–15 second windows; nearby final segments are grouped with a 1.5-second settling interval, extended while a continuing ASR preview is active (up to a 12-second grouping window). This is not continuous word-by-word semantic detection.
- **Recognition and reasoning can be wrong.** Product names, accents, overlapping voices, negation, rule translations, and complex exceptions are imperfect. A mixed-language “alert on any English word” example is a known semantic miss.
- **Alerts stay current:** new speech no longer cancels an in-flight judgment. Up to four statements wait in order; overflow drops the oldest waiting statement and results older than 30 seconds are skipped. The longer freshness window allows multi-stage checks but can permit later reminders. There is no default cooldown or three-alert cap. Manual mute and event deduplication still apply. Overload can still skip statements, and exported evaluation records identify skips.
- **Session limits:** the UI retains up to 1,000 finalized segments and 1,000 alerts; exports retain up to 1,000 statement evaluation records plus configuration snapshots. Up to four statements wait for evaluation. Statements over 1,500 characters are skipped whole rather than truncated. Pause-based grouping cannot reliably join explanations across long pauses or forced window boundaries.
- **Limited evaluation coverage:** 18 core groups pass and the expanded model regression suite scores 63/73. The latest six-case mapping smoke test scores 5/6. Continuous synthetic replay is separate from those text checks. A 10,000-segment queue simulation is not a multi-hour microphone test, and historical 8/8 and 5/6 audio results are not current general accuracy claims.
