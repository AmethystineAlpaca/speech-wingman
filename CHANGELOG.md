# Changelog

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
