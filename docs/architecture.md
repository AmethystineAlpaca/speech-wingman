# Architecture

Speech Wingman is a native macOS menu-bar app. It runs two local helper processes and sends them data over standard input/output. No HTTP server or cloud inference is involved.

![On-device processing](assets/pipeline.svg)

## Audio and transcription

`AudioCapture` reads microphone audio through AVAudioEngine and converts it to 16 kHz mono floating-point PCM. `SpeechStream` sends bounded audio blocks to `asr-worker` over JSONL, with acknowledgments and a queue limit. Stopping or restarting invalidates callbacks from old worker generations.

The ASR worker combines Silero VAD and SenseVoiceSmall using the sherpa-onnx C API and ONNX Runtime. Speech previews are decoded roughly every second from a bounded current window. SenseVoice is not a native streaming recognizer: each preview re-recognizes that window. Approximately 650 ms of silence produces a final segment, and long windows are bounded around 12–15 seconds. Automatic language selection supports Chinese, English, and mixed speech; proper-name accuracy is not guaranteed.

## Semantic evaluation

`SessionController` displays previews immediately. Final segments are queued and debounced before `LocalTextBackend` sends their text, recent context, rule, and sensitivity to `text-worker`.

The text worker runs Qwen3-4B-Instruct-2507 Q4_K_M through a pinned llama.cpp revision with Metal acceleration. Output is constrained JSON containing a decision and, for alerts, a quote and a short suggestion. `ResultValidator` requires the quote to be a contiguous substring of trusted ASR text; the model cannot rewrite the transcript. Validation does not prove semantic correctness.

Continued speech can make an in-flight alert stale. The controller may re-evaluate it after later text finalizes. This trades earlier alerts for more context and means uninterrupted speech can delay reminders. The current implementation does not perform continuous semantic classification of every partial preview.

## Presentation and state

An `AlertGate` applies per-event deduplication, mute state, a 30-second cooldown, and a maximum of three reminders per ten minutes. An accepted alert appears in a floating AppKit panel and in the current session view.

The display-language preference is independent of recognition and model configuration. English is the default; Chinese can be selected immediately without restarting audio or rewriting the rule. User-authored content and model suggestions retain their original language.

Pause, stop, rule updates, device changes, and failures invalidate active work. Session transcripts and alerts are memory-only unless explicitly exported. Preferences retain the rule, sensitivity, and display language. There is no speaker identification or system-audio capture.

## Packaging

The app and workers are App Sandbox signed without network entitlements. Setup scripts fetch pinned dependencies and models, verify hashes, and package them for offline runtime use. Downloaded weights, native libraries, dependency checkouts, and generated apps are intentionally not tracked in this source repository. Their upstream licenses must accompany any redistributed bundle.
