import Foundation
import Darwin

public struct BackendPaths: Sendable {
    public let worker: URL
    public let model: URL
    public init(worker: URL, model: URL) {
        self.worker = worker; self.model = model
    }
    public static func bundled(model: LocalModel = .defaultModel) throws -> BackendPaths {
        guard let resources = Bundle.main.resourceURL else {
            throw WingmanError.unavailable("无法定位应用资源")
        }
        return try resolve(resources: resources, model: model)
    }
    public static func resolve(resources: URL, model: LocalModel = .defaultModel) throws -> BackendPaths {
        let worker = resources.appendingPathComponent("text-worker")
        let models = resources.appendingPathComponent("Models")
        let result = BackendPaths(worker: worker,
            model: models.appendingPathComponent(model.weightsFilename))
        for file in [result.worker, result.model] {
            guard FileManager.default.fileExists(atPath: file.path) else {
                throw WingmanError.unavailable("缺少 \(model.sizeLabel) 本地模型资源（\(file.lastPathComponent)）。请运行 Scripts/setup-model.py 并重新打包应用。")
            }
        }
        return result
    }
}

public struct Evaluation: Sendable {
    public let result: VoiceResult
    public let elapsedSeconds: Double
}

public actor LocalTextBackend {
    private var process: Process?
    private var input: FileHandle?
    private var outputBuffer = Data()
    private var ready: CheckedContinuation<Void, any Error>?
    private var pending: [String: CheckedContinuation<Evaluation, any Error>] = [:]
    private var texts: [String: String] = [:]
    private var generation = UUID()
    private var loaded = false
    private var evaluating = false
    public init() {}

    public func load(paths: BackendPaths) async throws {
        shutdown()
        let current = UUID(); generation = current
        let proc = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        proc.executableURL = paths.worker
        proc.arguments = [paths.model.path]
        proc.standardInput = stdin; proc.standardOutput = stdout; proc.standardError = stderr
        // Drain diagnostics, but do not persist audio, prompts or model outputs in logs.
        stderr.fileHandleForReading.readabilityHandler = { handle in
            if handle.availableData.isEmpty { handle.readabilityHandler = nil }
        }
        process = proc; input = stdin.fileHandleForWriting
        proc.terminationHandler = { [weak self] _ in
            Task { await self?.workerExited(generation: current) }
        }
        do { try proc.run() }
        catch { shutdown(); throw WingmanError.unavailable("无法启动本地模型 worker：\(error.localizedDescription)") }
        let readHandle = stdout.fileHandleForReading
        Task.detached { [weak self] in
            // availableData returns a ready protocol message without waiting to fill a large buffer.
            while true {
                let data = readHandle.availableData
                if data.isEmpty { break }
                await self?.receive(data, generation: current)
            }
            await self?.workerExited(generation: current)
        }
        try await withCheckedThrowingContinuation { continuation in
            ready = continuation
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(180))
                await self?.loadTimedOut(generation: current)
            }
        }
    }

    public func evaluate(text: String, configuration: SessionConfiguration,
                         context: [TranscriptEntry]) async throws -> Evaluation {
        guard loaded, input != nil, process?.isRunning == true else { throw WingmanError.unavailable("本地模型未就绪") }
        guard pending.isEmpty else { throw WingmanError.worker("worker 忙，不能并行提交判断") }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 4_000,
              !configuration.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              configuration.prompt.count <= 4_000 else { throw WingmanError.worker("文本或 prompt 无效") }
        guard !evaluating else { throw WingmanError.worker("worker 忙，不能并行提交判断") }
        evaluating = true
        let current = generation, started = Date()
        defer { if generation == current { evaluating = false } }
        var elapsed: Double = 0
        var quietDecision = Decision.noAlert
        // Independent requests prevent one rule's exclusions from changing another rule.
        // Stop at the first match: one speech segment produces at most one reminder.
        for rule in configuration.rules {
            try Task.checkCancellation()
            guard generation == current else { throw WingmanError.cancelled }
            guard Date().timeIntervalSince(started) < CurrentSpeechWindow.maximumAge else {
                return Evaluation(result: VoiceResult(transcript: text, decision: .inconclusive, quote: "", suggestion: ""), elapsedSeconds: elapsed)
            }
            let single = SessionConfiguration(prompt: rule, sensitivity: configuration.sensitivity, version: configuration.version)
            let evaluation: Evaluation
            do { evaluation = try await evaluateRule(text: text, configuration: single) }
            catch WingmanError.invalidResult {
                // One malformed answer must not hide a valid match to a later rule.
                quietDecision = .inconclusive
                continue
            }
            try Task.checkCancellation()
            elapsed += evaluation.elapsedSeconds
            if evaluation.result.decision == .alert { return Evaluation(result: evaluation.result, elapsedSeconds: elapsed) }
            if evaluation.result.decision == .deferDecision && quietDecision != .inconclusive { quietDecision = .deferDecision }
            if evaluation.result.decision == .inconclusive { quietDecision = .inconclusive }
        }
        return Evaluation(result: VoiceResult(transcript: text, decision: quietDecision, quote: "", suggestion: ""), elapsedSeconds: elapsed)
    }

    private func evaluateRule(text: String, configuration: SessionConfiguration) async throws -> Evaluation {
        guard loaded, let input else { throw WingmanError.unavailable("本地模型未就绪") }
        let id = UUID().uuidString, current = generation
        texts[id] = text
        let request: [String: Any] = [
            "type": "evaluate", "id": id,
            "system": PromptBuilder.system,
            "user": PromptBuilder.user(text: text, configuration: configuration, context: [])
        ]
        var data = try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])
        data.append(10)
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do { try input.write(contentsOf: data) }
            catch { pending.removeValue(forKey: id)?.resume(throwing: error) }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                await self?.requestTimedOut(id: id, generation: current)
            }
        }
    }

    public func shutdown() {
        generation = UUID(); loaded = false; evaluating = false
        ready?.resume(throwing: WingmanError.cancelled); ready = nil
        let continuations = pending.values; pending.removeAll(); texts.removeAll()
        for continuation in continuations { continuation.resume(throwing: WingmanError.cancelled) }
        try? input?.close(); input = nil
        if let process, process.isRunning { process.terminate() }
        process = nil; outputBuffer.removeAll()
    }

    private func receive(_ data: Data, generation current: UUID) {
        guard current == generation else { return }
        outputBuffer.append(data)
        if outputBuffer.count > 131_072 { failAll(WingmanError.worker("worker 输出超出限制")); return }
        while let newline = outputBuffer.firstIndex(of: 10) {
            let line = Data(outputBuffer[..<newline]); outputBuffer.removeSubrange(...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let type = object["type"] as? String else {
                failAll(WingmanError.worker("worker 协议错误")); return
            }
            if type == "ready" {
                loaded = true; ready?.resume(); ready = nil
            } else if type == "error" {
                if let id = object["id"] as? String { texts.removeValue(forKey: id) }
                let error = WingmanError.worker(object["message"] as? String ?? "未知错误")
                if let id = object["id"] as? String, let continuation = pending.removeValue(forKey: id) {
                    continuation.resume(throwing: error)
                } else if ready != nil { failAll(error) }
            } else if type == "result", let id = object["id"] as? String,
                      let continuation = pending.removeValue(forKey: id) {
                do {
                    guard let raw = object["output"] as? String else { throw WingmanError.invalidResult("缺少输出") }
                    let original = texts.removeValue(forKey: id) ?? ""
                    let result = try ResultValidator.decodeDecision(raw, transcript: original)
                    continuation.resume(returning: Evaluation(result: result, elapsedSeconds: object["elapsed_seconds"] as? Double ?? 0))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    private func workerExited(generation current: UUID) {
        guard current == generation else { return }
        failAll(WingmanError.worker("worker 已退出"))
    }
    private func loadTimedOut(generation current: UUID) {
        if current == generation && ready != nil { failAll(WingmanError.worker("模型加载超时")) }
    }
    private func requestTimedOut(id: String, generation current: UUID) {
        if current == generation && pending[id] != nil { failAll(WingmanError.worker("推理超时，已停止 worker")) }
    }
    private func failAll(_ error: any Error) {
        ready?.resume(throwing: error); ready = nil
        let continuations = pending.values; pending.removeAll(); texts.removeAll()
        for continuation in continuations { continuation.resume(throwing: error) }
        shutdown()
    }
}
