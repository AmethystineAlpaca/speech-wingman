# Ultimate Test Case — Evaluation / 评估记录

日期 / Date: 2026-09-30 (Asia/Singapore)。本文件逐轮追加，不覆盖早期失败。

## 当前程序的敏感度映射 / Current runtime mapping — Iteration 12

**已修改实际推理代码。** 设置中保存的 Low/Medium/High 不改名；程序根据现有推理路径选择实测策略。12 条规则时，编译后的生产代码输出 `Low → legacy-low`、`Medium → legacy-high`、`High → legacy-medium`。这份映射进入独立候选判断和命中复核，不仅用于报告展示。

重新排名统一使用同一套 **15 个正例窗口**（原冻结标签的并集），而非比较分母分别为 12/13/15 的旧百分比：

| 当前档位 / Current level | 多规则实际策略 / Routed profile | 同口径召回 / Recall on the same positives | TP / FP / FN |
|---|---|---:|---:|
| Low | 旧 Low | 10/15 (66.7%) | 10 / 2 / 5 |
| Medium | 旧 High | 11/15 (73.3%) | 11 / 4 / 4 |
| High | 旧 Medium | 12/15 (80.0%) | 12 / 3 / 3 |

这里是 **Iteration 11 已记录输出按新映射重新统计**，不是另一次新跑的完整连续语音推理；原始输出和旧标签不改写。映射本身已经通过真实生产后端的请求检查，并另跑本地模型冒烟检查。版本标识为 `routed-recall-v1`。

少于 8 条规则的独立推理路径不交换档位：独立短句回归显示旧 High 的召回高于旧 Medium。直接全局交换会损害这条路径。两条路径都使用通用规则数量与已有执行方式决定映射，没有检查规则主题或例句。校准只重排已测策略，没有宣称模型能力凭改名得到提升。

少量规则路径在本轮新跑的共同 9 个正例上，Low/Medium/High 分别为 **5/9（55.6%）、7/9（77.8%）、8/9（88.9%）**。该集合与上表的 15 个长语音窗口不同，只在各自集合内比较排序。[可复核的校准结果](results/iteration12/calibration.json) · [编译后实际映射](results/iteration12/sensitivity-profiles.json)。

**The application mapping has changed.** On the routed path, the new High selects the previously measured Medium profile. The table reclassifies existing measurements on identical positives; it does not represent a fresh 44-window replay. The independent small-rule path retains its ordering. This is fixture-based calibration, not a universal guarantee of monotonic recall.

## 映射调整前的完整回放 / Complete replay before remapping — Iteration 11

**独立样例与三档连续回放已完成；质量有改善，但没有全面通过，不能判为稳定可用。** 12 条规则同时启用，一条约 11 分 26 秒的中英混合音频，源稿含 1,462 个中文字和 1,197 个英文单词。每档完整评估相同的 44 个窗口；没有将逐句测试代替最终长语音回放。

| Sensitivity / 敏感度 | Correct windows / 窗口符合预期 | TP / FP / FN | Decision precision / 判断精确率 | Recall / 召回率 | Presented TP / FP / 实际呈现 |
|---|---:|---:|---:|---:|---:|
| Low / 低 | 38/44 (86.4%) | 9 / 3 / 3 | 75.0% | 75.0% | 9 / 3 |
| Medium / 中 | 36/44 (81.8%) | 10 / 5 / 3 | 66.7% | 76.9% | 10 / 5 |
| High / 高 | 36/44 (81.8%) | 11 / 4 / 4 | 73.3% | 73.3% | 11 / 3 |

这是同一条音频在三种配置下的结果，不是 132 个独立语音样本。高档有一条误报因新鲜度检查没有呈现，判断层面仍计 FP。三档的真实正例都没有被呈现门控丢弃；高档仍有一条 `inconclusive`，不算安静成功。

| Sensitivity | Actual inference p50 / p95 | Simulated presented-alert delay p50 / p95 |
|---|---:|---:|
| Low | 4.33 / 10.46 s | 18.26 / 24.16 s |
| Medium | 4.83 / 11.99 s | 21.05 / 24.95 s |
| High | 6.70 / 17.38 s | 21.05 / 27.01 s |

右列从窗口最后一次 ASR final 起算，包含分窗等待、排队和实测推理；不包含真实同时运行 ASR 的计算等待，也不是从触发词出现起算的麦克风端到端延迟。本轮模型测试串行执行，期间源码指纹不变；普通桌面环境的负载和耗时波动仍存在。

The standalone fixture and all three replay runs are complete. Compared with the first valid complete run (Iteration 9), correct windows changed from **35/35/31** to **38/36/36** at low/medium/high. Iteration 0 was stopped early and cannot provide a comparable full-run accuracy baseline. Remaining false positives, missed alerts and delay prevent a claim of reliable real-world performance.

### 保留的问题 / Remaining failures

| Category / 类别 | Evidence / 证据 | Interpretation / 说明 |
|---|---|---|
| 未完成断言与跨窗口 / Incomplete claims | W8/W9，三档 | 前半段提前提醒，未返回 defer，因此后半段没有接上所需上下文。续接机制通过调度测试，不等于模型能可靠选择续接。 |
| 条件、排除与更正 / Conditions and corrections | W12、W18、W32 | 完整条件仍可误报，未满足的解释条件仍可漏报，后半段更正可能被忽略。 |
| 敏感度与边界 / Sensitivity boundaries | W34/W35 | 低、中档仍可能把含糊表达当作直接命中。高档召回也没有保持严格单调增加。 |
| 无效生成 / Invalid generation | W27，高档 | 原文引文校验在一次重试后仍失败，返回 inconclusive；低、中档该窗口通过。 |
| 原始语音与转录 / ASR loss | W11、W39 等 | 原稿中的触发内容可能被 ASR 改写或丢失，不能用转录后窗口分数掩盖。 |
| 建议表达 / Suggestion quality | 个别已匹配提醒 | 放宽长度解决强制截断；中英混用、过度概括及擅加规范判断仍需独立人工评价。 |

