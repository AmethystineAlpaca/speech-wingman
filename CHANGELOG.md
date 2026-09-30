# Changelog

## 0.3.0 — Multiple rules and floating control (2026-09-30)

- Independent rules on separate lines, evaluated individually until the first match.
- Alert language follows current speech, including when rules or UI use another language.
- Current-segment evaluation with bounded pending work, cancellation of superseded rule checks, and no conversation history.
- Removed default alert cooldown and three-per-ten-minute cap; mute and event deduplication remain.
- Draggable floating desktop control with listening state, audio level, saved visibility/position, and start/stop capture.
- Added multiple-rule model regression checks and long-session queue/cancellation tests: 28/28 synthetic text cases and 14 core test groups pass.
- Refreshed English/Chinese documentation and rendered UI demos.
- Building while the app is running now stages the update without closing the current session.

Rule checks run independently and can take longer as the list grows. New speech supersedes older pending checks; cross-segment history is not used. Text fixtures and queue simulations are not a real-speaker accuracy benchmark or a multi-hour microphone endurance test.

## 0.2.1 — Public source preview

- Offline speech previews using Silero VAD and SenseVoiceSmall.
- Local Qwen3 4B evaluation of natural-language rules, including combined conditions.
- Automatic Chinese, English, and mixed speech recognition.
- English display language by default, with an immediate Chinese switch.
- Menu-bar session controls, floating reminders, mute, and explicit JSON export.
- Pinned model/runtime manifests, build instructions, privacy checks, and synthetic test tools.
- English demonstration screenshots and bilingual documentation.

### Preview limitations

This release distributes source and automatically generated source archives, not an installer or model weights. Building initially requires network downloads. Runtime inference is offline. The app is ad hoc signed, not notarized. Semantic evaluation uses finalized segments and can be delayed during continuous speech. Known recognition and rule-evaluation failures are documented in `docs/validation.md`.
