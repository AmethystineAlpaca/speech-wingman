import AppKit
import AVFoundation
import Combine
import WingmanCore

@MainActor
final class SessionController: ObservableObject {
    enum State: Equatable { case idle, loading, listening, paused, failed }
    @Published var language: DisplayLanguage {
        didSet {
            guard language != oldValue else { return }
            language.save(to: preferences)
            if DisplayLanguage.allCases.contains(where: { $0.defaultRule == prompt }) {
                prompt = language.defaultRule
                configuration.prompt = prompt
                preferences.set(prompt, forKey: "alertPrompt")
            }
            configuration.responseLanguage = language
            configuration.version += 1
            configurations.append(configuration)
            activeAlertLanguage = language
            dismissAlert()
        }
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
    private var nextBatchLimit = CurrentSpeechWindow.maximumPending
    private var continuation = DeferredSpeechContinuation()
    private var evaluations: [StatementEvaluationRecord] = []
    private var configurations: [SessionConfiguration] = []
    private var configuration: SessionConfiguration
    private var epoch = UUID()
    private var sessionID = UUID()
    private var task: Task<Void, Never>?
    private var rollingDebounce: Task<Void, Never>?
    private var recovery: Task<Void, Never>?
    private var ignoreAudioChangesUntil = Date.distantPast
    private var segmentIDs: [Int: UUID] = [:]
    private var alertedSegments: Set<UUID> = []
    private var rollingEntry: TranscriptEntry?
    private var observations: [NSObjectProtocol] = []
    private var lastFinalizedSegment = -1
    private var shuttingDown = false
    private var levelUpdatedAt = Date.distantPast

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        let initialLanguage = DisplayLanguage.load(from: preferences)
        language = initialLanguage
        floatingControlVisible = preferences.object(forKey: "floatingControlVisible") as? Bool ?? true
        var savedPrompt = preferences.string(forKey: "alertPrompt") ?? initialLanguage.defaultRule
        if DisplayLanguage.allCases.contains(where: { $0.defaultRule == savedPrompt }) { savedPrompt = initialLanguage.defaultRule }
        let savedSensitivity = Sensitivity(rawValue: preferences.string(forKey: "sensitivity") ?? "medium") ?? .medium
        prompt = savedPrompt; sensitivity = savedSensitivity
        configuration = SessionConfiguration(prompt: savedPrompt, sensitivity: savedSensitivity, responseLanguage: initialLanguage)
        observations.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.pause() }
        })
        observations.append(NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == .listening else { return }
                self.recoverAudio()
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
        configuration = SessionConfiguration(prompt: prompt, sensitivity: sensitivity, version: configuration.version + 1, responseLanguage: language)
        preferences.set(prompt, forKey: "alertPrompt")
        preferences.set(sensitivity.rawValue, forKey: "sensitivity")
        preferences.removeObject(forKey: "localModel")
    }

    func start() async {
        guard !shuttingDown, state == .idle || state == .failed, validSettings() else { return }
        saveSettings()
        transcript.removeAll(); alerts.removeAll(); evaluations.removeAll(); configurations = [configuration]; dismissAlert()
        failures = 0; elapsed = 0; queueDelay = 0; resultDelay = 0; gate.resetSession(); sessionID = UUID()
        await beginListening()
    }
    private func beginListening() async {
        epoch = UUID(); let current = epoch
        state = .loading; status = "正在加载本地多语言转录和文本判断…"
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
            try startCapture(current: current)
            status = "正在本机监听 · 多语言自动识别"
        } catch {
            guard current == epoch else { return }
            fail(error.localizedDescription)
        }
    }

    private func startCapture(current: UUID) throws {
        ignoreAudioChangesUntil = Date().addingTimeInterval(1)
        try capture.start { [weak self] samples in
            Task { @MainActor in
                guard let self, self.epoch == current, self.state == .listening, self.recovery == nil else { return }
                let now = Date()
                if now.timeIntervalSince(self.levelUpdatedAt) >= 0.1 {
                    self.inputLevel = sqrt(samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(max(1, samples.count)))
                    self.levelUpdatedAt = now
                }
                do { try self.speech.append(samples) } catch { self.fail(error.localizedDescription) }
            }
        }
    }

    private func recoverAudio() {
        guard recovery == nil, Date() >= ignoreAudioChangesUntil else { return }
        let current = epoch
        status = "正在恢复麦克风…"
        recovery = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled, self.epoch == current, self.state == .listening else { return }
            do {
                try self.startCapture(current: current)
                self.status = "正在本机监听 · 多语言自动识别"
                self.recovery = nil
            } catch {
                self.recovery = nil
                self.fail(error.localizedDescription)
            }
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
        transcript.removeAll(); alerts.removeAll(); evaluations.removeAll(); configurations = [configuration]; dismissAlert()
        shuttingDown = true
        await backend.shutdown()
        shuttingDown = false
    }
    func applySettings() async {
        guard state != .loading, validSettings() else { return }
        let wasListening = state == .listening
        if wasListening { await pause() }
        guard !wasListening || state == .paused else { return }
        saveSettings(); configurations.append(configuration); dismissAlert()
        if wasListening { await resume() }
        else { status = "提醒条件已保存\(state == .paused ? "；已暂停" : "")" }
    }
    private func invalidate() {
        epoch = UUID(); recovery?.cancel(); recovery = nil
        rollingDebounce?.cancel(); rollingDebounce = nil; rollingEntry = nil
        segmentIDs.removeAll(); alertedSegments.removeAll()
        capture.stop(); speech.stop()
        task?.cancel(); task = nil
        for record in evaluations where record.status == .pending || record.status == .evaluating {
            updateEvaluation(record.id, status: .cancelled)
        }
        for index in transcript.indices where transcript[index].evaluationStatus == .pending {
            transcript[index].evaluationStatus = .cancelled
        }
        pending.reset(); nextBatchLimit = CurrentSpeechWindow.maximumPending; continuation.reset(); processing = false; processingStartedAt = nil; inputLevel = 0; preview = ""
    }
    private func fail(_ message: String) {
        guard state != .failed else { return }
        state = .failed; status = message; failures += 1
        invalidate()
        shuttingDown = true
        Task { await backend.shutdown(); shuttingDown = false }
    }

    private func receiveText(_ text: String, segment: Int, final: Bool, seconds: Double) {
        guard segment > lastFinalizedSegment else { return }
        segmentIDs = segmentIDs.filter { $0.key >= segment - 10 }
        alertedSegments.formIntersection(Set(segmentIDs.values))
        let id = segmentIDs[segment] ?? UUID()
        segmentIDs[segment] = id
        rollingDebounce?.cancel()
        if !final {
            preview = String(text.suffix(CurrentSpeechWindow.maximumCharacters))
            guard !preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !alertedSegments.contains(id) else { return }
            let current = epoch
            rollingDebounce = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, self.epoch == current, !Task.isCancelled, self.task == nil, !self.alertedSegments.contains(id) else { return }
                self.rollingEntry = TranscriptEntry(id: id, date: Date(), text: self.preview,
                    decision: .deferDecision, configurationVersion: self.configuration.version, isFinal: false)
                self.pump()
            }
            return
        }
        lastFinalizedSegment = segment; preview = ""; rollingEntry = nil
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let entry = TranscriptEntry(id: id, date: Date(), text: text, decision: .deferDecision,
                                    configurationVersion: configuration.version,
                                    evaluationStatus: alertedSegments.contains(id) ? .evaluated : .pending)
        transcript.append(entry)
        if transcript.count > 1000 { transcript.removeFirst(transcript.count - 1000) }
        // The ASR endpoint already represents 550 ms of silence; do not wait again.
        if !alertedSegments.contains(id) { enqueue([entry]) }
    }

    private func enqueue(_ segments: [TranscriptEntry]) {
        guard let last = segments.last, segments.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return }
        let text = segments.map(\.text).joined(separator: "\n")
        let entry = TranscriptEntry(id: last.id, date: last.date, text: text, decision: .deferDecision,
                                    configurationVersion: last.configurationVersion)
        evaluations.append(StatementEvaluationRecord(id: entry.id, segmentIDs: segments.map(\.id),
                                                      text: text, configurationVersion: entry.configurationVersion))
        if evaluations.count > 1000 { evaluations.removeFirst(evaluations.count - 1000) }
        for skipped in pending.append(entry) { updateEvaluation(skipped.id, status: .overflow) }
        pump()
    }

    private func updateEvaluation(_ id: UUID, status: EvaluationStatus, decision: Decision? = nil,
                                  disposition: String? = nil, errorMessage: String? = nil) {
        guard let index = evaluations.firstIndex(where: { $0.id == id }) else { return }
        evaluations[index].status = status
        evaluations[index].decision = decision
        evaluations[index].alertDisposition = disposition
        evaluations[index].errorMessage = errorMessage
        if status == .evaluating { evaluations[index].startedAt = Date() }
        if status != .pending && status != .evaluating { evaluations[index].completedAt = Date() }
        let ids = Set(evaluations[index].segmentIDs)
        transcript = transcript.map { entry in
            guard ids.contains(entry.id) else { return entry }
            return TranscriptEntry(id: entry.id, date: entry.date, text: entry.text,
                                   decision: decision ?? entry.decision, configurationVersion: entry.configurationVersion,
                                   evaluationStatus: status)
        }
    }

    private func pump() {
        guard task == nil, state == .listening else { return }
        for expired in pending.removeExpired(now: Date()) { updateEvaluation(expired.id, status: .expired) }
        let batch = pending.takeBatch(now: Date(), limit: nextBatchLimit)
        nextBatchLimit = CurrentSpeechWindow.maximumPending
        guard let entry = batch.last ?? rollingEntry else { return }
        rollingEntry = nil
        let eventIDs = batch.isEmpty ? [entry.id] : batch.map(\.id)
        let input = batch.isEmpty ? entry.text : batch.map(\.text).joined(separator: "\n")
        let merged = TranscriptEntry(id: entry.id, date: entry.date, text: input,
            decision: entry.decision, configurationVersion: entry.configurationVersion)
        for id in eventIDs { updateEvaluation(id, status: .evaluating) }
        let continued = batch.isEmpty ? (text: merged.text, continuedFrom: Optional<UUID>.none) : continuation.input(for: merged)
        let text = continued.text, eventID = entry.id
        for index in evaluations.indices where eventIDs.contains(evaluations[index].id) {
            evaluations[index].inputText = text
            evaluations[index].continuedFromID = continued.continuedFrom
        }
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
                let evaluation = try await self.evaluateSerial(text: text, configuration: config)
                guard self.epoch == current, self.state == .listening, !Task.isCancelled else { return }
                let result = evaluation.result
                if !batch.isEmpty { self.continuation.remember(merged, decision: result.decision) }
                if let index = self.evaluations.firstIndex(where: { $0.id == eventID }) {
                    self.evaluations[index].matchedRuleIndex = evaluation.matchedRuleIndex
                }
                self.elapsed = evaluation.elapsedSeconds
                self.resultDelay = Date().timeIntervalSince(entry.date)
                let fresh = CurrentSpeechWindow.isFresh(entry, now: Date()) && !eventIDs.contains(where: { self.alertedSegments.contains($0) })
                let admitted = config.responseLanguage == self.language && fresh && self.gate.admit(result, eventID: eventID, isFinal: true, now: Date())
                for id in eventIDs { self.updateEvaluation(id, status: .evaluated, decision: result.decision,
                                      disposition: result.decision == .alert ? (admitted ? "presented" : (fresh ? "muted_or_limited" : "expired")) : nil,
                                      errorMessage: evaluation.validationErrors.isEmpty ? nil : evaluation.validationErrors.joined(separator: "; ")) }
                if admitted {
                    self.alertedSegments.formUnion(eventIDs)
                    for removed in self.pending.remove(ids: Set(eventIDs)) {
                        self.updateEvaluation(removed.id, status: .evaluated, decision: .alert, disposition: "preview_presented")
                    }
                    let alert = AlertEntry(id: eventID, date: Date(), quote: result.quote, suggestion: result.suggestion, configurationVersion: config.version)
                    self.alerts.append(alert); self.activeAlert = alert
                    if self.alerts.count > 1000 { self.alerts.removeFirst(self.alerts.count - 1000) }
                    self.activeAlertLanguage = self.language
                    self.presenter.present(alert, language: self.activeAlertLanguage, dismiss: { [weak self] in self?.dismissAlert() }, mute: { [weak self] in self?.mute() })
                }
                if result.decision == .inconclusive {
                    self.failures += 1
                    self.status = "当前片段未能完成判断，已跳过提醒"
                } else { self.status = "正在本机监听 · 多语言自动识别" }
            } catch {
                guard self.epoch == current, !Task.isCancelled else { return }
                if error.isContextCapacityExceeded, batch.count > 1 {
                    self.nextBatchLimit = batch.count - 1
                    for id in eventIDs { self.updateEvaluation(id, status: .pending) }
                    for skipped in self.pending.prepend(batch) { self.updateEvaluation(skipped.id, status: .overflow) }
                    return // defer immediately pumps the largest remaining prefix; no timer.
                }
                self.failures += 1
                for id in eventIDs { self.updateEvaluation(id, status: .invalid, errorMessage: error.localizedDescription) }
                if error.isContextCapacityExceeded {
                    self.status = "转录正常；上一条判断超出模型容量，已跳过提醒"
                    return
                }
                if case WingmanError.invalidResult = error {
                    self.status = "转录正常；上一条判断无效，已跳过提醒"
                } else { self.fail(error.localizedDescription); return }
            }
        }
    }

    // Busy is backpressure, not a worker failure. Retain this exact input and the
    // single scheduling slot while retrying; queued finals remain bounded separately.
    private func evaluateSerial(text: String, configuration: SessionConfiguration) async throws -> Evaluation {
        while true {
            try Task.checkCancellation()
            do { return try await backend.evaluate(text: text, configuration: configuration, context: []) }
            catch where error.isWorkerBusy { try await Task.sleep(for: .milliseconds(300)) }
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
        struct Export: Encodable {
            let sensitivityMappingVersion = SessionConfiguration.sensitivityMappingVersion
            let sessionID: UUID; let transcript: [TranscriptEntry]; let alerts: [AlertEntry]
            let configurations: [SessionConfiguration]; let evaluations: [StatementEvaluationRecord]
        }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(Export(sessionID: sessionID, transcript: transcript, alerts: alerts, configurations: configurations, evaluations: evaluations)).write(to: url, options: .atomic)
        } catch { status = "导出失败：\(error.localizedDescription)" }
    }
}
