import Foundation

/// Shared interface and generated-alert language; ASR and verbatim quotes remain unchanged.
public enum DisplayLanguage: String, CaseIterable, Codable, Sendable {
    case english = "en"
    case chinese = "zh-Hans"
    case japanese = "ja"
    case korean = "ko"
    public static let preferenceKey = "displayLanguage"
    public static func load(from defaults: UserDefaults = .standard) -> Self {
        defaults.string(forKey: preferenceKey).flatMap(Self.init(rawValue:)) ?? .english
    }
    public func save(to defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: Self.preferenceKey) }
    public var locale: Locale { Locale(identifier: rawValue) }
    public var name: String {
        switch self { case .english: "English"; case .chinese: "中文"; case .japanese: "日本語"; case .korean: "한국어" }
    }
    public var defaultRule: String {
        switch self {
        case .english: "Alert when the current speech makes a firm commitment but lacks an explicit deadline or delivery scope. Do not alert for denials of a guarantee, wishes, or commitments with complete conditions."
        case .chinese: "当当前发言作出强确定性承诺，但当前发言缺少明确截止时间或交付范围时提醒。否定自己能保证、愿望和条件完整的承诺不提醒。"
        case .japanese: "現在の発言で確実な約束をしているのに、明確な期限または提供範囲が欠けている場合に通知する。保証できることの否定、願望、条件がすべて明示された約束では通知しない。"
        case .korean: "현재 발언에서 확실한 약속을 하지만 명확한 기한이나 제공 범위가 없으면 알린다. 보장할 수 없다는 표현, 희망 사항, 조건이 완전한 약속에는 알리지 않는다."
        }
    }
    public var suggestionInstruction: String {
        switch self {
        case .english: "English only. suggestion MUST contain no Chinese, Japanese or Korean text, regardless of the speech or rule language. Keep quote verbatim."
        case .chinese: "suggestion必须只用简体中文，不跟随发言或规则的语言，suggestion只能使用汉字、数字和中文标点，不能包含任何英文字母。外文单词必须翻译为中文，不便翻译的词用“该词”指代。例如：提到了香蕉。外文原词仅保留在quote中，quote不能翻译。"
        case .japanese: "suggestionは日本語のみで書いてください。発言やルールの言語に左右されず、ラテン文字や他言語を混ぜず、外来語はカタカナで表記してください。quoteは原文のまま保持してください。"
        case .korean: "suggestion은 한국어로만 작성하세요. 발언이나 규칙의 언어와 관계없이 라틴 문자나 다른 언어를 섞지 말고 외래어도 한글로 표기하세요. quote는 원문을 그대로 유지하세요."
        }
    }
    public func acceptsSuggestion(_ value: String) -> Bool {
        let latin = value.range(of: "[A-Za-z]", options: .regularExpression) != nil
        let kana = value.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) }
        let hangul = value.unicodeScalars.contains { (0xAC00...0xD7AF).contains($0.value) || (0x1100...0x11FF).contains($0.value) }
        switch self {
        case .english: return !SpeechLanguage.containsChinese(value) && !kana && !hangul
        case .chinese: return !latin && !kana && !hangul && SpeechLanguage.detect(value) == .chinese
        case .japanese: return kana && !hangul && !latin
        case .korean: return hangul && !kana && !latin && !SpeechLanguage.containsChinese(value)
        }
    }
    public func text(_ key: String) -> String {
        guard self != .chinese else {
            for (prefix, _) in Self.errorPrefixes where key.hasPrefix(prefix) {
                return prefix + text(String(key.dropFirst(prefix.count)))
            }
            return SpeechLanguage.containsChinese(key) ? key : "未知错误"
        }
        if self == .japanese || self == .korean {
            if let pair = Self.asianStrings[key] { return pair[self == .japanese ? 0 : 1] }
            for (prefix, _) in Self.errorPrefixes where key.hasPrefix(prefix) {
                return text(prefix) + text(String(key.dropFirst(prefix.count)))
            }
            return text("未知错误")
        }
        if let translated = Self.englishStrings[key] { return translated }
        // Localize error wrappers; never leak an untranslated diagnostic into another language.
        for (prefix, translated) in Self.errorPrefixes where key.hasPrefix(prefix) {
            return translated + text(String(key.dropFirst(prefix.count)))
        }
        if key.hasPrefix("缺少 "), let start = key.range(of: "（"), let end = key.range(of: "）") {
            return "Missing local model resource (" + key[start.upperBound..<end.lowerBound] + "). Reinstall the app or run Scripts/setup-model.py and rebuild."
        }
        return SpeechLanguage.containsChinese(key) ? "Unknown error." : key
    }
    public func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }
    private static let errorPrefixes = [
        ("导出失败：", "Export failed: "),
        ("模型输出未通过校验：", "Invalid model output: "),
        ("本地模型错误：", "Local model error: "),
        ("无法启动本地模型 worker：", "Could not start local model worker: ")
    ]
    private static let englishStrings: [String: String] = [
        "转录正常；上一条判断超出模型容量，已跳过提醒": "Transcription is running. The previous evaluation exceeded model capacity; alert skipped.",
        "规则候选索引无效": "Invalid rule candidate index.",
        "规则候选重复": "Duplicate rule candidates.",
        "中间判断字段或类型错误": "Invalid intermediate evaluation fields or types.",
        "中间判断缺少连续原文证据": "Intermediate evaluation lacks verbatim evidence.",

        "提醒语言与设置不符": "Alert language does not match the selected language.",
        "提醒设置": "Alert settings",
        "Speech Wingman 实验版": "Speech Wingman Preview",
        "多语言 · 离线": "Multilingual · Offline",
        "麦克风": "Microphone",
        "本次判断已处理 %.0f 秒": "Evaluating · %.0f s",
        "开始监听": "Start listening",
        "加载中…": "Loading…",
        "暂停": "Pause",
        "继续": "Resume",
        "停止并清空": "Stop and clear",
        "设置": "Settings",
        "提醒": "Alert",
        "原话：%@": "Quote: %@",
        "原话": "Quote",
        "关闭": "Dismiss",
        "静音一小时": "Mute for one hour",
        "提醒静音至 %@": "Alerts muted until %@",
        "取消静音": "Unmute",
        "当前会话转写": "Session transcript",
        "手动开始后监听麦克风中的所有人声。未满足提醒条件时保持安静。": "Start listening to monitor speech picked up by the microphone. No alert appears unless your rule is met.",
        "实时转录中…": "Transcribing…",
        "主动导出会话": "Export session",
        "判断 %.1f 秒": "Evaluation %.1f s",
        "转录定稿后 %.1f 秒完成判断（排队 %.1f 秒）": "Decision %.1f s after final transcript (queue %.1f s)",
        "默认不保存音频。选择“停止并清空”会清空本次转写与提醒。": "Audio is not saved. “Stop and clear” clears this session’s transcript and alerts.",
        "退出": "Quit",
        "本地语音处理": "On-device speech processing",
        "多语言自动转录 + Qwen3 4B 文本判断": "Automatic multilingual ASR + Qwen3 4B evaluation",
        "英语、中文、日语、韩语和粤语自动识别，可交替使用，无需切换语言。模型已随应用打包，运行不联网。转录持续显示，判断在后台进行。": "English, Chinese, Japanese, Korean, and Cantonese are recognized automatically, including language switches. Models are bundled for offline use. Transcripts update as you speak; evaluation runs in the background.",
        "提醒条件": "Alert rules",
        "每行一条规则，命中任意一条就提醒。每条的例外条件写在同一行。提醒使用设置中选择的语言。": "One rule per line; any match triggers an alert. Keep each rule’s exceptions on the same line. Alerts use the selected language.",
        "例如：说到 banana 就提醒。\n说汤姆的坏话就提醒，赞扬他不提醒。": "Examples: Alert when I say banana.\nAlert if I speak badly of Tom, but not when I praise him.",
        "桌面悬浮按钮": "Floating desktop button",
        "停止监听": "Stop listening",
        "取消加载": "Cancel loading",
        "正在监听": "Listening",
        "等待语音…": "Waiting for speech…",
        "点击重试": "Click to retry",
        "点击开始": "Click to start",
        "拖动空白处移动；点击按钮开始或停止监听": "Drag the background to move; click the button to start or stop listening",
        "拖动标题或文字区移动；点击按钮开始或停止监听": "Drag the title or transcript to move; click the button to start or stop listening",
        "当前片段未能完成判断，已跳过提醒": "The current segment could not be fully evaluated; alert skipped.",
        "提醒语言与当前发言不符": "Alert language does not match the current speech.",
        "敏感度": "Sensitivity",
        "回车新建规则；长句会自动换行。": "Return starts a new rule; long lines wrap automatically.",
        "查看规则示例": "Show example rules",
        "仅明显命中": "Clear matches only",
        "明确语义匹配": "Clear meaning & intent",
        "包括边界情况": "Include borderline matches",
        "低：只在表达直接、证据明确时提醒，尽量减少打扰。": "Low: alert only for direct, unambiguous matches, keeping interruptions to a minimum.",
        "中：也识别清楚的同义表达和隐含意思；模糊情况保持安静。": "Medium: also recognize clear paraphrases and implied meaning; stay quiet when evidence is ambiguous.",
        "高：有相关证据的暗示和可能命中也提醒，优先减少漏报。": "High: also alert on hints and possible matches supported by the speech, prioritizing fewer misses.",
        "所有档位都遵守规则中的例外条件。高敏感度可能增加误报，也不能保证不漏报。": "Every level respects your rule’s exceptions. High may produce more false alerts and can still miss matches.",
        "低": "Low",
        "中": "Medium",
        "高": "High",
        "%d / 4000 字": "%d / 4000 characters",
        "保存并应用": "Save and apply",
        "应用新条件时会取消旧判断，并从新的音频片段开始。麦克风中的其他人声也会参与判断。": "Applying a new rule cancels pending evaluations and starts a new audio segment. Other voices picked up by the microphone are also evaluated.",
        "Speech Wingman 提醒": "Speech Wingman Alert",
        "界面语言": "Interface and alert language",
        "设置界面与生成提醒的语言；转录与引用保留原文。": "Sets the interface and generated alert language. Speech and verbatim quotes keep their original language.",
        "已停止": "Stopped",
        "音频设备已改变，请继续监听": "Audio device changed. Resume listening to continue.",
        "请填写最多 4000 字的提醒条件": "Enter an alert rule of up to 4,000 characters.",
        "正在加载本地多语言转录和文本判断…": "Loading on-device transcription and evaluation…",
        "请在系统设置中允许麦克风访问": "Allow microphone access in System Settings.",
        "正在本机监听 · 多语言自动识别": "Listening on device · Multilingual recognition",
        "已暂停": "Paused",
        "提醒条件已保存": "Alert rule saved",
        "提醒条件已保存；已暂停": "Alert rule saved; listening is paused",
        "判断积压过多，已停止监听；转录已保留，请继续重试": "Evaluation backlog is full. Listening stopped; transcript retained. Start again to retry.",
        "单段转录超出判断容量": "Transcript segment exceeds evaluation capacity.",
        "转录正常；上一条判断无效，已跳过提醒": "Transcription is running. An invalid evaluation was skipped.",
        "麦克风音频格式不可用": "Microphone audio format is unavailable.",
        "多语言转录加载超时": "Multilingual transcription took too long to load.",
        "ASR 未就绪或音频块无效": "Transcription is not ready or the audio block is invalid.",
        "ASR 跟不上收音，已暂停；请继续重试": "Transcription could not keep up. Listening paused; resume to retry.",
        "ASR 未就绪": "Transcription is not ready.",
        "ASR 收尾超时": "Transcription finalization timed out.",
        "ASR 已停止": "Transcription stopped.",
        "ASR 音频传输失败": "Audio transfer failed.",
        "ASR 输出超出限制": "Transcription output exceeds the limit.",
        "ASR 协议错误": "Transcription protocol error.",
        "ASR 转录格式错误": "Invalid transcription format.",
        "ASR 失败": "Transcription failed.",
        "未知 ASR 消息": "Unknown transcription message.",
        "多语言转录进程已退出": "Transcription worker exited.",
        "无法定位应用资源": "App resources could not be located.",
        "本地模型未就绪": "The local model is not ready.",
        "worker 忙，不能并行提交判断": "An evaluation is already in progress.",
        "文本或 prompt 无效": "Invalid transcript or alert rule.",
        "worker 输出超出限制": "Model output exceeds the limit.",
        "worker 协议错误": "Model protocol error.",
        "未知错误": "Unknown error.",
        "缺少输出": "Missing model output.",
        "worker 已退出": "Model worker exited.",
        "模型加载超时": "Model loading timed out.",
        "推理超时，已停止 worker": "Evaluation timed out; model worker stopped.",
        "已取消": "Cancelled",
        "判断字段或类型错误": "Invalid evaluation fields or types.",
        "JSON 字段或类型错误": "Invalid JSON fields or types.",
        "无效的判断状态": "Invalid decision.",
        "输出过长": "Output is too long.",
        "打开主面板": "Open main panel",
        "正在恢复麦克风…": "Recovering microphone…",
        "拖动标题移动；选择文字后按 ⌘C 复制": "Drag the title to move; select text and press ⌘C to copy",
        "提醒缺少原话或建议，或原话不是转写子串": "Alert evidence or suggestion is missing, or the quote does not match the transcript.",
        "建议只能是一行": "The suggestion must be a single line.",
        "安静状态必须使用空原话和建议": "A quiet decision must not include a quote or suggestion."
    ]
}

