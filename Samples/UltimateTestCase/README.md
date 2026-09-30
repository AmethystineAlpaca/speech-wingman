# Ultimate Test Case

独立的端侧长语音压力样例：**12 条中英规则、1,462 个中文字 + 1,197 个英文单词、一条约 11 分 26 秒的连续音频**。包含中文、英文和中英混说、句中思考停顿、短气口、零额外间隔、连续换题、否定、补充、例外、多规则命中和嵌入式指令。

A standalone on-device stress sample: 12 simultaneous bilingual rules and one continuous fictional monologue. The 32 annotated topic blocks never reset ASR or the session. They are not fed to the model as separate test cases.

- [每轮评估与最终三档结果 / Evaluation history](EVALUATION.md)
- [完整口述稿 / Full annotated script](SCENARIO.md)
- [固定场景与源稿预期 / Scenario](scenario.json)
- [实际分窗的冻结标签 / Frozen window labels](window-labels.json)
- [12 条可粘贴的规则 / Copyable rules](rules.txt)
- [原始结果与逐窗计分 / Results](results/)

## 运行 / Run

先按仓库说明准备模型、Swift、原生依赖及 macOS 已安装的 Samantha / Tingting 声音。无需云端 API；模型和声音必须事先在本机可用。

From the repository root, after completing its local model/runtime setup:

```bash
bash Scripts/build-worker.sh
bash Samples/UltimateTestCase/run.sh all
/usr/bin/python3 Samples/UltimateTestCase/score.py \
  --run-dir "$(cat local-evaluation/ultimate/latest-run.txt)" --tag my-run --append
```

`all` 依次运行 `low`、`medium`、`high`，共用同一音频与 ASR 时间线。也可指定单档。首次运行自动生成音频并转录；若修改场景，先重新运行 `/usr/bin/python3 Samples/UltimateTestCase/audio.py`。默认输出在被 Git 忽略的 `local-evaluation/ultimate/`；设置 `ULTIMATE_OUTPUT` 可使用独立输出目录。计分的 `--tag` 用新名称保存每轮；不要重复使用已有标签。

The output directory contains `ultimate.wav`, audio/worker fingerprints, source timing spans, all ASR partials/finals, the assembled windows, and per-level decisions. `score.py` verifies window-text hashes against the frozen labels and refuses mismatched windows. Different OS/voice versions can change synthesized audio: such a run needs a separately reviewed label file, not automatic relabeling against model predictions.

## 测量边界 / Measurement boundaries

音频以 100 ms PCM 块进入真实本地 ASR，整个录音期间不重置；ASR 加速运行并保留音频时钟。Swift 回放工具复用生产核心的片段缓冲、FIFO、续接、文本模型、验证和提醒门控；复现控制器的计时调度，使用实测文本推理耗时推进模拟时钟。模型进程之间串行运行，避免多个评估争抢显存。

This is **accelerated audio-clock replay with actual local inference**, not real-time microphone capture. It does not measure hardware microphone quality, human accents, acoustic background noise, TTS naturalness, real-time ASR/LLM contention, or UI popup behavior. Two installed TTS voices simulate one continuous bilingual speaker; no claim is made that it is a real human recording. Additional controller checks exercise production scheduling with a controlled worker.

原文、标签和模型输出分开保存。标签不作为提示词。漏转录、提前提醒、错误规则、无效输出、超时、丢弃及没有实际呈现的提醒都必须在报告中可见。源稿中有触发、但 ASR 改写后不再满足条件的情况，必须另外报告，不能只给转录后窗口的准确率。

## 实现原则 / Harness principles

1. 大量规则使用语义相关性分流，候选再逐条独立验证；分流不直接产生提醒。Routing can still omit a relevant rule, which remains a measured model failure.
2. 分流和独立判断使用通用 JSON 语法约束；命中后复核引文，无效输出最多重试一次。Only final validated evidence and language can reach the alert gate.
3. 只有显式 `defer` 才保留紧邻前一段，限定时间、字符数和配置版本；不递归积累历史。
4. 所有机制适用于任意用户规则，没有 banana、密码、缩写等专用识别分支。
5. 这个场景用于开发调试；原有独立回归集用于检查外溢影响。单个合成场景的高分不代表通用准确率。

每次运行的结果写入全新 `run.*` 子目录，`latest-run.txt` 指向最近一次。每档重新加载 worker；真正的 worker 失败会停止该档并明确标记未执行窗口。受约束生成未完成归为无效模型输出，不等同于 worker 崩溃。

## 敏感度校准 / Sensitivity calibration

实际程序的 `routed-recall-v1` 映射：8 条及以上规则时，UI Low/Medium/High 分别选择原 Low/High/Medium 提示策略；少量规则路径保留原顺序。设置保存的档位名称没有被改写。原提示字符串保持不变；按相同正例集合比较的召回率用于排序，不能比较不同分母的旧百分比。

`run.sh profiles` 会编译生产代码并输出本场景的真实策略映射，不启动文本模型推理。已有音频 fixture 时，可复核校准结果：

```bash
bash Samples/UltimateTestCase/run.sh profiles
/usr/bin/python3 Samples/UltimateTestCase/calibrate.py \
  --source Samples/UltimateTestCase/results/iteration11 \
  --profile-run "$(cat local-evaluation/ultimate/latest-run.txt)" \
  --short-log local-evaluation/ultimate-regressions-iteration12.log \
  --tag my-calibration
```

Calibration reclassifies recorded long-run outputs; it does not silently present them as fresh inference. The report separately records fresh regression/model smoke checks and the limitations of calibrating on development fixtures.
