# Third-party notices

- **Qwen3-4B-Instruct-2507**, Apache 2.0. Original: https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507 . Q4_K_M conversion: https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF . Pinned revisions and SHA-256: `Models/manifest-text.json`; original license included.
- **SenseVoiceSmall**, original weights under the FunASR Model Open Source License Agreement (not Apache 2.0). Original: https://huggingface.co/FunAudioLLM/SenseVoiceSmall . ONNX conversion: https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17 . Both the original model agreement and converter's license pointer are included in `Models/`; pinned model and license hashes in `manifest-asr.json`.
- **Silero VAD v6.2**, MIT. https://github.com/snakers4/silero-vad . Model and license hashes in `Models/manifest-vad.json`.
- **sherpa-onnx v1.13.8**, Apache 2.0. https://github.com/k2-fsa/sherpa-onnx . Native CPU inference; ONNX Runtime **1.28.2**, MIT, with its third-party notices. Official release archive and individual runtime file hashes are in `Resources/asr-runtime.json`.
- **llama.cpp / ggml**, MIT, commit `272aad8b984a4470d26f14bea8d958be68ac7c0c`. https://github.com/ggml-org/llama.cpp . This build links text inference only; server, HTTP, multimodal projector and web UI are disabled.
- **nlohmann JSON**, MIT, and the upstream public-domain base64 helper retain their notices in the bundled `Licenses` directory.

Apple audio/UI frameworks are supplied by macOS. The application does not use Apple's Speech service. Model download tools and Python are development-only and are not bundled. Models and inference runtimes are bundled; no runtime account, network download or cloud fallback exists.
