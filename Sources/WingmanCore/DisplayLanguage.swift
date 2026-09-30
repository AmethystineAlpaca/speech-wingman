import Foundation

/// Display-only preference. It is deliberately absent from the ASR and model configuration.
public enum DisplayLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case chinese = "zh-Hans"
    public static let preferenceKey = "displayLanguage"
    public static func load(from defaults: UserDefaults = .standard) -> Self {
        defaults.string(forKey: preferenceKey).flatMap(Self.init(rawValue:)) ?? .english
    }
    public func save(to defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: Self.preferenceKey) }
    public var locale: Locale { Locale(identifier: rawValue) }
    public var name: String { self == .english ? "English" : "中文" }
    public func text(_ key: String) -> String {
        guard self == .english else { return key }
        if let translated = Self.englishStrings[key] { return translated }
        // Keep paths and OS/native diagnostics intact while translating our error wrappers.
        for (prefix, translated) in Self.errorPrefixes where key.hasPrefix(prefix) {
            return translated + text(String(key.dropFirst(prefix.count)))
        }
        if key.hasPrefix("缺少 "), let start = key.range(of: "（"), let end = key.range(of: "）") {
            return "Missing local model resource (" + key[start.upperBound..<end.lowerBound] + "). Reinstall the app or run Scripts/setup-model.py and rebuild."
        }
        return key
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
        "提醒设置": "Alert settings",
        "Speech Wingman 实验版": "Speech Wingman Preview",
        "中英双语 · 离线": "Chinese & English · Offline",
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
        "默认不保存音频。停止后清空本次转写与提醒。": "Audio is not saved. Stopping clears this session’s transcript and alerts.",
        "退出": "Quit",
        "本地语音处理": "On-device speech processing",
        "中英自动 ASR + Qwen3 4B 文本判断": "Automatic Chinese & English ASR + Qwen3 4B evaluation",
        "中文、英文和混合发言自动识别，无需切换语言。模型已随应用打包，运行不联网。转录持续显示，判断在后台进行。": "Chinese, English, and mixed speech are recognized automatically. Models are bundled for offline use. Transcripts update as you speak; evaluation runs in the background.",
        "提醒条件": "Alert rule",
        "用自然语言说明什么时候提醒，以及哪些情况应保持安静。一次启用一段条件。": "Describe when to alert and when to stay quiet, in either language. One rule is active at a time.",
        "敏感度": "Sensitivity",
        "低": "Low",
        "中": "Medium",
        "高": "High",
        "%d / 4000 字": "%d / 4000 characters",
        "保存并应用": "Save and apply",
        "应用新条件时会取消旧判断，并从新的音频片段开始。麦克风中的其他人声也会参与判断。": "Applying a new rule cancels pending evaluations and starts a new audio segment. Other voices picked up by the microphone are also evaluated.",
        "Speech Wingman 提醒": "Speech Wingman Alert",
        "界面语言": "Display language",
        "只改变界面显示；录音始终自动识别中文、英文和中英混合。": "Changes the interface only. Speech recognition always supports Chinese, English, and mixed speech.",
        "已停止": "Stopped",
        "音频设备已改变，请继续监听": "Audio device changed. Resume listening to continue.",
        "请填写最多 4000 字的提醒条件": "Enter an alert rule of up to 4,000 characters.",
        "正在加载本地双语转录和文本判断…": "Loading on-device transcription and evaluation…",
        "请在系统设置中允许麦克风访问": "Allow microphone access in System Settings.",
        "正在本机监听 · 中英自动识别": "Listening on device · Automatic Chinese & English",
        "已暂停": "Paused",
        "提醒条件已保存": "Alert rule saved",
        "提醒条件已保存；已暂停": "Alert rule saved; listening is paused",
        "判断积压过多，已停止监听；转录已保留，请继续重试": "Evaluation backlog is full. Listening stopped; transcript retained. Start again to retry.",
        "单段转录超出判断容量": "Transcript segment exceeds evaluation capacity.",
        "转录正常；上一条判断无效，已跳过提醒": "Transcription is running. An invalid evaluation was skipped.",
        "麦克风音频格式不可用": "Microphone audio format is unavailable.",
        "中英双语 ASR 加载超时": "Chinese & English transcription took too long to load.",
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
        "中英双语 ASR 已退出": "Transcription worker exited.",
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
        "提醒缺少原话或建议，或原话不是转写子串": "Alert evidence or suggestion is missing, or the quote does not match the transcript.",
        "建议只能是一行": "The suggestion must be a single line.",
        "安静状态必须使用空原话和建议": "A quiet decision must not include a quote or suggestion."
    ]
}
