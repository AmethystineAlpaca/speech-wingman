# Changelog

## 0.4.0 — Continuous speech, live transcript UI and calibrated sensitivity (2026-09-30)

- Show recent and live speech in the floating control, follow revised/final text, retain text when paused, and collapse after clearing. Add a settings shortcut and native dragging from the title or transcript.
- Redesign settings with a larger fixed-height editor, character count, expandable examples, sensitivity cards, scrollable content, a pinned save footer, save feedback and Command-S. Cover small windows and bilingual light/dark layouts.
- Publish the complete Ultimate Test Case history and measured latency tradeoffs. Before remapping, complete-run correct windows improved from 35/35/31 to 38/36/36 out of 44 during development; these are synthetic development results, not general accuracy claims.
- Verify 18 core groups and retain the independent model regression result of 63/73, plus a 5/6 mapping smoke test and known failures. Extend grammar bounds for suggestions and distinguish invalid generated output from worker failure.

- Calibrate the actual sensitivity mapping by inference path: for eight or more rules, High uses the previous Medium profile and Medium uses the previous High profile; small-rule configurations keep their measured ordering. Record the mapping version in exports and evaluation runs.
- Withdraw the added quote-only veto from small-rule configurations after independent regressions showed additional missed alerts.

- Join adjacent speech fragments before judging, allowing short continuations and corrections to finish.
- Let in-flight judgments finish while keeping a bounded FIFO of four waiting statements; retain freshness and session-cancellation checks.
- Export configuration snapshots, actual statement inputs, source segment IDs, evaluation status, and alert disposition.
- Add production-controller scheduling checks. Long pauses and grouping bounds can still separate a continuation from the preceding statement.
- Add a standalone bilingual Ultimate Test Case: 12 rules, one continuous 11-minute recording, all three sensitivities, immutable run artifacts, and a Markdown history retaining failed iterations.
- Route large rule sets before independent checks, separate rule configuration from speech, constrain intermediate output, and retry malformed model output within a fixed bound.
- Allow one explicitly deferred input to continue into the next evaluated window; export the actual inference input and matched rule identity. Extend freshness to 30 seconds for the multi-stage checks.

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