保留的生产改动都作用于通用流程：规则与发言边界、多规则分流及独立检查、有界分窗/FIFO/续接、严格输出验证、有限重试和输出长度。没有加入数字、缩写或某条规则的专用分支。Diagnostic F/G 的替代提示未通过足够验证，未采用。下一步更有价值的验证是独立真人语音及未参与调优的规则集；本报告没有把这些尚未做的验证写成已通过。

[最终逐窗记录与指标 / Final raw results](results/iteration11/summary.json) · [固定标签快照 / Label snapshot](results/iteration11/labels.json) · [完整口述稿 / Script](SCENARIO.md) · [运行说明 / Run instructions](README.md)

## 测试口径 / Method

- 一段连续合成音频，约 11 分 26 秒；1,462 个中文字 + 1,197 个英文单词；12 条中英规则始终同时启用。32 个源稿话题只是标注，不作为模型或 ASR 的切分边界。
- 本地 macOS TTS → 单条 PCM 音频流 → 实际 Silero VAD / SenseVoice ASR → 原始 partial/final 时间线 → Swift 生产核心的合并、FIFO、超时、文本模型和提醒门控。
- 文本模型为 Qwen3-4B-Instruct-2507、Q4_K_M；Apple M4、16 GB 统一内存、macOS 27.0。完整运行目录保留模型、worker、音频、事件和源码 SHA-256；这不是多个机型或不同模型的横向测试。
- ASR 加速运行，调度在音频时钟上模拟，文本模型推理真实执行，实测推理耗时推进模拟时钟。不是真人麦克风或全链路实时墙钟延迟测试。
- 网络被 sandbox-exec 禁止，并用 socket 尝试确认。源稿、规则、初始预期在模型评估前写定；分窗语义标签独立于模型输出。
- “安静”只接受 no_alert / defer；inconclusive、invalid、expired、overflow 不会作为正确的安静判断。分别统计规则判断与实际可呈现提醒。
- 多条规则命中一个窗口时，产品只显示一条已验证提醒；必须核对规则身份，不以任意 alert 算通过。
- 固定标签的正例窗口数分别为低档 12、中档 13、高档 15。高敏感度允许指定的边界案例，但不允许忽略规则的明确排除条件。敏感度是提示层面的行为要求，不是经过校准的概率阈值。
- “Correct windows”衡量提醒决策及匹配规则身份。原文必须通过连续子串与基本语言验证，但该得分不等于建议措辞的人工质量评分：仍可见中英混用、泛化建议，以及把用户规则擅自称作“违规”的措辞。第 11 轮放宽长度只修正硬截断，不证明这些语义问题已经消失。

Continuous synthetic audio, real local ASR/model inference, and audio-clock scheduling simulation. This is a development stress test, not a representative real-speaker accuracy benchmark. Labels and source text are never supplied to the model as answers.

### 源稿与识别后的差异 / Source versus recognized speech

下方分数衡量固定 ASR 输出上的窗口行为，**不是原始口述意图的端到端准确率**。60 个 final、635 个 partial 合并为 44 个窗口；ASR 加速处理墙钟约 117.4 秒。

- W11：源稿的明确保证被识别成 `iI will finish over the work`。低档标签为安静，中、高档仍要求识别承诺；原稿中的强确定性信号已经损失。
- W39：源稿的第二次 banana 被识别成 `banner`。仍可命中 R02 对汤姆的批评，但不能以这个成功证明 banana 被识别出来。
- W16：API 被识别成 ATI；解释文字仍在，因此标签要求安静。W18 末尾还插入了源稿没有的日语片段。
- W8/W9：语气停顿把未完成的断言与其内容切开。标签要求 W8 保持安静或 defer，W9 通过有界续接命中 R03；只有前半段误报不算成功。`window-labels-v1.json` 保留初版，当前评分固定使用 `window-labels.json` 的流水线目标，不再按输出改标签。
- W31 的“没有核实，但现在当作确定事实传播”按后半段立场标为 R11；W32 后半段的指定负责人按更正处理，标为安静。这是本场景的固定解释，含语义歧义，不代表已经取得多人标注的一致性。

Source losses and annotation assumptions are retained alongside the scores. The original scenario expectations, frozen ASR-window labels, actual inference inputs and raw results remain separately inspectable. No ASR spelling is corrected before model evaluation.

## 每轮记录 / Iteration history

### Iteration 0 — 原实现基线 / Original baseline

状态：**提前停止 / stopped early**。只运行低敏感度；中、高未运行。

- 改动 / Change: 保持原有逐条推理；增加评估记录中的匹配规则索引。
- 已记录 4 / 44 个窗口；状态 {'evaluated': 4, 'expired': 1, 'pending': 39}。
- 已完成窗口的判断 / Decisions: {'inconclusive': 4}。
- 实测推理墙钟均值 20.73s，中位数 20.67s。
- 12 条规则逐条检查超出判断预算，暂停以处理系统性瓶颈。
- 原始结果 / Raw results: [JSON](results/baseline-low.json)。

### Iteration 1 — 分组筛查 / Group screening

状态：**提前停止 / stopped early**。只运行低敏感度；中、高未运行。

- 改动 / Change: 8 条及以上规则先按每组 4 条做 OR 筛查，命中组逐条独立确认；增加通用的全段语义指令。
- 已记录 15 / 44 个窗口；状态 {'evaluated': 15, 'expired': 1, 'pending': 28}。
- 已完成窗口的判断 / Decisions: {'no_alert': 10, 'alert': 2, 'inconclusive': 3}。
- 实测推理墙钟均值 10.06s，中位数 8.59s。
- 发现长段落否定误报、开头命中漏报和无效输出。此轮提前停止，不能当作完整三档结果。
- 原始结果 / Raw results: [JSON](results/iteration1-low.json)。

### Diagnostic A — 等待边界与全局 prompt / Boundary and global prompt

将连续片段等待上限从 12 秒调为 18 秒，以容纳 ASR 最长约 15 秒的连续片段；加强全局否定、例外及证据要求。用固定的 4 个失败窗口做局部诊断：**1/4** 通过。Banana 命中恢复，否定评价、假密码和完整承诺仍失败。不是完整连续回放。

