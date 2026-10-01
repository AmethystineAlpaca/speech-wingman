# Multilingual recorded replay

One continuous audio track passes through the production `SpeechStream`, `SessionController`, `LocalTextBackend`, result validator, alert gate, and SwiftUI views. The only input substitution is prerecorded synthetic PCM in place of the microphone. No transcripts, model decisions, or alert suggestions are supplied by the harness.

The scenario moves through English → Mandarin Chinese → Japanese → Korean → Cantonese, then repeats those languages with one-second pauses between sentences. The same recognizer stays in `auto` mode for the entire session. One English rule asks for an alert on mentions of bananas; the interface and generated reminders stay in English.

## Results and media

- [Full video with original audio](../../docs/assets/multilingual-continuous.mp4)
- [Five-language GIF](../../docs/assets/multilingual-five-languages.gif)
- [Mixed-conversation GIF](../../docs/assets/multilingual-mixed.gif)
- [Actual inputs and voice names](../../docs/assets/multilingual-input.json)
- [Every ASR preview/final, evaluation, and alert](../../docs/assets/multilingual-report.json)
- [Checks and source/binary/media hashes](../../docs/assets/multilingual-summary.json)
- [Rapid-switch stress-test failure](../../docs/assets/multilingual-rapid-stress.json)

The approximately 38-second recorded run produced ten finalized utterances and ten actual alerts, with no pipeline errors. The banana concept survived in every utterance, including Cantonese. This is a narrow trigger test, not a word-accuracy score or a general model-accuracy claim. Korean spacing/repeated syllables and Cantonese orthography are visible in the unedited outputs. Some alerts legitimately quote an earlier live preview rather than the later finalized transcript.

The introductory graphic and language indicators are replay metadata, not recognition results. Checkmarks mean that the input has played, not that its transcript is perfect. The right-hand session view and floating control use production views bound to the actual running controller. Controls are not clicked during the recording. Old alerts are dismissed at the start of the next top-level example, without changing recognition settings. GIFs are silent excerpts at the original two-frame-per-second capture rate; the video contains the full run and original synthetic audio.

## Known boundary: very rapid switching

The initial [stress scenario](rapid-within-segment.json) used only 250 ms between the five languages in its final passage. ASR merged that passage into a single segment and lost much of the wording. The raw final output was:

```text
s香蕉나나를 좋아해요我吃香蕉。
```

An alert still occurred on an earlier preview; that is **not** evidence of a complete or accurate multilingual transcript. The successful demonstration uses natural sentence pauses. Both results are retained; do not describe this as flawless recognition of arbitrary within-sentence language mixing.

## Reproduce locally

Requires the repository's model/runtime setup, a built app, Swift/AppKit, and installed macOS voices Samantha, Tingting, Kyoko, Yuna, and Sinji. It uses an isolated preferences domain and does not change the user's rules or language selection. The harness briefly opens its own recording window and actual alert panels.

```bash
bash Scripts/build-app.sh
bash Scripts/record-multilingual-demo.sh
xcrun swiftc -parse-as-library Scripts/render-multilingual-media.swift \
  -o local-evaluation/multilingual-demo/render-media
local-evaluation/multilingual-demo/render-media "$PWD"
cp local-evaluation/multilingual-demo/report.json docs/assets/multilingual-report.json
cp local-evaluation/multilingual-demo/input.json docs/assets/multilingual-input.json
/usr/bin/python3 Scripts/verify-multilingual-demo.py
```

To rerun the deliberately difficult stress input, use `bash Scripts/record-multilingual-demo.sh --scenario Tests/MultilingualDemo/rapid-within-segment.json`. This replaces local replay outputs; archive them separately before rerunning the successful scenario. The successful-run verifier is intentionally not expected to pass on that stress case.

The recording script compiles a temporary copy of the current controller with access control relaxed, following the existing scheduling-test approach. The shipping application has no recording or replay hook. Packaged helpers are copied and locally re-signed without the sandbox-inheritance requirement so that a command-line test harness can launch them; their source and models are unchanged. This replay itself is not a network-denied test. The separate `Scripts/audit-offline.sh` checks shipping sandbox entitlements and binary/source properties.

All media stays local until explicitly published. Voice/OS versions and inference timing can change output; the verifier fails rather than substituting expected text. Generated input audio and frame sequences remain under ignored `local-evaluation/`; only the deliberate demonstration media and JSON evidence live in `docs/assets/`.
