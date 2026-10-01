# 0.4.0 release notes

[README](../README.md) · [Changelog](../CHANGELOG.md)

This update brings together the UI, continuous-speech processing, sensitivity calibration, and evaluation work since the previous commit. Write **one rule per line**, with its exceptions on the same line; any matching rule can produce a reminder in the language of your current speech.

The **floating control now shows live text** in a fixed-height viewport, follows revised and finalized speech, retains finalized text when paused, and collapses after clearing the session. Drag the title or text area to move it; use the new gear button to open settings. Starting and stopping capture still preserves the session.

The **settings page has a larger rule editor**, a character counter, expandable examples, three selectable sensitivity cards, and a pinned **Save and apply** footer with save feedback and ⌘S. It scrolls in smaller windows and supports English/Chinese and light/dark appearances.

- **Speech continuity:** nearby ASR finals settle together before evaluation. New speech no longer cancels an in-flight judgment; up to four statements wait in FIFO order. An explicit `defer` can carry one original preceding statement into the next evaluation, with bounded age and size. This still cannot guarantee every correction or thinking pause is joined correctly.
- **General rule processing:** eight or more rules use relevance routing and independent candidate checks. Rule configuration and speech are separated, generated evidence is validated, and routed output gets at most one repair attempt. There are no topic-specific keyword patches. Output bounds and separate invalid-output/worker-error handling improve failure reporting; English suggestions have more room before the length limit.
- **Measured sensitivity mapping:** on the routed path, High selects the former Medium profile, Medium selects the former High profile, and Low stays unchanged. Smaller rule lists retain their original ordering because their measured recall ranking differs. Saved UI choices keep their identity; exports record mapping version `routed-recall-v1`.
- **Inspect missed alerts:** JSON exports include configuration snapshots, actual inference text, source segment IDs, deferral links, matched rule index, queue/expiration/cancellation status, validation errors, timing, and whether a reminder was presented or suppressed.
- **Reproducible evaluation:** the standalone [Ultimate Test Case](../Samples/UltimateTestCase/README.md) has 12 bilingual rules and one continuous 11-minute-26-second recording, with thinking pauses and code-switching. Its [Markdown report](../Samples/UltimateTestCase/EVALUATION.md) retains iterations 0–12, diagnostics, raw results, failed runs, frozen labels, and source/model fingerprints.

See [measured accuracy and latency](validation.md#measured-accuracy-and-latency). The published [v0.4.0 source preview](https://github.com/AmethystineAlpaca/speech-wingman/releases/tag/v0.4.0) includes source and an evaluation archive; build the offline app locally using the pinned models.

## 中文更新说明

这次汇总了上次提交以来的全部功能更新：

- **悬浮窗：** 显示最近发言和实时转写，自动跟随最新一行，识别修正后同步更新；暂停保留定稿文字，清空后收起。标题和文字区可拖动，新增齿轮按钮直达设置。
- **设置页：** 更大的规则编辑区、字符计数、可展开例子、三档敏感度卡片，以及固定在底部的保存栏、保存反馈和 ⌘S；兼顾小窗口、中英文和深浅色界面。
- **连续发言：** 合并相邻定稿片段，新发言不再取消正在判断的内容；最多四条 FIFO 等待。明确返回 `defer` 时可续接一个原始前段，限制为同配置、24 秒间隔和 1,500 字符，避免无限累积历史。提醒新鲜度从 20 秒放宽到 30 秒，代价是部分提醒更晚。
- **通用判断流程：** 8 条及以上规则先做相关性分流，再独立检查候选；分离规则与发言、严格验证原文、限制输出长度并允许一次无效输出修复。没有为数字、缩写或某条例句写专用识别分支。
- **实际敏感度映射：** 多规则路径的 High 使用旧 Medium 策略，Medium 使用旧 High，Low 不变；少量规则保持原顺序。设置值保持原名称，导出记录映射版本。撤回了导致三例短句新增漏报的额外引文复核。
- **诊断和独立样例：** 导出加入配置快照、实际输入、原始片段关联、续接来源、命中规则、过期/丢弃/取消/无效状态及是否呈现；新增 12 条规则、11 分 26 秒连续中英混合语音的 Ultimate Test Case，保留第 0–12 轮及所有诊断结果。

**准确率有改善，但仍未全面通过。** 开发过程中，两次完整回放的原始三档窗口符合预期数从 **35/35/31 提升到 38/36/36（各 44 个窗口）**；不能把它写成相对上次 Git 提交的完整准确率对比。按同一套 15 个正例重新计分，当前 Low/Medium/High 召回率为 **66.7%／73.3%／80.0%**。这是既有长回放按新映射重算；独立的新一轮回归为 **63/73**，映射冒烟为 **5/6**，核心测试 **18 组通过**。

**延迟也公开保留。** 当前长语音中三档的文本推理中位数约 **4.33／6.70／4.83 秒**，从窗口最后一次 ASR 定稿到实际呈现的模拟中位数约 **18.26／21.05／21.05 秒**，包含合并等待和排队，不含真实并发 ASR 的计算等待。更多上下文和复核存在延迟代价，不宣称整体都更快。早期“约 1 秒预览”是不同阶段的短句测试结果。

[完整双语评估与每轮记录](../Samples/UltimateTestCase/EVALUATION.md) · [独立样例及运行方式](../Samples/UltimateTestCase/README.md) · [v0.4.0 源码预览发布](https://github.com/AmethystineAlpaca/speech-wingman/releases/tag/v0.4.0)。公开发布继续提供源码与评估资料包；本地构建的应用包含离线模型，使用本机签名。