### Diagnostic B — 长文本命中复核 / Contextual review

加入基于完整上下文的第二次命中复核，限制建议长度。4 个固定窗口：**1/4** 通过。假密码保持安静；Banana 复核输出语言错误，否定窗口尚未达到当时复核的长度阈值，完整承诺仍误报。阈值随后改为长文本或大量规则均复核。

### Diagnostic C — 分阶段输出 / Staged output

筛查只生成 decision，独立候选只生成 decision + quote，最终复核才生成 suggestion。4 个固定窗口：**1/4** 通过。减少无用输出，但暴露候选引文不为连续原文的问题；Banana 漏报、两例 inconclusive 保留。

以上诊断仅用于定位通用流程问题；不是三档最终成绩。 / These focused diagnostics are not final three-level results.

### Iteration 2 — 通用 harness / General harness

**提前停止 / Stopped early.** 分阶段语法约束、规则身份记录、上下文复核、18 秒合并上限、只允许显式 defer 延续到紧邻下一窗口的有界上下文。没有规则关键词分支或专用分类器。全局提示删除了具体领域提示。

本轮低敏感度完成 12/28 个窗口（含失败）；中、高未运行。状态：{'evaluated': 11, 'invalid': 1, 'pending': 16}；判断：{'no_alert': 7, 'alert': 2, 'inconclusive': 2}；已返回窗口平均墙钟耗时 12.78s。

加长时间窗口导致不同话题混合，仍不能保证未完成前半句与后半句合并；本轮还出现 token budget exceeded、无效候选引文、错误的承诺提醒和过期提醒。因此不保留单纯加长到 18 秒的策略。原始结果：[JSON](results/iteration2-low.json)。


### Iteration 3 — 有界续接与输出约束 / Bounded continuation and output

**提前停止 / Stopped early**。恢复 12 秒合并上限；显式 defer 仅向紧邻下一窗口续接，最多 24 秒间隔、1,500 字符，不递归累积；仅对无效候选进行一次全上下文修复，原文验证仍严格；语法限制 quote / suggestion 长度，避免长输出耗尽 token 预算。新鲜度上限调整到 30 秒，给合并等待和多规则推理留出空间，代价是可能出现更晚的提醒。

所有机制与规则内容无关：不检测具体主题，不加入案例词表，不替换 ASR 内容。

### iteration3 — 自动计分 / Frozen-label scoring

| Sensitivity | Returned | Correct windows | TP/FP/FN | Precision | Recall | Presented recall | Inference p50/p95 |
|---|---:|---:|---:|---:|---:|---:|---:|
| low | 18/44 | 15/44 (34.1%) | 3/2/9 | 60.0% | 25.0% | 25.0% | 9.03/18.85s |

分母包含未完成、错误、过期及丢弃窗口。TP 必须命中预期规则身份；一个错误规则提醒同时计 FP，并使应有提醒计 FN。这里的延迟是实测文本推理加音频时钟模拟，不含真实实时 ASR 计算等待。 / Missing work never counts as quiet success. Wrong-rule alerts are not true positives.

**low** — statuses `{'evaluated': 18, 'pending': 26}`; decisions `{'no_alert': 13, 'alert': 5}`; continuations 0; validation diagnostics 1.

| Window | Expected | Actual | Rule | Presented |
|---|---|---|---|---|
| W8 | quiet | alert | R03 | True |
| W9 | R03 | no_alert | — | False |
| W12 | quiet | alert | R04 | True |
| W18 | R06 | pending | — | False |
| W19 | R07 | pending | — | False |
| W20 | quiet | pending | — | False |
| W21 | quiet | pending | — | False |
| W22 | R08 | pending | — | False |
| W23 | quiet | pending | — | False |
| W24 | R09 | pending | — | False |
| W25 | quiet | pending | — | False |
| W26 | quiet | pending | — | False |
| W27 | R10 | pending | — | False |
| W28 | quiet | pending | — | False |
| W29 | quiet | pending | — | False |
| W30 | quiet | pending | — | False |
| W31 | R11 | pending | — | False |
| W32 | quiet | pending | — | False |
| W33 | quiet | pending | — | False |
| W34 | quiet | pending | — | False |
| W35 | quiet | pending | — | False |
| W36 | quiet | pending | — | False |
| W37 | quiet | pending | — | False |
| W38 | quiet | pending | — | False |
| W39 | R02 | pending | — | False |
| W40 | R12 | pending | — | False |
| W41 | quiet | pending | — | False |
| W42 | quiet | pending | — | False |
| W43 | quiet | pending | — | False |

[Raw results](results/iteration3/low.json) · [Per-window scores](results/iteration3/low-scored.json)


### Iteration 4 — 结构化语义复核 / Structured semantic review

**提前停止 / Stopped early**。将复核输出改为 complete、matches、excluded 三个布尔值，由程序组合为 defer / no_alert / alert，只有通过复核的提醒才验证和显示引文与建议。保持规则无关，不加入任何具体主题的判断分支。三档使用同一音频、规则和冻结标签；此前轮次未完成的模式明确保留为未运行。

### iteration4 — 自动计分 / Frozen-label scoring

| Sensitivity | Returned | Correct windows | TP/FP/FN | Precision | Recall | Presented recall | Inference p50/p95 |
|---|---:|---:|---:|---:|---:|---:|---:|
| low | 15/44 | 11/44 (25.0%) | 3/3/9 | 50.0% | 25.0% | 25.0% | 9.71/17.93s |

分母包含未完成、错误、过期及丢弃窗口。TP 必须命中预期规则身份；一个错误规则提醒同时计 FP，并使应有提醒计 FN。这里的延迟是实测文本推理加音频时钟模拟，不含真实实时 ASR 计算等待。 / Missing work never counts as quiet success. Wrong-rule alerts are not true positives.

**low** — statuses `{'evaluated': 15, 'pending': 29}`; decisions `{'no_alert': 9, 'alert': 6}`; continuations 0; validation diagnostics 1.

