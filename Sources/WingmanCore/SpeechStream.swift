import Foundation

/// Self-contained bilingual streaming ASR. No OS speech service, language switch or network path.
@MainActor
public final class SpeechStream {
    private var process: Process?
    private var input: FileHandle?
    private var ready: CheckedContinuation<Void, any Error>?
    private var finished: CheckedContinuation<Void, any Error>?
    private var output = Data()
    private var generation = UUID()
    private var outstanding = 0
    private var loaded = false
    private var didFinish = false
    private let writer = DispatchQueue(label: "wingman.asr.input", qos: .userInitiated)
    private var onText: (@MainActor (String, Int, Bool, Double) -> Void)?
    private var onFailure: (@MainActor (String) -> Void)?
    public init() {}

    public func start(worker: URL, models: URL,
                      onText: @escaping @MainActor (String, Int, Bool, Double) -> Void,
                      onFailure: @escaping @MainActor (String) -> Void) async throws {
        stop()
        let current = generation
        let proc = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        proc.executableURL = worker; proc.arguments = [models.path]
        proc.standardInput = stdin; proc.standardOutput = stdout; proc.standardError = stderr
        stderr.fileHandleForReading.readabilityHandler = { handle in
            if handle.availableData.isEmpty { handle.readabilityHandler = nil }
        }
        self.onText = onText; self.onFailure = onFailure
        self.process = proc; input = stdin.fileHandleForWriting
        do { try proc.run() } catch { stop(); throw error }
        let reader = stdout.fileHandleForReading
        Task.detached { [weak self] in
            while true {
                let data = reader.availableData
                if data.isEmpty { break }
                await self?.receive(data, generation: current)
            }
            await self?.exited(generation: current)
        }
        try await withCheckedThrowingContinuation { continuation in
            ready = continuation
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard let self, self.generation == current, self.ready != nil else { return }
                self.fail("中英双语 ASR 加载超时")
            }
        }
    }

    public func append(_ samples: [Float]) throws {
        guard loaded, !didFinish, !samples.isEmpty, samples.count <= 16_000 else {
            throw WingmanError.unavailable("ASR 未就绪或音频块无效")
        }
        guard outstanding < 128 else { throw WingmanError.unavailable("ASR 跟不上收音，已暂停；请继续重试") }
        let pcm = samples.withUnsafeBytes { Data($0) }
        let object = ["type": "audio", "pcm_f32_base64": pcm.base64EncodedString()]
        let data = try JSONSerialization.data(withJSONObject: object) + Data([10])
        outstanding += 1
        try send(data)
    }

    public func finish() async throws {
        guard loaded else { throw WingmanError.unavailable("ASR 未就绪") }
        try send(Data("{\"type\":\"finish\"}\n".utf8))
        try await withCheckedThrowingContinuation { continuation in
            finished = continuation
            let current = generation
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard let self, self.generation == current, self.finished != nil else { return }
                self.fail("ASR 收尾超时")
            }
        }
    }

    private func send(_ data: Data) throws {
        guard let input else { throw WingmanError.unavailable("ASR 已停止") }
        let current = generation
        writer.async { [weak self] in
            do { try input.write(contentsOf: data) }
            catch { Task { @MainActor in
                guard let self, self.generation == current else { return }
                self.fail("ASR 音频传输失败")
            } }
        }
    }

    public func stop() {
        generation = UUID(); loaded = false; didFinish = false
        ready?.resume(throwing: WingmanError.cancelled); ready = nil
        finished?.resume(throwing: WingmanError.cancelled); finished = nil
        if let process, process.isRunning { process.terminate() }
        process = nil
        // Close on the same serial queue as writes; queued input belongs to the old generation.
        if let handle = input { writer.async { try? handle.close() } }
        input = nil; output.removeAll(); outstanding = 0
        onText = nil; onFailure = nil
    }

    private func receive(_ data: Data, generation current: UUID) {
        guard current == generation else { return }
        output.append(data)
        guard output.count < 262_144 else { fail("ASR 输出超出限制"); return }
        while let newline = output.firstIndex(of: 10) {
            let line = Data(output[..<newline]); output.removeSubrange(...newline)
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let type = obj["type"] as? String else { fail("ASR 协议错误"); return }
            switch type {
            case "ready": loaded = true; ready?.resume(); ready = nil
            case "ack": outstanding = max(0, outstanding - 1)
            case "transcript":
                guard let text = obj["text"] as? String, let segment = obj["segment"] as? Int,
                      let final = obj["final"] as? Bool, let seconds = obj["audio_seconds"] as? Double else {
                    fail("ASR 转录格式错误"); return
                }
                onText?(text, segment, final, seconds)
            case "finished": didFinish = true; finished?.resume(); finished = nil
            case "error": fail(obj["message"] as? String ?? "ASR 失败"); return
            default: fail("未知 ASR 消息"); return
            }
            guard generation == current else { return }
        }
    }
    private func exited(generation current: UUID) {
        guard current == generation, !didFinish else { return }
        fail("中英双语 ASR 已退出")
    }
    private func fail(_ message: String) {
        let callback = onFailure
        let error = WingmanError.worker(message)
        ready?.resume(throwing: error); ready = nil
        finished?.resume(throwing: error); finished = nil
        stop(); callback?(message)
    }
}
