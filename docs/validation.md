# Validation and known failures

## Scope

Development checks were run locally on an Apple M4 Mac with 16 GB unified memory, macOS 27, and Swift 6.4. The deployment target is macOS 14, but older macOS versions have not been comprehensively tested.

The repository contains only fictional case definitions and reproducible test tools. Local audio, logs, model outputs, machine-specific reports, and saved application preferences are excluded from version control.

## Checks completed before the initial source publication

- Eleven core test groups cover JSON validation, trusted ASR transcripts, policy boundaries, alert deduplication/cooldown/mute, resource paths, worker shutdown/reload, ASR partial/final events, and display-language defaults/persistence.
- The UI harness compiles the production views/controller/presenter with a separate test entry point and isolated preferences. It checks language restoration, preservation of session content/state, and updating an existing alert panel without showing a new one. English and Chinese layouts were inspected. README images use separate fictional English-only content.
- A sandbox audit checks app/worker entitlements, signatures, selected native symbols, and runtime source for network APIs.
- Realtime replay sends synthetic PCM in 100 ms blocks to actual packaged ASR/text workers with all network access denied; a socket attempt confirms the denial. Disposable worker copies are re-signed to run under this command-line sandbox.
- A separate bundle check uses an App Sandbox parent and the original inherited-sandbox workers, verifying packaged resource loading and ASR-to-text-model inference.

These are programmatic UI and recorded-audio integration checks. They are not a new live-microphone, mouse-driven end-to-end test, a representative speech benchmark, or proof of perfect offline behavior across all macOS services.

## Speech results

| Group | Result | Interpretation |
| --- | --- | --- |
| Existing synthetic cases | 8 / 8 expected decisions | Chinese commitments/negation, English insult/negation, rule changes, and mixed technical terms |
| Additional synthetic cases | 5 / 6 expected decisions | Conditional statements, complete commitments, numeric password, pet description, and Chinese→English continuation; one mixed-term semantic miss |

Known failure: a Chinese sentence containing “GitHub Actions” can be transcribed correctly but fail the rule asking for an alert whenever Chinese speech contains an English word, including product names. The case remains in `Tests/Evaluation/heldout.json`; no keyword workaround hides the miss.

A separately tested English translation of the built-in Chinese rule produced an incorrect alert on a commitment with both deadline and scope. That default-rule translation was reverted. Interface localization does not translate the active rule. Wording and language of a rule can affect semantic decisions.

In short realtime clips, first text appeared at roughly one second, and decisions often arrived about 1.5–3.3 seconds after the clip ended. Model loading is excluded. These are illustrative measurements from small synthetic fixtures, not latency guarantees or representative accuracy estimates. macOS voice versions can alter regenerated fixtures.

## Reproducing checks

Follow the README setup/build instructions first. Then run:

```bash
swift run WingmanCoreTests
bash Scripts/check-ui-language.sh
bash Scripts/audit-offline.sh
python3 Scripts/generate-fixtures.py
python3 Scripts/evaluate-streaming.py --realtime
python3 Scripts/evaluate-streaming.py --realtime --cases Tests/Evaluation/heldout.json
bash Scripts/evaluate-bundle.sh
```

The additional suite retains a known failing case and may exit nonzero. Fixtures require already-installed macOS voices; the generator blocks network access during synthesis and does not overwrite existing WAV files. The CLI evaluates a combined transcript after playback; the app's controller instead evaluates finalized segments and applies alert gating. Neither replay harness reproduces every live session scheduling edge case.

Before publishing source changes, stage the intended files, inspect the staged diff, and run `python3 Scripts/audit-publication.py`. Its exact-index checks detect blocked artifact paths, oversized files, common secret patterns, home-directory paths, and textual image metadata. This is a guardrail, not a comprehensive secret detector or a substitute for reviewing content and commit identity.