| Window | Expected | Actual | Rule | Presented |
|---|---|---|---|---|
| W7 | quiet | alert | R02 | True |
| W8 | quiet | alert | R03 | True |
| W9 | R03 | no_alert | — | False |
| W12 | quiet | alert | R04 | True |
| W15 | quiet | pending | — | False |
| W16 | quiet | pending | — | False |
| W17 | quiet | pending | — | False |
| W18 | R06 | pending | — | False |
| W19 | R07 | pending | — | False |
| W20 | quiet | pending | — | False |
| W21 | quiet | pending | — | False |
| W22 | R08 | pending | — | False |
| W23 | quiet | pending | — | False |
| W24 | R09 | pending | — | False |
| W25 | quiet | pending | — | False |
| W26 | quiet | pending | — | False |
| W27 | R10 | pending | — | False |
| W28 | quiet | pending | — | False |
| W29 | quiet | pending | — | False |
| W30 | quiet | pending | — | False |
| W31 | R11 | pending | — | False |
| W32 | quiet | pending | — | False |
| W33 | quiet | pending | — | False |
| W34 | quiet | pending | — | False |
| W35 | quiet | pending | — | False |
| W36 | quiet | pending | — | False |
| W37 | quiet | pending | — | False |
| W38 | quiet | pending | — | False |
| W39 | R02 | pending | — | False |
| W40 | R12 | pending | — | False |
| W41 | quiet | pending | — | False |
| W42 | quiet | pending | — | False |
| W43 | quiet | pending | — | False |

[Raw results](results/iteration4/low.json) · [Per-window scores](results/iteration4/low-scored.json)


Iteration 4 仍出现“判断是提醒、生成文字却说无需提醒”的内部矛盾，因此不能宣布修复成功。原始记录及冻结标签计分见上表。

### Iteration 5 — 先概括事实，再作判断 / Assessment before decision

**已结束，worker 失败 / Ended with worker failure**。复核先输出一句有长度上限的通用事实概括，再填写完整性、命中、例外三个判断，缓解先输出决策再事后解释的偏差。没有增加任何特定规则或领域示例。

Iteration 5 在低档发生 worker 失败，旧测试器仍继续发送请求，随后两档均返回“本地模型未就绪”，不构成有效的中、高档推理测试。低档原始 JSON 在下一轮启动后被覆盖，不能再声称具有完整逐规则原始记录；保留的逐窗口日志如下，后续工具将改成每轮独立目录和每档独立加载，防止重现。

- low: `{'no_alert': 10, 'alert': 3, 'defer': 2, 'inconclusive': 1, 'invalid': 9}`
- medium: `{'invalid': 44}`
- high: `{'invalid': 44}`

[保留日志](results/iteration5/preserved-output.txt) · [日志摘要与限制](results/iteration5/log-summary.json)。未返回窗口、过期及 worker 失败均不算通过。

### Iteration 6 — 相关规则分流 / Semantic routing

**提前停止 / Stopped early**。只用模型选出可能相关的规则，包括否定、未说完和存在例外的情况，再逐条独立核查完整语义。分流不直接提醒，索引受到语法与范围校验；分流结果非法时回退到逐条核查。用减少模型调用次数来改善吞吐，不以特定主题词匹配替代语义判断。

### iteration6 — 自动计分 / Frozen-label scoring

| Sensitivity | Returned | Correct windows | TP/FP/FN | Precision | Recall | Presented recall | Inference p50/p95 |
|---|---:|---:|---:|---:|---:|---:|---:|
| low | 19/44 | 10/44 (22.7%) | 3/2/9 | 60.0% | 25.0% | 16.7% | 19.90/33.83s |

分母包含未完成、错误、过期及丢弃窗口。TP 必须命中预期规则身份；一个错误规则提醒同时计 FP，并使应有提醒计 FN。这里的延迟是实测文本推理加音频时钟模拟，不含真实实时 ASR 计算等待。 / Missing work never counts as quiet success. Wrong-rule alerts are not true positives.

**low** — statuses `{'evaluated': 17, 'invalid': 2, 'expired': 4, 'pending': 21}`; decisions `{'no_alert': 6, 'defer': 3, 'alert': 5, 'inconclusive': 3}`; continuations 2; validation diagnostics 5.

| Window | Expected | Actual | Rule | Presented |
|---|---|---|---|---|
| W5 | quiet | inconclusive | — | False |
| W8 | quiet | alert | R03 | True |
| W9 | R03 | no_alert | — | False |
| W10 | quiet | inconclusive | — | False |
| W11 | quiet | alert | R04 | False |
| W12 | quiet | invalid | — | False |
| W13 | R05 | expired | — | False |
| W15 | quiet | expired | — | False |
| W16 | quiet | invalid | — | False |
| W18 | R06 | defer | — | False |
| W19 | R07 | expired | — | False |
| W20 | quiet | inconclusive | — | False |
| W21 | quiet | expired | — | False |
| W23 | quiet | pending | — | False |
| W24 | R09 | pending | — | False |
| W25 | quiet | pending | — | False |
| W26 | quiet | pending | — | False |
| W27 | R10 | pending | — | False |
| W28 | quiet | pending | — | False |
| W29 | quiet | pending | — | False |
| W30 | quiet | pending | — | False |
| W31 | R11 | pending | — | False |
| W32 | quiet | pending | — | False |
| W33 | quiet | pending | — | False |
| W34 | quiet | pending | — | False |
| W35 | quiet | pending | — | False |
| W36 | quiet | pending | — | False |
| W37 | quiet | pending | — | False |
| W38 | quiet | pending | — | False |
| W39 | R02 | pending | — | False |
| W40 | R12 | pending | — | False |
| W41 | quiet | pending | — | False |
| W42 | quiet | pending | — | False |
| W43 | quiet | pending | — | False |

[Raw results](results/iteration6/low.json) · [Per-window scores](results/iteration6/low-scored.json)


Iteration 6 仍有无效引文、生成超出 token 预算和过期提醒。中、高档未运行，不能使用前一轮留在同名文件中的结果。

### Iteration 7 — 完整复跑 / Full rerun

