# Architecture

Speech Wingman is a native macOS menu-bar app. It runs two local helper processes and sends them data over standard input/output. No HTTP server or cloud inference is involved.

![On-device processing](assets/pipeline.svg)

## Audio and transcription

`AudioCapture` reads microphone audio through AVAudioEngine and converts it to 16 kHz mono floating-point PCM. `SpeechStream` sends bounded audio blocks to `asr-worker` over JSONL, with acknowledgments and a queue limit. Stopping or restarting invalidates callbacks from old worker generations.

The ASR worker combines Silero VAD and SenseVoiceSmall using the sherpa-onnx C API and ONNX Runtime. Speech previews are decoded roughly every second from a bounded current window. SenseVoice is not a native streaming recognizer: each preview re-recognizes that window. Approximately 650 ms of silence produces a final segment, and long windows are bounded around 12–15 seconds. Automatic language selection supports Chinese, English, and mixed speech; proper-name accuracy is not guaranteed.

## Semantic evaluation

`SessionController` displays previews immediately. `CurrentSpeechWindow` retains at most one pending final segment (up to 1,500 characters, at most 20 seconds old). New final text replaces waiting text, and a 180 ms debounce coalesces closely spaced updates. `LocalTextBackend` sends only this segment, the independent nonempty rule lines, sensitivity, and speech-derived alert language. Conversation history is never included, even if a caller supplies the legacy context argument. Each rule is evaluated in a separate request with its own exceptions; evaluation stops at the first alert. This avoids cross-rule interference, at the cost of latency as rule count grows. No further rule checks are launched once evaluation has taken 20 seconds; an unfinished list yields an inconclusive result. An already running request can finish later and has its own 20-second timeout. New finalized speech cancels remaining rules after the current request finishes; its result is discarded. Presentation independently enforces the 20-second freshness limit.

The text worker runs Qwen3-4B-Instruct-2507 Q4_K_M through a pinned llama.cpp revision with Metal acceleration. Output is constrained JSON containing a decision and, for alerts, a quote and a short suggestion. `ResultValidator` requires the quote to be a contiguous substring of trusted ASR text; the model cannot rewrite the transcript. Validation does not prove semantic correctness.

A newer final segment invalidates an older in-flight alert. Old segments are never reinserted or merged into new speech. A live preview does not block evaluation or presentation of the latest final segment, so continuous speech is evaluated at ASR window boundaries. Partial previews themselves are not classified. Slow inference can skip intermediate segments; cross-segment references and corrections are not resolved. Oversized segments are skipped whole rather than truncating away negations or exceptions.

## Presentation and state

An `AlertGate` applies per-event deduplication and mute state. Cooldown and rate limits remain configurable in the core, but are disabled by default so distinct rules are not silently suppressed. Deduplication history is bounded to ten minutes. An accepted alert appears in a floating AppKit panel and in the current session view.

The display-language preference is independent of recognition and model configuration. English is the default; Chinese can be selected immediately without restarting audio or rewriting the rule. User-authored content retains its original language. Suggestion and alert popup language follows current speech (Chinese/English, estimated dominant language for mixed speech); validation rejects a suggestion detected in the wrong language.

Pause, stop, rule updates, device changes, and failures invalidate active work. Session transcripts and alerts are memory-only unless explicitly exported. Preferences retain the rules, sensitivity, display language, floating-control visibility, and panel position. The nonactivating floating panel shares the same controller as the menu-bar view, appears across Spaces, and toggles capture without clearing the session. Transcript and alert lists retain at most 1,000 entries each. There is no speaker identification or system-audio capture.

## Packaging

The app and workers are App Sandbox signed without network entitlements. Setup scripts fetch pinned dependencies and models, verify hashes, and package them for offline runtime use. Downloaded weights, native libraries, dependency checkouts, and generated apps are intentionally not tracked in this source repository. Their upstream licenses must accompany any redistributed bundle.