extension DisplayLanguage {
    static let asianStrings: [String: [String]] = [
        "转录正常；上一条判断超出模型容量，已跳过提醒": ["文字起こしは動作中です。前の判定がモデル容量を超えたため、通知をスキップしました。", "전사는 정상 작동 중입니다. 이전 판단이 모델 용량을 초과하여 알림을 건너뛰었습니다."],
        "规则候选索引无效": ["ルール候補の番号が無効です。", "규칙 후보 번호가 잘못되었습니다."],
        "规则候选重复": ["ルール候補が重複しています。", "규칙 후보가 중복되었습니다."],
        "中间判断字段或类型错误": ["中間判定の項目または型が無効です。", "중간 판단 필드 또는 유형이 잘못되었습니다."],
        "中间判断缺少连续原文证据": ["中間判定に連続した原文の根拠がありません。", "중간 판단에 연속된 원문 근거가 없습니다."],

        "提醒语言与设置不符": ["通知の言語が設定と一致しません。", "알림 언어가 설정과 일치하지 않습니다."],
        "提醒设置": ["通知設定", "알림 설정"],
        "Speech Wingman 实验版": ["Speech Wingman プレビュー版", "Speech Wingman 미리보기"],
        "多语言 · 离线": ["多言語 · オフライン", "다국어 · 오프라인"],
        "麦克风": ["マイク", "마이크"],
        "本次判断已处理 %.0f 秒": ["判定中 · %.0f 秒", "판단 중 · %.0f초"],
        "开始监听": ["音声入力を開始", "듣기 시작"],
        "加载中…": ["読み込み中…", "불러오는 중…"],
        "暂停": ["一時停止", "일시 정지"],
        "继续": ["再開", "계속"],
        "停止并清空": ["停止して消去", "중지 및 지우기"],
        "设置": ["設定", "설정"],
        "提醒": ["通知", "알림"],
        "原话：%@": ["原文：%@", "원문: %@"],
        "原话": ["原文", "원문"],
        "关闭": ["閉じる", "닫기"],
        "静音一小时": ["1時間ミュート", "1시간 알림 끄기"],
        "提醒静音至 %@": ["%@ まで通知をミュート", "%@까지 알림 끄기"],
        "取消静音": ["ミュートを解除", "알림 다시 켜기"],
        "当前会话转写": ["セッションの文字起こし", "현재 세션 전사"],
        "手动开始后监听麦克风中的所有人声。未满足提醒条件时保持安静。": ["開始すると、マイクが拾うすべての音声を判定します。ルールに一致した場合のみ通知します。", "시작하면 마이크에 잡히는 모든 음성을 판단합니다. 규칙에 해당할 때만 알립니다."],
        "实时转录中…": ["文字起こし中…", "실시간 전사 중…"],
        "主动导出会话": ["セッションを書き出す", "세션 내보내기"],
        "判断 %.1f 秒": ["判定 %.1f 秒", "판단 %.1f초"],
        "转录定稿后 %.1f 秒完成判断（排队 %.1f 秒）": ["文字起こし確定から判定まで %.1f 秒（待機 %.1f 秒）", "전사 확정 후 판단까지 %.1f초 (대기 %.1f초)"],
        "默认不保存音频。选择“停止并清空”会清空本次转写与提醒。": ["音声は保存されません。「停止して消去」で、このセッションの文字起こしと通知を消去します。", "음성은 저장되지 않습니다. ‘중지 및 지우기’를 선택하면 현재 전사와 알림이 지워집니다."],
        "退出": ["終了", "종료"],
        "本地语音处理": ["デバイス上で音声処理", "기기 내 음성 처리"],
        "多语言自动转录 + Qwen3 4B 文本判断": ["多言語の自動文字起こし＋Qwen3 4B による判定", "다국어 자동 전사 + Qwen3 4B 판단"],
        "英语、中文、日语、韩语和粤语自动识别，可交替使用，无需切换语言。模型已随应用打包，运行不联网。转录持续显示，判断在后台进行。": ["英語、中国語、日本語、韓国語、広東語を自動認識し、言語を切り替えて話せます。モデルはアプリに同梱され、オフラインで動作します。文字起こしを表示しながら、バックグラウンドで判定します。", "영어, 중국어, 일본어, 한국어, 광둥어를 자동 인식하며 언어를 바꿔 가며 말할 수 있습니다. 모델이 앱에 포함되어 오프라인으로 작동합니다. 전사는 계속 표시되며 판단은 백그라운드에서 진행됩니다."],
        "提醒条件": ["通知ルール", "알림 규칙"],
        "每行一条规则，命中任意一条就提醒。每条的例外条件写在同一行。提醒使用设置中选择的语言。": ["1行に1つのルールを入力します。いずれかに一致すると通知します。例外は同じ行に記載してください。通知は選択した言語で表示されます。", "한 줄에 규칙 하나를 입력하세요. 하나라도 해당하면 알립니다. 예외 조건은 같은 줄에 작성하세요. 알림은 선택한 언어로 표시됩니다."],
        "例如：说到 banana 就提醒。\n说汤姆的坏话就提醒，赞扬他不提醒。": ["例：バナナと言ったら通知する。\nトムを悪く言ったら通知するが、褒めた場合は通知しない。", "예: 바나나를 말하면 알림.\n톰을 험담하면 알리되 칭찬하면 알리지 않음."],
        "桌面悬浮按钮": ["デスクトップのフローティングボタン", "바탕 화면 플로팅 버튼"],
        "停止监听": ["音声入力を停止", "듣기 중지"],
        "取消加载": ["読み込みをキャンセル", "불러오기 취소"],
        "正在监听": ["音声入力中", "듣는 중"],
        "等待语音…": ["音声を待機中…", "음성 대기 중…"],
        "点击重试": ["クリックして再試行", "클릭하여 다시 시도"],
        "点击开始": ["クリックして開始", "클릭하여 시작"],
        "拖动空白处移动；点击按钮开始或停止监听": ["余白をドラッグして移動、ボタンをクリックして音声入力を開始・停止", "빈 곳을 드래그하여 이동하고 버튼을 클릭하여 듣기를 시작하거나 중지하세요"],
        "拖动标题或文字区移动；点击按钮开始或停止监听": ["タイトルか本文をドラッグして移動、ボタンをクリックして音声入力を開始・停止", "제목이나 텍스트 영역을 드래그하여 이동하고 버튼을 클릭하여 듣기를 시작하거나 중지하세요"],
        "当前片段未能完成判断，已跳过提醒": ["現在の区間の判定が完了しなかったため、通知をスキップしました。", "현재 구간의 판단을 완료하지 못해 알림을 건너뛰었습니다."],
        "提醒语言与当前发言不符": ["通知の言語が発言と一致しません。", "알림 언어가 발언과 일치하지 않습니다."],
        "敏感度": ["感度", "민감도"],
        "回车新建规则；长句会自动换行。": ["改行で新しいルールを追加します。長い文は自動で折り返します。", "엔터로 새 규칙을 만듭니다. 긴 문장은 자동으로 줄바꿈됩니다."],
        "查看规则示例": ["ルールの例を表示", "규칙 예시 보기"],
        "仅明显命中": ["明確な一致のみ", "명백한 일치만"],
        "明确语义匹配": ["明確な意味・意図の一致", "명확한 의미와 의도 일치"],
        "包括边界情况": ["境界的なケースも含む", "경계 사례 포함"],
        "低：只在表达直接、证据明确时提醒，尽量减少打扰。": ["低：直接的な表現で根拠が明確な場合のみ通知し、中断を最小限にします。", "낮음: 직접적인 표현과 명확한 근거가 있을 때만 알려 방해를 줄입니다."],
        "中：也识别清楚的同义表达和隐含意思；模糊情况保持安静。": ["中：明確な言い換えや含意も認識します。曖昧な場合は通知しません。", "중간: 명확한 유사 표현과 함축된 의미도 인식하며 모호하면 알리지 않습니다."],
        "高：有相关证据的暗示和可能命中也提醒，优先减少漏报。": ["高：根拠のある暗示や一致の可能性も通知し、見逃しを減らします。", "높음: 근거가 있는 암시나 일치 가능성도 알려 누락을 줄입니다."],
        "所有档位都遵守规则中的例外条件。高敏感度可能增加误报，也不能保证不漏报。": ["すべての感度で例外条件を尊重します。高感度では誤通知が増える場合があり、見逃しを完全には防げません。", "모든 단계에서 예외 조건을 따릅니다. 높은 민감도는 오탐을 늘릴 수 있으며 누락을 완전히 막지는 못합니다."],
        "低": ["低", "낮음"],
        "中": ["中", "중간"],
        "高": ["高", "높음"],
        "%d / 4000 字": ["%d / 4000 文字", "%d / 4000자"],
        "保存并应用": ["保存して適用", "저장 및 적용"],
        "应用新条件时会取消旧判断，并从新的音频片段开始。麦克风中的其他人声也会参与判断。": ["新しいルールを適用すると、保留中の判定を取り消し、新しい音声区間から開始します。マイクが拾う他の人の声も判定対象です。", "새 규칙을 적용하면 이전 판단이 취소되고 새 음성 구간부터 시작합니다. 마이크에 잡히는 다른 사람의 음성도 판단합니다."],
        "Speech Wingman 提醒": ["Speech Wingman 通知", "Speech Wingman 알림"],
        "界面语言": ["表示・通知の言語", "표시 및 알림 언어"],
        "设置界面与生成提醒的语言；转录与引用保留原文。": ["画面と生成される通知の言語を設定します。文字起こしと引用は原文のままです。", "화면과 생성되는 알림의 언어를 설정합니다. 전사와 인용은 원문을 유지합니다."],
        "已停止": ["停止中", "중지됨"],
        "音频设备已改变，请继续监听": ["音声デバイスが変更されました。音声入力を再開してください。", "오디오 장치가 변경되었습니다. 듣기를 재개하세요."],
        "请填写最多 4000 字的提醒条件": ["4000文字以内で通知ルールを入力してください。", "알림 규칙을 4000자 이내로 입력하세요."],
        "正在加载本地多语言转录和文本判断…": ["デバイス上の文字起こしと判定を読み込み中…", "기기 내 전사 및 판단 모델을 불러오는 중…"],
        "请在系统设置中允许麦克风访问": ["システム設定でマイクへのアクセスを許可してください。", "시스템 설정에서 마이크 접근을 허용하세요."],
        "正在本机监听 · 多语言自动识别": ["デバイス上で音声入力中 · 多言語を自動認識", "기기에서 듣는 중 · 다국어 자동 인식"],
        "已暂停": ["一時停止中", "일시 정지됨"],
        "提醒条件已保存": ["通知ルールを保存しました", "알림 규칙 저장됨"],
        "提醒条件已保存；已暂停": ["通知ルールを保存しました。一時停止中です", "알림 규칙 저장됨; 일시 정지 상태"],
        "判断积压过多，已停止监听；转录已保留，请继续重试": ["判定待ちが多すぎるため音声入力を停止しました。文字起こしは保持されています。再開してください。", "판단 대기가 너무 많아 듣기를 중지했습니다. 전사는 보존되었습니다. 다시 시작하세요."],
        "单段转录超出判断容量": ["文字起こし区間が判定容量を超えています。", "전사 구간이 판단 용량을 초과했습니다."],
        "转录正常；上一条判断无效，已跳过提醒": ["文字起こしは動作中です。無効な判定の通知をスキップしました。", "전사는 정상 작동 중입니다. 잘못된 판단의 알림을 건너뛰었습니다."],
        "麦克风音频格式不可用": ["マイクの音声形式を利用できません。", "마이크 오디오 형식을 사용할 수 없습니다."],
        "多语言转录加载超时": ["多言語の文字起こしの読み込みがタイムアウトしました。", "다국어 전사 로딩 시간이 초과되었습니다."],
        "ASR 未就绪或音频块无效": ["文字起こしの準備ができていないか、音声データが無効です。", "전사가 준비되지 않았거나 오디오 데이터가 잘못되었습니다."],
        "ASR 跟不上收音，已暂停；请继续重试": ["文字起こしが追いつかないため一時停止しました。再開してください。", "전사가 음성 입력을 따라가지 못해 일시 정지했습니다. 재개하세요."],
        "ASR 未就绪": ["文字起こしの準備ができていません。", "전사가 준비되지 않았습니다."],
        "ASR 收尾超时": ["文字起こしの終了処理がタイムアウトしました。", "전사 마무리 시간이 초과되었습니다."],
        "ASR 已停止": ["文字起こしが停止しました。", "전사가 중지되었습니다."],
        "ASR 音频传输失败": ["音声の転送に失敗しました。", "오디오 전송에 실패했습니다."],
        "ASR 输出超出限制": ["文字起こしの出力が上限を超えました。", "전사 출력이 제한을 초과했습니다."],
        "ASR 协议错误": ["文字起こしの通信エラーです。", "전사 통신 오류입니다."],
        "ASR 转录格式错误": ["文字起こしの形式が無効です。", "전사 형식이 잘못되었습니다."],
        "ASR 失败": ["文字起こしに失敗しました。", "전사에 실패했습니다."],
        "未知 ASR 消息": ["不明な文字起こしメッセージです。", "알 수 없는 전사 메시지입니다."],
        "多语言转录进程已退出": ["文字起こし処理が終了しました。", "전사 작업이 종료되었습니다."],
        "无法定位应用资源": ["アプリのリソースが見つかりません。", "앱 리소스를 찾을 수 없습니다."],
        "本地模型未就绪": ["ローカルモデルの準備ができていません。", "로컬 모델이 준비되지 않았습니다."],
        "worker 忙，不能并行提交判断": ["すでに判定を実行中です。", "이미 판단이 진행 중입니다."],
        "文本或 prompt 无效": ["文字起こしまたは通知ルールが無効です。", "전사 또는 알림 규칙이 잘못되었습니다."],
        "worker 输出超出限制": ["モデルの出力が上限を超えました。", "모델 출력이 제한을 초과했습니다."],
        "worker 协议错误": ["モデルの通信エラーです。", "모델 통신 오류입니다."],
        "未知错误": ["不明なエラーです。", "알 수 없는 오류입니다."],
        "缺少输出": ["モデルの出力がありません。", "모델 출력이 없습니다."],
        "worker 已退出": ["モデル処理が終了しました。", "모델 작업이 종료되었습니다."],
        "模型加载超时": ["モデルの読み込みがタイムアウトしました。", "모델 로딩 시간이 초과되었습니다."],
        "推理超时，已停止 worker": ["判定がタイムアウトし、モデル処理を停止しました。", "판단 시간이 초과되어 모델 작업을 중지했습니다."],
        "已取消": ["キャンセル済み", "취소됨"],
        "判断字段或类型错误": ["判定の項目または型が無効です。", "판단 필드 또는 유형이 잘못되었습니다."],
        "JSON 字段或类型错误": ["JSONの項目または型が無効です。", "JSON 필드 또는 유형이 잘못되었습니다."],
        "无效的判断状态": ["判定状態が無効です。", "판단 상태가 잘못되었습니다."],
        "输出过长": ["出力が長すぎます。", "출력이 너무 깁니다."],
        "打开主面板": ["メインパネルを開く", "메인 패널 열기"],
        "正在恢复麦克风…": ["マイクを復旧中…", "마이크 복구 중…"],
        "拖动标题移动；选择文字后按 ⌘C 复制": ["タイトルをドラッグして移動。文字を選択して ⌘C でコピー", "제목을 드래그하여 이동하고 텍스트 선택 후 ⌘C로 복사하세요"],
        "提醒缺少原话或建议，或原话不是转写子串": ["通知の引用や提案がないか、引用が文字起こしと一致しません。", "알림의 인용이나 제안이 없거나 인용이 전사와 일치하지 않습니다."],
        "建议只能是一行": ["提案は1行で記述してください。", "제안은 한 줄이어야 합니다."],
        "安静状态必须使用空原话和建议": ["通知しない場合は引用と提案を空にしてください。", "알림이 없을 때는 인용과 제안이 비어 있어야 합니다."],
        "导出失败：": ["書き出しに失敗：", "내보내기 실패: "],
        "模型输出未通过校验：": ["モデル出力の検証に失敗：", "모델 출력 검증 실패: "],
        "本地模型错误：": ["ローカルモデルエラー：", "로컬 모델 오류: "],
        "无法启动本地模型 worker：": ["ローカルモデルを起動できません：", "로컬 모델을 시작할 수 없습니다: "]
    ]
}