**提前停止 / Stopped early**。一次对最多 12 条规则做相关性分流，减少重复输入；复核只比较必要事实与已表达事实。缩短受约束输出的字段长度；区分无效模型输出与 worker 故障。每轮使用独立目录、每档重新加载模型，防止旧结果混入或一档故障污染后续档位。小规则配置恢复原有简短全局 prompt，避免长提示拖累原有回归集。只运行低档的一部分；中、高档未运行。

### iteration7 — 自动计分 / Frozen-label scoring

| Sensitivity | Returned | Correct windows | TP/FP/FN | Precision | Recall | Presented recall | Inference p50/p95 |
|---|---:|---:|---:|---:|---:|---:|---:|
| low | 6/44 | 5/44 (11.4%) | 1/0/11 | 100.0% | 8.3% | 0.0% | 20.87/31.74s |

分母包含未完成、错误、过期及丢弃窗口。TP 必须命中预期规则身份；一个错误规则提醒同时计 FP，并使应有提醒计 FN。这里的延迟是实测文本推理加音频时钟模拟，不含真实实时 ASR 计算等待。 / Missing work never counts as quiet success. Wrong-rule alerts are not true positives.

**low** — statuses `{'evaluated': 6, 'expired': 2, 'pending': 36}`; decisions `{'defer': 4, 'inconclusive': 1, 'alert': 1}`; continuations 2; validation diagnostics 1.

| Window | Expected | Actual | Rule | Presented |
|---|---|---|---|---|
| W1 | quiet | inconclusive | — | False |
| W2 | quiet | expired | — | False |
| W6 | R02 | expired | — | False |
| W8 | quiet | pending | — | False |
| W9 | R03 | pending | — | False |
| W10 | quiet | pending | — | False |
| W11 | quiet | pending | — | False |
| W12 | quiet | pending | — | False |
| W13 | R05 | pending | — | False |
| W14 | quiet | pending | — | False |
| W15 | quiet | pending | — | False |
| W16 | quiet | pending | — | False |
| W17 | quiet | pending | — | False |
| W18 | R06 | pending | — | False |
| W19 | R07 | pending | — | False |
| W20 | quiet | pending | — | False |
| W21 | quiet | pending | — | False |
| W22 | R08 | pending | — | False |
| W23 | quiet | pending | — | False |
| W24 | R09 | pending | — | False |
| W25 | quiet | pending | — | False |
| W26 | quiet | pending | — | False |
| W27 | R10 | pending | — | False |
| W28 | quiet | pending | — | False |
| W29 | quiet | pending | — | False |
| W30 | quiet | pending | — | False |
| W31 | R11 | pending | — | False |
| W32 | quiet | pending | — | False |
| W33 | quiet | pending | — | False |
| W34 | quiet | pending | — | False |
| W35 | quiet | pending | — | False |
| W36 | quiet | pending | — | False |
| W37 | quiet | pending | — | False |
| W38 | quiet | pending | — | False |
| W39 | R02 | pending | — | False |
| W40 | R12 | pending | — | False |
| W41 | quiet | pending | — | False |
| W42 | quiet | pending | — | False |
| W43 | quiet | pending | — | False |

[Raw results](results/iteration7/low.json) · [Per-window scores](results/iteration7/low-scored.json)


### Diagnostic D — 配置与发言分离 / Configuration versus speech

固定四个窗口的分流诊断：原先将 rules 与 speech 放在同一个 user JSON；改为规则放入配置指令、user 只含 speech。候选索引从零开始。

| Window | Before | After |
|---|---|---|
| W0，无关开场白 | 0,5,10,11 | empty |
| W7，否定评价 | 1 | 1 |
| W8，未完成断言 | 0,2 | 2 |
| W9，后续片段 | 2,5,10 | 2 |

这是局部路由诊断，不是端到端提醒准确率。

### Iteration 8 — 明确输入边界 / Explicit input boundaries

**提前停止 / Stopped early**。分流和复核均隔离规则配置与语音数据，区分缺少相关信息和未说完。低档仅完成部分窗口；复杂的多字段复核仍有无效输出与过度 defer，因此移除该复杂输出结构，中、高档未运行。

### iteration8 — 自动计分 / Frozen-label scoring

| Sensitivity | Returned | Correct windows | TP/FP/FN | Precision | Recall | Presented recall | Inference p50/p95 |
|---|---:|---:|---:|---:|---:|---:|---:|
| low | 21/44 | 13/44 (29.5%) | 2/1/10 | 66.7% | 16.7% | 16.7% | 5.88/12.43s |

分母包含未完成、错误、过期及丢弃窗口。TP 必须命中预期规则身份；一个错误规则提醒同时计 FP，并使应有提醒计 FN。这里的延迟是实测文本推理加音频时钟模拟，不含真实实时 ASR 计算等待。 / Missing work never counts as quiet success. Wrong-rule alerts are not true positives.

**low** — statuses `{'evaluated': 21, 'pending': 23}`; decisions `{'no_alert': 4, 'defer': 9, 'inconclusive': 5, 'alert': 3}`; continuations 8; validation diagnostics 5.

| Window | Expected | Actual | Rule | Presented |
|---|---|---|---|---|
| W3 | quiet | inconclusive | — | False |
| W4 | R01 | defer | — | False |
| W7 | quiet | inconclusive | — | False |
| W9 | R03 | inconclusive | — | False |
| W10 | quiet | inconclusive | — | False |
| W11 | quiet | inconclusive | — | False |
| W13 | R05 | alert | R04 | True |
| W18 | R06 | defer | — | False |
| W21 | quiet | pending | — | False |
| W22 | R08 | pending | — | False |
| W23 | quiet | pending | — | False |
| W24 | R09 | pending | — | False |
| W25 | quiet | pending | — | False |
| W26 | quiet | pending | — | False |
| W27 | R10 | pending | — | False |
| W28 | quiet | pending | — | False |
| W29 | quiet | pending | — | False |
| W30 | quiet | pending | — | False |
| W31 | R11 | pending | — | False |
| W32 | quiet | pending | — | False |
| W33 | quiet | pending | — | False |
| W34 | quiet | pending | — | False |
| W35 | quiet | pending | — | False |
| W36 | quiet | pending | — | False |
| W37 | quiet | pending | — | False |
| W38 | quiet | pending | — | False |
| W39 | R02 | pending | — | False |
| W40 | R12 | pending | — | False |
| W41 | quiet | pending | — | False |
| W42 | quiet | pending | — | False |
| W43 | quiet | pending | — | False |

