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

## Multiple rules and current-speech update

- The final production prompt/backend passed 28/28 synthetic text cases: the existing eight cases plus twenty multiple-rule cases in `Tests/Evaluation/multiple-rules.json`. These exercise banana, negative remarks about Tom, rule-order permutations, matches in later lines, praise/negation, independent exceptions, speech/rule language mismatch, and old history that must not trigger a new alert. Language validation and verbatim-quote validation run on every alert. This does not measure ASR accuracy or guarantee wording quality.
- Fourteen core test groups pass, including independent model requests, cancelling superseded rule checks and reusing the worker, language validation, history exclusion, and a simulation of 10,000 successive segments. Waiting work stays bounded to the latest segment; expired results cannot be presented. This is a scheduling simulation, not a multi-hour microphone endurance run.
- The production UI harness passes floating visibility/persistence, stop/cancel state transitions, session preservation on pause, and English/Chinese rendered layouts. A native UI check also clicked the floating control to enter listening and clicked it again to stop microphone capture.
- The rebuilt signed bundle passed the runtime/signature audit and a realtime synthetic-audio replay through the packaged ASR and text workers. The unrelated password rule stayed quiet for the commitment fixture.
- Independent rule evaluation increases latency. In the final text run, two example rules took roughly 2–4 seconds for a match, and examples reaching later rules in a five-rule list took roughly 5–8 seconds, excluding model loading and ASR. Competing model processes can be much slower and may time out. New finalized speech cancels remaining old rule checks; skipped or expired speech is not replayed later.
- A decision regression on complete commitments was found during prompt development and corrected before the final 28-case run. Earlier experimental prompt results are not the shipped results. Suggestions can still include unnecessary advice; passing a decision/language check does not certify every generated sentence.

Run the text suite against an unsigned local development worker (or a disposable worker copy without inherited App Sandbox entitlements):

```bash
swift run WingmanPolicyCheck build/native/bin/text-worker Models/Qwen3-4B-Instruct-2507-Q4_K_M.gguf Tests/Evaluation/cases.json Tests/Evaluation/multiple-rules.json
```

## Statement continuity checks (2026-09-30)

This update supersedes the single-pending-segment scheduling described above. Adjacent finals settle for 1.5 seconds; an active preview can extend the group up to 12 seconds. Four statements can wait in FIFO order, and new speech no longer cancels an in-flight judgment. Pause/rule changes still invalidate work, and the 20-second freshness bound remains.

Core tests cover grouping, FIFO order, overflow/expiration, cancellation, and export diagnostics. `Scripts/check-statement-scheduling.sh` compiles the production controller with private access relaxed only in a temporary test copy. A delayed fake worker verifies continuation/correction grouping, retaining both in-flight and queued judgments, mute disposition, and pause cancellation. It uses isolated preferences without microphone capture or popups.

This is a scheduling check, not a semantic accuracy benchmark. Long pauses and grouping limits can still split a statement. Slow inference or a full queue can still skip work; exports now identify those paths and worker/validation errors. No topic-specific prompt branches or acronym extraction are used.

```bash
bash Scripts/check-statement-scheduling.sh
```

## Settings and sensitivity checks

The rule editor now retains 240 points of height inside a scrolling settings page, with a pinned save footer. The UI harness renders both languages at the previous window size, at 540 × 520, and in dark appearance at 680 × 820. Core worker checks verify that High reaches every independently evaluated rule through the system prompt.

`Tests/Evaluation/sensitivity.json` compares 15 synthetic statements across all three levels (45 expectations). The expectations are regression targets, not a claim that every case passes. Checks found that Low can still infer fatigue from indirect symptoms, Medium can alert on an ambiguous request for a break, and incomplete statements or invalid generated evidence can produce an unexpected outcome. High/Low differed on requests for a break, and targeted High checks recognized both borderline criticism and unexplained ETL/OLAP. These are synthetic text observations, not live-speech accuracy measurements or calibrated confidence thresholds. Failed cases are retained.

The policy harness accepts an optional `sensitivity` field per case (default `medium`) and serializes its own model suites with a process lock. Pause live listening before model checks; a running app does not participate in the test lock.

```bash
swift run WingmanPolicyCheck build/native/bin/text-worker Models/Qwen3-4B-Instruct-2507-Q4_K_M.gguf Tests/Evaluation/sensitivity.json
```

## Ultimate Test Case (2026-09-30)

Runtime sensitivity calibration now ranks profiles on identical positive sets within each inference path. At eight or more rules, High selects the previous Medium profile and Medium selects the previous High profile; Low stays unchanged. Smaller rule lists retain their ordering, which performed better on the independent short-text suite. The evaluation report explicitly separates reclassification of recorded continuous outputs from fresh model checks. Mapping boundary/request checks pass as part of 18 core groups; the fresh independent regression suite is 63/73, with failures retained. The quote-only veto introduced three short-text regressions and was withdrawn from that path.

The standalone [Ultimate Test Case](../Samples/UltimateTestCase/README.md) uses 12 simultaneous bilingual rules and one continuous 11 minute 26 second synthetic recording (1,462 Chinese characters and 1,197 English words). It runs real on-device ASR and text inference at all three sensitivities. Its audio-clock replay measures inference wall time and simulates queue scheduling; it does not measure live microphone acoustics or simultaneous ASR/model contention. The [evaluation report](../Samples/UltimateTestCase/EVALUATION.md) preserves every iteration, partial failures, frozen per-window labels, and complete three-level results.

This implementation supersedes the earlier 20-second freshness setting with a 30-second limit. An explicit `defer` can carry one original preceding window forward, within 24 seconds and 1,500 characters; it never accumulates an arbitrary conversation history. Large rule lists use semantic routing followed by independent candidate checks, evidence validation and bounded output repair. These are global mechanisms with no topic-specific rule branches. The report, rather than earlier short-case totals, is the current evidence for this long-input scenario.

```bash
bash Samples/UltimateTestCase/run.sh all
/usr/bin/python3 Samples/UltimateTestCase/score.py --run-dir "$(cat local-evaluation/ultimate/latest-run.txt)" --tag my-run --append
```

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
