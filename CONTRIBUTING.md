# Contributing

English and Chinese contributions are welcome. Useful places to start:

- Report a reproducible recognition or rule-evaluation failure using a fictional sentence.
- Share an alert recipe with positive, negative, and ambiguous examples.
- Test an Apple Silicon / macOS configuration and record what actually worked.
- Improve setup instructions, translations, accessibility, or tests.

Use [Discussions](https://github.com/AmethystineAlpaca/speech-wingman/discussions) for questions and rule ideas, [Issues](https://github.com/AmethystineAlpaca/speech-wingman/issues/new/choose) for actionable bugs, and focused pull requests for changes. Search for an existing report first.

## Development

Follow the [build instructions](docs/guide.md#getting-started). See [Development and checks](docs/development.md) for the full command reference and repository layout. Core checks need no model weights:

```bash
swift run WingmanCoreTests
```

For UI changes, run `bash Scripts/check-ui-language.sh` in a desktop session. Refresh public UI illustrations with `bash Scripts/check-ui-language.sh --public-demo` and inspect every changed image; that mode uses isolated preferences and fictional English examples. Regenerate the project card with `swift Scripts/render-social-preview.swift docs/assets/social-preview.png`. For inference changes, also run the offline audit and audio replays described in `docs/validation.md`. Use the production `WingmanPolicyCheck` text suite for independent-rule and language regressions; its invocation is in `docs/validation.md`. Preserve known failures; do not tune a hardcoded keyword rule to make a semantic test appear to pass.

Explain the behavior change and checks in your PR. If you have not tested live audio, another macOS version, or an English/Chinese rule, say so. Discuss large architecture changes before implementing them.

## Privacy and accurate evidence

Only share fictional or deliberately sanitized material. Do not commit recordings, session exports, secrets, private logs, downloaded models, compiled apps, or paths to your home directory. Use a GitHub noreply email if you want to keep your email private.

Stage the intended files and run `python3 Scripts/audit-publication.py`, then inspect the diff and image content yourself. The scanner is a scoped guardrail, not a guarantee. Screenshots made with fictional data must be labeled as demonstrations, not measured model output.

This source is MIT licensed. Model weights and third-party code keep their own licenses. Keep the offline runtime boundary and license notices intact.

## 中文

欢迎中文反馈和贡献。可以分享带正反例的提醒规则、使用虚构句子报告漏报/误报、验证其他 Apple Silicon 机型，或改善文档、翻译和可访问性。请先查找已有讨论，提交改动时写清楚实际测试范围。

不要公开真实对话、个人资料、密钥、日志、模型权重或本机目录。截图如使用虚构内容，请明确标注。较大的架构调整请先发起讨论。