[Raw results](results/iteration8/low.json) · [Per-window scores](results/iteration8/low-scored.json)

### Iteration 9 — 简短独立判断 / Short independent judgments

**三档完整回放完成 / Full three-level replay completed**。保留配置/发言边界及语义分流，撤回复杂布尔复核和长事实概括，回到简短的独立规则判断、原文校验、FIFO 与有界续接。本轮三档均使用独立 worker；不覆盖以往失败结果。

### Diagnostic E — 引文一致性与格式重试 / Evidence consistency and format retry

在完整上下文已经命中后，对引文本身做一个通用的否定/未完成检查；这个步骤只能否决，不单独产生提醒。无效生成最多重新生成一次，仍严格要求原文子串和正确提醒语言。8 个固定窗口局部诊断 **6/8**：W0、W4、W22、W24、W27、W31 通过；W7 的否定和 W8 的未完成断言仍失败。W27 的无效引文通过有界重试恢复。完整回放另外加入敏感度约束，诊断分数不能直接当作完整回放结果。

[Diagnostic E raw output](results/diagnostic-e.txt)

### iteration9 — 自动计分 / Frozen-label scoring

| Sensitivity | Returned | Correct windows | TP/FP/FN | Precision | Recall | Presented recall | Inference p50/p95 |
|---|---:|---:|---:|---:|---:|---:|---:|
| low | 44/44 | 35/44 (79.5%) | 7/4/5 | 63.6% | 58.3% | 58.3% | 4.24/7.34s |
| medium | 44/44 | 35/44 (79.5%) | 10/7/3 | 58.8% | 76.9% | 76.9% | 4.87/6.91s |
| high | 44/44 | 31/44 (70.5%) | 12/10/3 | 54.5% | 80.0% | 80.0% | 5.12/6.79s |

分母包含未完成、错误、过期及丢弃窗口。TP 必须命中预期规则身份；一个错误规则提醒同时计 FP，并使应有提醒计 FN。这里的延迟是实测文本推理加音频时钟模拟，不含真实实时 ASR 计算等待。 / Missing work never counts as quiet success. Wrong-rule alerts are not true positives.

**low** — statuses `{'evaluated': 44}`; decisions `{'no_alert': 32, 'alert': 11, 'inconclusive': 1}`; continuations 0; validation diagnostics 1.

| Window | Expected | Actual | Rule | Presented |
|---|---|---|---|---|
| W7 | quiet | alert | R02 | True |
| W8 | quiet | alert | R03 | True |
| W9 | R03 | no_alert | — | False |
| W11 | quiet | alert | R06 | True |
| W22 | R08 | no_alert | — | False |
| W24 | R09 | no_alert | — | False |
| W27 | R10 | inconclusive | — | False |
| W31 | R11 | no_alert | — | False |
| W34 | quiet | alert | R05 | True |

[Raw results](results/iteration9/low.json) · [Per-window scores](results/iteration9/low-scored.json)

**medium** — statuses `{'evaluated': 44}`; decisions `{'no_alert': 26, 'alert': 17, 'inconclusive': 1}`; continuations 0; validation diagnostics 1.

| Window | Expected | Actual | Rule | Presented |
|---|---|---|---|---|
| W7 | quiet | alert | R02 | True |
| W8 | quiet | alert | R03 | True |
| W9 | R03 | no_alert | — | False |
| W11 | R04 | alert | R06 | True |
| W12 | quiet | alert | R04 | True |
| W25 | quiet | alert | R09 | True |
| W27 | R10 | inconclusive | — | False |
| W32 | quiet | alert | R12 | True |
| W34 | quiet | alert | R05 | True |

[Raw results](results/iteration9/medium.json) · [Per-window scores](results/iteration9/medium-scored.json)

**high** — statuses `{'evaluated': 44}`; decisions `{'no_alert': 20, 'alert': 22, 'inconclusive': 2}`; continuations 0; validation diagnostics 3.

| Window | Expected | Actual | Rule | Presented |
|---|---|---|---|---|
| W2 | quiet | alert | R02 | True |
| W7 | quiet | alert | R02 | True |
| W8 | quiet | alert | R03 | True |
| W9 | R03 | no_alert | — | False |
| W10 | quiet | inconclusive | — | False |
| W11 | R04 | alert | R06 | True |
| W12 | quiet | alert | R04 | True |
| W15 | quiet | alert | R05 | True |
| W25 | quiet | alert | R09 | True |
| W27 | R10 | inconclusive | — | False |
| W28 | quiet | alert | R10 | True |
| W29 | quiet | alert | R11 | True |
| W32 | quiet | alert | R12 | True |

[Raw results](results/iteration9/high.json) · [Per-window scores](results/iteration9/high-scored.json)

### Iteration 10 — 通用复核与有界修复 / General review and bounded repair

在 Iteration 9 上增加引文复核及一次无效输出重试；不更改规则、源稿、ASR、分窗标签。完整上下文判断仍负责触发条件，引文复核只能否决。复核传入同一敏感度，并明确排除条件优先。低规则数路径也使用同一复核机制，需要另跑原有回归集，不能只凭 Ultimate Test Case 的改进判断没有回归。

Three-level replay uses the same fixed audio and frozen labels. The additional check is global and contains no domain-specific examples or token matching. It adds inference cost and may reject context-dependent quotations; both missed alerts and extra delay remain part of the evaluation.

本轮高档有一段与 Diagnostic F 争用本地模型资源：诊断脚本误将锁写到 `/tmp`，Swift 测试器使用系统临时目录，两个锁没有互斥。行为结果仍保留，但高档延迟不是无争用的性能对照。诊断脚本随后统一到系统临时目录，最终复跑需串行执行。Low/medium had already run before this overlap; the high-level timing is explicitly marked as affected by competing inference.

### iteration10 — 自动计分 / Frozen-label scoring

