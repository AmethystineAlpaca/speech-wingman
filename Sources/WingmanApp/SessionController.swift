import AppKit
import AVFoundation
import Combine
import WingmanCore

@MainActor
final class SessionController: ObservableObject {
    enum State: Equatable { case idle, loading, listening, paused, failed }
    @Published var language: DisplayLanguage {
        didSet { language.save(to: preferences) }
    }
    func t(_ key: String) -> String { language.text(key) }
    @Published var floatingControlVisible: Bool {
        didSet { preferences.set(floatingControlVisible, forKey: "floatingControlVisible") }
    }
    @Published var state: State = .idle
    @Published var status = "已停止"
    @Published var transcript: [TranscriptEntry] = []
    @Published var alerts: [AlertEntry] = []
    @Published private(set) var activeAlertLanguage: DisplayLanguage = .english
    @Published var activeAlert: AlertEntry?
    @Published var preview = ""
    @Published var processing = false
    @Published var failures = 0
    @Published var elapsed: Double = 0
    @Published var queueDelay: Double = 0
    @Published var resultDelay: Double = 0
    @Published var processingStartedAt: Date?
    @Published var inputLevel: Float = 0
    @Published var mutedUntil: Date?
    @Published var prompt: String
    @Published var sensitivity: Sensitivity
    private let preferences: UserDefaults
    private let backend = LocalTextBackend()
    private let speech = SpeechStream()
    private let capture = AudioCapture()
    private let presenter = AlertPresenter()
    private var gate = AlertGate()
    private var pending = CurrentSpeechWindow()
    private var configuration: SessionConfiguration
    private var epoch = UUID()
    private var sessionID = UUID()
    private var task: Task<Void, Never>?
    private var debounce: Task<Void, Never>?
    private var observations: [NSObjectProtocol] = []
    private var lastFinalizedSegment = -1
    private var shuttingDown = false
    private var levelUpdatedAt = Date.distantPast

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        language = DisplayLanguage.load(from: preferences)
        floatingControlVisible = preferences.object(forKey: "floatingControlVisible") as? Bool ?? true
        let savedPrompt = preferences.string(forKey: "alertPrompt") ?? "当当前发言作出强确定性承诺，但当前发言缺少明确截止时间或交付范围时提醒。否定自己能保证、愿望和条件完整的承诺不提醒。"
        let savedSensitivity = Sensitivity(rawValue: preferences.string(forKey: "sensitivity") ?? "medium") ?? .medium
        prompt = savedPrompt; sensitivity = savedSensitivity
        configuration = SessionConfiguration(prompt: savedPrompt, sensitivity: savedSensitivity)
        observations.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.pause() }
        })
        observations.append(NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == .listening else { return }
                await self.pause(); self.status = "音频设备已改变，请继续监听"
            }
        })
    }

    private func validSettings() -> Bool {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, prompt.count <= 4_000 else {
            status = "请填写最多 4000 字的提醒条件"; return false
        }
        return true
    }
    private func saveSettings() {
        configuration = SessionConfiguration(prompt: prompt, sensitivity: sensitivity, version: configuration.version + 1)
        preferences.set(prompt, forKey: "alertPrompt")
        preferences.set(sensitivity.rawValue, forKey: "sensitivity")
        preferences.removeObject(forKey: "localModel")
    }

    func start() async {
        guard !shuttingDown, state == .idle || state == .failed, validSettings() else { return }
        saveSettings()
        transcript.removeAll(); alerts.removeAll(); dismissAlert()
        failures = 0; elapsed = 0; queueDelay = 0; resultDelay = 0; gate.resetSession(); sessionID = UUID()
        await beginListening()
    }
    private func beginListening() async {
        epoch = UUID(); let current = epoch
        state = .loading; status = "正在加载本地双语转录和文本判断…"
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            guard current == epoch else { return }
            state = .failed; status = "请在系统设置中允许麦克风访问"; return
        }
        guard current == epoch else { return }
        do {
            let paths = try BackendPaths.bundled()
            try await backend.load(paths: paths)
            guard current == epoch else { return }
            let resources = paths.worker.deletingLastPathComponent()
            try await speech.start(worker: resources.appendingPathComponent("asr-worker"), models: resources.appendingPathComponent("Models"),
                onText: { [weak self] text, segment, final, seconds in
                    guard let self, self.epoch == current, self.state == .listening else { return }
                    self.receiveText(text, segment: segment, final: final, seconds: seconds)
                }, onFailure: { [weak self] message in
                    guard let self, self.epoch == current else { return }
                    self.fail(message)
                })
            guard current == epoch else { return }
            lastFinalizedSegment = -1; preview = ""
            state = .listening
            try capture.start { [weak self] samples in
                Task { @MainActor in
                    guard let self, self.epoch == current, self.state == .listening else { return }
                    let now = Date()
                    if now.timeIntervalSince(self.levelUpdatedAt) >= 0.1 {
                        self.inputLevel = sqrt(samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(max(1, samples.count)))
                        self.levelUpdatedAt = now
                    }
                    do { try self.speech.append(samples) } catch { self.fail(error.localizedDescription) }
                }
            }
            status = "正在本机监听 · 中英自动识别"
        } catch {
            guard current == epoch else { return }
            fail(error.localizedDescription)
        }
    }

    func pause() async {
        guard state == .listening else { return }
        state = .paused; status = "已暂停"
        invalidate()
        shuttingDown = true
        await backend.shutdown()
        shuttingDown = false
    }
    func resume() async {
        guard !shuttingDown, state == .paused else { return }
        await beginListening()
    }
    func stop() async {
        state = .idle; status = "已停止"
        invalidate()
        transcript.removeAll(); alerts.removeAll(); dismissAlert()
        shuttingDown = true
        await backend.shutdown()
        shuttingDown = false
    }
    func applySettings() async {
        guard state != .loading, validSettings() else { return }
        let wasListening = state == .listening
        if wasListening { await pause() }
        guard !wasListening || state == .paused else { return }
        saveSettings(); dismissAlert()
        if wasListening { await resume() }
        else { status = "提醒条件已保存\(state == .paused ? "；已暂停" : "")" }
    }
    private func invalidate() {
        epoch = UUID(); capture.stop(); speech.stop()
        task?.cancel(); task = nil; debounce?.cancel(); debounce = nil
        pending.reset(); processing = false; processingStartedAt = nil; inputLevel = 0; preview = ""
    }
    private func fail(_ message: String) {
        state = .failed; status = message; failures += 1
        invalidate()
        shuttingDown = true
        Task { await backend.shutdown(); shuttingDown = false }
    }

    private func receiveText(_ text: String, segment: Int, final: Bool, seconds: Double) {
        guard segment > lastFinalizedSegment else { return }
        if !final { preview = text; return }
        lastFinalizedSegment = segment; preview = ""
        let entry = TranscriptEntry(id: UUID(), date: Date(), text: text, decision: .deferDecision, configurationVersion: configuration.version)
        // ASR text is displayed immediately, independently of classification or classifier errors.
        task?.cancel() // A newer final supersedes any remaining rules for the old segment.
        transcript.append(entry); pending.append(entry)
        if transcript.count > 1000 { transcript.removeFirst(transcript.count - 1000) }
        debounce?.cancel()
        let current = epoch
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self, self.epoch == current, !Task.isCancelled else { return }
            self.debounce = nil; self.pump()
        }
    }

    private func pump() {
        guard task == nil, state == .listening, let entry = pending.take(now: Date()) else { return }
        let text = entry.text, eventID = entry.id
        let current = epoch, config = configuration, started = Date()
        queueDelay = started.timeIntervalSince(entry.date)
        processing = true; processingStartedAt = started
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.epoch == current {
                    self.task = nil; self.processing = false; self.processingStartedAt = nil
                    self.pump()
                }
            }
            do {
                let evaluation = try await self.backend.evaluate(text: text, configuration: config, context: [])
                guard self.epoch == current, self.state == .listening, !Task.isCancelled else { return }
                let result = evaluation.result
                self.elapsed = evaluation.elapsedSeconds
                self.resultDelay = Date().timeIntervalSince(entry.date)
                self.transcript = self.transcript.map { entry in
                    guard entry.id == eventID else { return entry }
                    return TranscriptEntry(id: entry.id, date: entry.date, text: entry.text, decision: result.decision, configurationVersion: entry.configurationVersion)
                }
                if self.pending.canPresent(entry, now: Date()) && self.gate.admit(result, eventID: eventID, isFinal: true, now: Date()) {
                    let alert = AlertEntry(id: eventID, date: Date(), quote: result.quote, suggestion: result.suggestion, configurationVersion: config.version)
                    self.alerts.append(alert); self.activeAlert = alert
                    if self.alerts.count > 1000 { self.alerts.removeFirst(self.alerts.count - 1000) }
                    self.activeAlertLanguage = SpeechLanguage.detect(text).displayLanguage
                    self.presenter.present(alert, language: self.activeAlertLanguage, dismiss: { [weak self] in self?.dismissAlert() }, mute: { [weak self] in self?.mute() })
                }
                if result.decision == .inconclusive {
                    self.failures += 1
                    self.status = "当前片段未能完成判断，已跳过提醒"
                } else { self.status = "正在本机监听 · 中英自动识别" }
            } catch {
                guard self.epoch == current, !Task.isCancelled else { return }
                self.failures += 1
                if case WingmanError.invalidResult = error {
                    self.status = "转录正常；上一条判断无效，已跳过提醒"
                } else { self.fail(error.localizedDescription); return }
            }
        }
    }

    /// The desktop button stops capture without deleting the session; a second click resumes.
    func toggleListening() async {
        guard !shuttingDown else { return }
        switch state {
        case .idle, .failed: await start()
        case .paused: await resume()
        case .listening: await pause()
        case .loading: await stop()
        }
    }

    func mute() { mutedUntil = Date().addingTimeInterval(3600); gate.mutedUntil = mutedUntil; dismissAlert() }
    func dismissAlert() { activeAlert = nil; presenter.close() }
    func unmute() { mutedUntil = nil; gate.mutedUntil = nil }
    func export() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "speech-wingman-session.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        struct Export: Encodable { let sessionID: UUID; let transcript: [TranscriptEntry]; let alerts: [AlertEntry] }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(Export(sessionID: sessionID, transcript: transcript, alerts: alerts)).write(to: url, options: .atomic)
        } catch { status = "导出失败：\(error.localizedDescription)" }
    }
}
