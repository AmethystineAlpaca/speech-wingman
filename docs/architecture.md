# Architecture

Speech Wingman is a native macOS menu-bar app. It runs two local helper processes and sends them data over standard input/output. No HTTP server or cloud inference is involved.

![On-device processing](assets/pipeline.svg)

## Audio and transcription

`AudioCapture` reads microphone audio through AVAudioEngine and converts it to 16 kHz mono floating-point PCM. `SpeechStream` sends bounded audio blocks to `asr-worker` over JSONL, with acknowledgments and a queue limit. Stopping or restarting invalidates callbacks from old worker generations.

The ASR worker combines Silero VAD and SenseVoiceSmall using the sherpa-onnx C API and ONNX Runtime. Speech previews are decoded roughly every second from a bounded current window. SenseVoice is not a native streaming recognizer: each preview re-recognizes that window. Approximately 650 ms of silence produces a final segment, and long windows are bounded around 12–15 seconds. Automatic language selection supports Chinese, English, and mixed speech; proper-name accuracy is not guaranteed.

## Semantic evaluation

Sensitivity labels select measured inference profiles. With eight or more rules, `SessionConfiguration.evaluationSensitivity` maps UI Low/Medium/High to the original Low/High/Medium profiles. The independent path below eight rules retains Low/Medium/High because its measured recall ranking differs. The original profile prompt strings remain byte-for-byte intact; UI values and saved preferences are not renamed. Session exports and the Ultimate harness record mapping version `routed-recall-v1`. See the evaluation report for comparisons using the same positive set across all profiles; percentages with different positive denominators are not used to rank recall. This calibration is evidence from the current fixtures, not a guarantee on arbitrary rules.

Quoted-evidence vetoes apply only to the routed path. The extra veto was withdrawn from the independent path after it introduced three additional misses in the short-text regression suite; its existing full-context review and strict output validation remain.

`SessionController` displays raw ASR segments immediately. `SpeechStatementBuffer` collects adjacent finalized segments into one current statement. A 1.5-second settling interval allows a continuation or explanation to arrive; an active ASR preview holds the buffer open, bounded to 12 seconds. Configuration changes and the 1,500-character bound also close a group. This is a pause-based heuristic, not a semantic sentence detector: long pauses, forced window limits, and delayed ASR can still separate a statement from its explanation.

`CurrentSpeechWindow` keeps at most four waiting statements in FIFO order. A new statement does not cancel an in-flight evaluation. Overflow drops the oldest waiting statement, and statements older than 30 seconds are skipped. No text is truncated. General session history is not sent to the model. Only an explicit model `defer` can carry one original statement into the next evaluated statement, with the same configuration, a maximum 24-second gap, and the existing 1,500-character limit; accumulated context is never carried recursively. Pause and configuration changes clear this state.

Each nonempty rule line retains its own exclusions. Configurations with eight or more rules first route speech to potentially relevant rule indices in batches of at most twelve, then verify each candidate independently. The rule configuration is separated from the speech data. A malformed routing result falls back to checking the batch, while a wrongly omitted candidate remains a possible model miss. A short quoted-evidence check can veto an apparent match; it cannot create an alert without the validated full-context result. One invalid generated candidate can be regenerated once in the routed path. Processing stops at the first validated alert, and no new checks launch after the 30-second budget. An unfinished list yields `inconclusive`. Individual requests retain a 20-second timeout. Invalid model output is distinct from a worker failure, and presentation checks freshness independently.

The text worker runs Qwen3-4B-Instruct-2507 Q4_K_M through a pinned llama.cpp revision with Metal acceleration. Output is constrained JSON containing a decision and, for alerts, a quote and a short suggestion. `ResultValidator` requires the quote to be a contiguous substring of trusted ASR text; the model cannot rewrite the transcript. Validation does not prove semantic correctness.

The prompt applies user-authored rules without topic-specific branches or keyword extraction. Assembled speech is marked as adjacent fragments so the model can consider continuations and corrections together. Decisions still come from the local model.

Exports include configuration snapshots and statement evaluation records linking input to raw segment IDs. Optional `inputText`, `continuedFromID`, and `matchedRuleIndex` record the actual inference input, any explicit deferral predecessor, and the zero-based matched rule. `evaluationStatus` distinguishes pending, evaluating, evaluated, cancelled, expired, overflow, and invalid work; a pending entry's legacy `defer` value is not a model decision. Records distinguish presented alerts from muted/limited or expired alerts and retain evaluation timing plus worker/validation errors. Old exports without the optional fields remain decodable. Transcript, alert, and statement-record collections are each bounded to 1,000 entries.

## Presentation and state

An `AlertGate` applies per-event deduplication and mute state. Cooldown and rate limits remain configurable in the core, but are disabled by default so distinct rules are not silently suppressed. Deduplication history is bounded to ten minutes. An accepted alert appears in a floating AppKit panel and in the current session view.

The display-language preference is independent of recognition and model configuration. English is the default; Chinese can be selected immediately without restarting audio or rewriting the rule. User-authored content retains its original language. Suggestion and alert popup language follows current speech (Chinese/English, estimated dominant language for mixed speech); validation rejects a suggestion detected in the wrong language.

Pause, stop, rule updates, device changes, and failures invalidate active work. Session transcripts and alerts are memory-only unless explicitly exported. Preferences retain the rules, sensitivity, display language, floating-control visibility, and panel position. The nonactivating floating panel shares the same controller as the menu-bar view, appears across Spaces, and toggles capture without clearing the session. Transcript and alert lists retain at most 1,000 entries each. There is no speaker identification or system-audio capture.

## Packaging

The app and workers are App Sandbox signed without network entitlements. Setup scripts fetch pinned dependencies and models, verify hashes, and package them for offline runtime use. Downloaded weights, native libraries, dependency checkouts, and generated apps are intentionally not tracked in this source repository. Their upstream licenses must accompany any redistributed bundle.