| Sensitivity | Returned | Correct windows | TP/FP/FN | Precision | Recall | Presented recall | Inference p50/p95 |
|---|---:|---:|---:|---:|---:|---:|---:|
| low | 44/44 | 38/44 (86.4%) | 9/3/3 | 75.0% | 75.0% | 75.0% | 4.21/9.96s |
| medium | 44/44 | 36/44 (81.8%) | 10/5/3 | 66.7% | 76.9% | 76.9% | 5.81/11.05s |
| high | 44/44 | 36/44 (81.8%) | 11/4/4 | 73.3% | 73.3% | 73.3% | 5.70/10.51s |

分母包含未完成、错误、过期及丢弃窗口。TP 必须命中预期规则身份；一个错误规则提醒同时计 FP，并使应有提醒计 FN。这里的延迟是实测文本推理加音频时钟模拟，不含真实实时 ASR 计算等待。 / Missing work never counts as quiet success. Wrong-rule alerts are not true positives.

**low** — statuses `{'evaluated': 44}`; decisions `{'no_alert': 32, 'alert': 12}`; continuations 0; validation diagnostics 2.

| Window | Expected | Actual | Rule | Presented |
|---|---|---|---|---|
| W8 | quiet | alert | R03 | True |
| W9 | R03 | no_alert | — | False |
| W18 | R06 | no_alert | — | False |
| W31 | R11 | no_alert | — | False |
| W32 | quiet | alert | R12 | True |
| W34 | quiet | alert | R05 | True |

[Raw results](results/iteration10/low.json) · [Per-window scores](results/iteration10/low-scored.json)

**medium** — statuses `{'evaluated': 44}`; decisions `{'no_alert': 29, 'alert': 15}`; continuations 0; validation diagnostics 2.

| Window | Expected | Actual | Rule | Presented |
|---|---|---|---|---|
| W8 | quiet | alert | R03 | True |
| W9 | R03 | no_alert | — | False |
| W11 | R04 | no_alert | — | False |
| W12 | quiet | alert | R04 | True |
| W18 | R06 | no_alert | — | False |
| W32 | quiet | alert | R12 | True |
| W34 | quiet | alert | R05 | True |
| W35 | quiet | alert | R02 | True |

[Raw results](results/iteration10/medium.json) · [Per-window scores](results/iteration10/medium-scored.json)

**high** — statuses `{'evaluated': 44}`; decisions `{'no_alert': 27, 'alert': 15, 'inconclusive': 1, 'defer': 1}`; continuations 1; validation diagnostics 2.

| Window | Expected | Actual | Rule | Presented |
|---|---|---|---|---|
| W8 | quiet | alert | R03 | True |
| W9 | R03 | no_alert | — | False |
| W11 | R04 | no_alert | — | False |
| W12 | quiet | alert | R04 | True |
| W18 | R06 | no_alert | — | False |
| W27 | R10 | inconclusive | — | False |
| W29 | quiet | alert | R11 | True |
| W32 | quiet | alert | R12 | True |

[Raw results](results/iteration10/high.json) · [Per-window scores](results/iteration10/high-scored.json)

### Diagnostic F — 中性完整发言判断 / Neutral full-context decision

16 个固定窗口，**12/16**。W7（否定）、W8（未完成）、W18（未解释术语）、W34（低档边界）失败。未采用此提示替换生产流程。本次存在上文披露的并发争用，不用其耗时做性能结论。[Raw results](results/diagnostic-f.json).

### Diagnostic G — 提示对照 / Prompt alternatives

同样 16 个窗口，在正确共享锁下串行推理：中文严格复核（附引文和完整发言）**13/16**；英文完整发言判断 **11/16**。前者仍失败 W8、W18、W32，后者仍失败 W7、W8、W18、W32、W34。这些是局部诊断，不是连续回放，也没有覆盖完整三档，未凭局部分数替换生产流程。[Raw requests and results](results/diagnostic-g.json).

### Iteration 11 — 输出边界修正与串行复跑 / Output bound and serialized rerun

Iteration 10 的英文建议出现词尾被硬截断：64 字符的语法上限对英文过短。统一放宽至现有验证器的 160 字符上限，仍保留 256 token 预算、严格原文验证和有界重试；不改规则语义提示、不增加领域示例。本轮重新串行跑全部三档，随后运行原有 73 条文本回归，避免 Diagnostic F 的争用问题。长度限制仍不是自然语言完整性的证明。

The only production change since Iteration 10 is the generic suggestion-length grammar bound. All three levels are rerun with the same frozen fixtures. This round also supplies a clean, isolated timing comparison; model mistakes are retained even when the displayed sentence is well formed.

### iteration11 — 自动计分 / Frozen-label scoring

| Sensitivity | Returned | Correct windows | TP/FP/FN | Precision | Recall | Presented recall | Inference p50/p95 |
|---|---:|---:|---:|---:|---:|---:|---:|
| low | 44/44 | 38/44 (86.4%) | 9/3/3 | 75.0% | 75.0% | 75.0% | 4.33/10.46s |
| medium | 44/44 | 36/44 (81.8%) | 10/5/3 | 66.7% | 76.9% | 76.9% | 4.83/11.99s |
| high | 44/44 | 36/44 (81.8%) | 11/4/4 | 73.3% | 73.3% | 73.3% | 6.70/17.38s |

分母包含未完成、错误、过期及丢弃窗口。TP 必须命中预期规则身份；一个错误规则提醒同时计 FP，并使应有提醒计 FN。这里的延迟是实测文本推理加音频时钟模拟，不含真实实时 ASR 计算等待。 / Missing work never counts as quiet success. Wrong-rule alerts are not true positives.

**low** — statuses `{'evaluated': 44}`; decisions `{'no_alert': 32, 'alert': 12}`; continuations 0; validation diagnostics 2.

实际呈现的提醒距窗口最后一次 ASR final 的模拟延迟 / Presented alert delay from the last ASR final, audio-clock simulation: p50 **18.26s**, p95 **24.16s**. This includes grouping/queue wait and inference, not live ASR computation.

实际呈现 / Presented: 9 true positives, 3 false positives.

