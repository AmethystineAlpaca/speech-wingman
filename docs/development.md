# Development and checks

[README](../README.md) · [Build instructions](guide.md#getting-started) · [Contributing](../CONTRIBUTING.md) · [Validation](validation.md)

Run these commands from the repository root.

```bash
# Core logic and worker lifecycle checks (no model download required)
swift run WingmanCoreTests

# Programmatic English/Chinese UI state and rendering checks (desktop session required)
bash Scripts/check-ui-language.sh

# Exercise the production controller's grouping, FIFO, deferral and cancellation
bash Scripts/check-statement-scheduling.sh

# Check runtime source, native symbols, sandbox entitlements, and packaged signatures
bash Scripts/audit-offline.sh

# Generate fictional speech fixtures using already-installed macOS voices
python3 Scripts/generate-fixtures.py

# Replay synthetic audio at microphone speed with network access denied
python3 Scripts/evaluate-streaming.py --realtime
python3 Scripts/evaluate-streaming.py --realtime --cases Tests/Evaluation/heldout.json

# Evaluate current independent-rule behavior using the production Swift backend
swift run WingmanPolicyCheck build/native/bin/text-worker \
  Models/Qwen3-4B-Instruct-2507-Q4_K_M.gguf \
  Tests/Evaluation/cases.json Tests/Evaluation/multiple-rules.json Tests/Evaluation/sensitivity.json

# Run one continuous bilingual recording at all three sensitivities
bash Samples/UltimateTestCase/run.sh all

# Verify the actual bundled workers under an App Sandbox parent
bash Scripts/evaluate-bundle.sh
```

Build the app before model-based checks. Fixture generation needs installed English and Chinese macOS voices; it does not ship audio or download voices. Generated audio/results go to ignored `local-evaluation/`. The additional-case suite includes a known failure and can exit nonzero; voice versions can also change results. The UI checks use an isolated preferences domain and fictional content, not your microphone.

The offline evaluation CLI accepts an audio file and a UTF-8 policy file:

```bash
.build/release/wingman-evaluate \
  build/native/bin/text-worker build/native/bin/asr-worker Models \
  /path/to/recording.wav /path/to/policy.txt --realtime
```

It accepts up to five minutes of audio and evaluates the combined transcript after playback. Combined text exceeding 4,000 characters is rejected; the menu-bar app evaluates segments instead.

| Directory | Purpose |
| --- | --- |
| `Sources/WingmanApp` | SwiftUI/AppKit interface, microphone capture, session coordination |
| `Sources/WingmanCore` | Worker protocols, output validation, alert controls, display strings |
| `Native` | C++ ASR and text-inference workers |
| `Models` / `Resources` | Pinned manifests, licenses, app metadata, sandbox entitlements |
| `Scripts` | Reproducible setup, build, evaluation, and publication checks |
| `Tests` | Core checks, UI rendering harness, fictional evaluation definitions |
| `Samples/UltimateTestCase` | Continuous bilingual fixture, replay/calibration tools, frozen labels and complete iteration history |