| Window | Expected | Actual | Rule | Presented |
|---|---|---|---|---|
| W8 | quiet | alert | R03 | True |
| W9 | R03 | no_alert | — | False |
| W18 | R06 | no_alert | — | False |
| W31 | R11 | no_alert | — | False |
| W32 | quiet | alert | R12 | True |
| W34 | quiet | alert | R05 | True |

[Raw results](results/iteration11/low.json) · [Per-window scores](results/iteration11/low-scored.json)

**medium** — statuses `{'evaluated': 44}`; decisions `{'no_alert': 29, 'alert': 15}`; continuations 0; validation diagnostics 2.

实际呈现的提醒距窗口最后一次 ASR final 的模拟延迟 / Presented alert delay from the last ASR final, audio-clock simulation: p50 **21.05s**, p95 **24.95s**. This includes grouping/queue wait and inference, not live ASR computation.

实际呈现 / Presented: 10 true positives, 5 false positives.

| Window | Expected | Actual | Rule | Presented |
|---|---|---|---|---|
| W8 | quiet | alert | R03 | True |
| W9 | R03 | no_alert | — | False |
| W11 | R04 | no_alert | — | False |
| W12 | quiet | alert | R04 | True |
| W18 | R06 | no_alert | — | False |
| W32 | quiet | alert | R12 | True |
| W34 | quiet | alert | R05 | True |
| W35 | quiet | alert | R02 | True |

[Raw results](results/iteration11/medium.json) · [Per-window scores](results/iteration11/medium-scored.json)

**high** — statuses `{'evaluated': 44}`; decisions `{'no_alert': 27, 'alert': 15, 'inconclusive': 1, 'defer': 1}`; continuations 1; validation diagnostics 2.

实际呈现的提醒距窗口最后一次 ASR final 的模拟延迟 / Presented alert delay from the last ASR final, audio-clock simulation: p50 **21.05s**, p95 **27.01s**. This includes grouping/queue wait and inference, not live ASR computation.

实际呈现 / Presented: 11 true positives, 3 false positives.

| Window | Expected | Actual | Rule | Presented |
|---|---|---|---|---|
| W8 | quiet | alert | R03 | False |
| W9 | R03 | no_alert | — | False |
| W11 | R04 | no_alert | — | False |
| W12 | quiet | alert | R04 | True |
| W18 | R06 | no_alert | — | False |
| W27 | R10 | inconclusive | — | False |
| W29 | quiet | alert | R11 | True |
| W32 | quiet | alert | R12 | True |

[Raw results](results/iteration11/high.json) · [Per-window scores](results/iteration11/high-scored.json)

### Iteration 11 — 独立回归补充 / Independent regression addendum

73 条原有回归完成 **60/73**，对照前一短提示版本的 **63/73**，新增失败为 `implied-criticism-low`、`unexplained-acronym-mixed-low`、`unexplained-acronym-mixed-medium`，没有新增恢复。因此不能把大量规则场景的改善当作全局无回归。[Raw regression output](results/iteration11/regressions.txt).

### Iteration 12 — 实际档位校准与回归回退 / Runtime calibration and regression rollback

按用户要求，修改生产代码中设置档位到推理策略的映射。先以相同正例集合比较召回，避免不同分母的误排名；大量规则路径旧 Medium/High/Low 的召回为 12/15、11/15、10/15，因此当前 High/Medium/Low 对应这三种策略。少量规则的独立回归排序不同，保留原映射。

同时撤回独立小规则路径的新增引文否决步骤，处理 Iteration 11 的三例新增漏报；原有完整上下文复核、原文验证、规则独立性和静音门控仍保留。大规则路径除映射外没有改推理流程、提示文本或语法。新测试检查了 1/7/8/12/24 条规则的映射边界、保存后用户档位不变，以及真实 `LocalTextBackend` 发往 worker 的判断和复核请求。

本轮区分三种证据：①先前长回放的同口径重计分；②新代码的真实模型短回归和映射冒烟；③控制器/构建/离线审计。不会把①写成重新合成长语音或重新执行了全部连续推理。

新一轮独立回归 **63/73**，恢复上轮的三例新增漏报，仍保留 10 例失败。少量规则的共同正例召回分别为 Low 5/9、Medium 7/9、High 8/9，因此这一推理路径保持原排序。[Raw regression output](results/iteration12/regressions.txt)。

实际本地模型映射冒烟 **5/6**：三档 W0 均保持安静；Low/High 的 W27 正确提醒；当前 Medium（旧 High 策略）的 W27 仍因无效引文返回 inconclusive。该失败保留，不算映射通过后的语义问题已经修好。当前 High 在相同文本上取得了旧 Medium 的提醒结果。[Smoke inputs](results/iteration12/model-smoke-cases.json) · [Smoke output](results/iteration12/model-smoke.txt)。

核心 **18 组通过**，包含映射边界、持久化档位身份、生产 worker 请求中实际策略的验证；生产控制器调度检查通过。[Check output](results/iteration12/checks.txt)。

新版 `build/Speech Wingman.app` 已从当前校准代码重新构建；原生 worker、应用打包与签名验证通过，离线权限/符号审计通过。源码指纹与编译映射检查保持一致。[Build/check exit status](results/iteration12/build-checks.json)。这是源代码及打包的验证，不是实际麦克风会话的端到端验证。

### 0.4.0 发布复核 / Release verification

发布前重新运行 18 组核心检查、生产控制器调度检查、中英文/深浅色/小窗口 UI 检查；重建 0.4.0（build 5）应用并通过签名和离线审计。打包应用的网络受限音频冒烟测试保持预期的 `no_alert`：首段预览 1.01 秒，最终转录 4.98 秒，判断 0.89 秒，音频 4.09 秒。该单条无关规则测试验证打包链路，不取代上面的 63/73 语义回归，也不代表连续多规则延迟。

This publication pass adds no new model-tuning iteration. Historical model outputs and scores remain unchanged. The local repository prefix in the compiler warnings in `results/diagnostic-e.txt` is normalized to `<repository>/` for publication; the warnings and evaluation results are retained. Trailing whitespace in archived text logs is removed; decisions, timings and scores are unchanged. Public screenshots use fictional content and the current settings window size.
