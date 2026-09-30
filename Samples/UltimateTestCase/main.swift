import Foundation
import Darwin
import WingmanCore

struct AudioEvent: Decodable {
    let text: String
    let segment: Int
    let final: Bool
    let audio_seconds: Double
}
struct Scenario: Decodable {
    struct Rule: Decodable { let id: String; let text: String }
    let rules: [Rule]
}
struct Window: Codable {
    let index: Int
    let segments: [Int]
    let text: String
    let finalTime: Double
    let enqueuedAt: Double
    var status = "pending"
    var decision: String?
    var quote: String?
    var suggestion: String?
    var errors: [String] = []
    var startedAt: Double?
    var completedAt: Double?
    var inferenceSeconds: Double?
    var presented = false
    var matchedRuleID: String?
    var inputText: String?
    var continuedFrom: Int?
}
struct Run: Encodable {
    let runID: String
    let sensitivity: String
    let evaluationProfileID: String
    let sensitivityMappingVersion = SessionConfiguration.sensitivityMappingVersion
    let mode = "audio-clock simulation; actual production core and local model; no microphone"
    let windows: [Window]
}
@main struct UltimateReplay {
    static func log(_ s: String) { FileHandle.standardOutput.write(Data((s+"\n").utf8)) }
    static func date(_ s: Double) -> Date { Date(timeIntervalSince1970: s) }
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count >= 7 else {
            log("Usage: ultimate-replay WORKER MODEL SCENARIO EVENTS OUTPUT low|medium|high|all"); exit(2)
        }
        // Same lock as the production policy harness: no competing benchmark workers.
        let fd = open(FileManager.default.temporaryDirectory.appendingPathComponent("speech-wingman-policy-check-\(getuid()).lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0, flock(fd, LOCK_EX) == 0 else { throw POSIXError(.EIO) }
        defer { flock(fd, LOCK_UN); close(fd) }
        let scenario = try JSONDecoder().decode(Scenario.self, from: Data(contentsOf: URL(fileURLWithPath: args[3])))
        let events = try JSONDecoder().decode([AudioEvent].self, from: Data(contentsOf: URL(fileURLWithPath: args[4])))
        let output = URL(fileURLWithPath: args[5]); try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let runID = UUID().uuidString
        var statement = SpeechStatementBuffer(), preview = "", timer: Double?, windows: [Window] = []
        var segmentNumbers: [UUID: Int] = [:]
        func enqueue(_ segments: [TranscriptEntry], at time: Double) {
            guard let last = segments.last else { return }
            windows.append(Window(index: windows.count, segments: segments.map { segmentNumbers[$0.id]! }, text: segments.map(\.text).joined(separator: "\n"), finalTime: last.date.timeIntervalSince1970, enqueuedAt: time))
        }
        func advance(to time: Double) {
            while let deadline = timer, deadline <= time {
                if !preview.isEmpty, let began = statement.startedAt,
                   deadline - began.timeIntervalSince1970 < SpeechStatementBuffer.maximumDuration {
                    timer = deadline + 0.25
                } else { enqueue(statement.flush(), at: deadline); timer = nil }
            }
        }
        for event in events {
            advance(to: event.audio_seconds)
            if !event.final { preview = event.text; continue }
            preview = ""
            let entry = TranscriptEntry(id: UUID(), date: date(event.audio_seconds), text: event.text, decision: .deferDecision, configurationVersion: 1)
            segmentNumbers[entry.id] = event.segment
            if let group = statement.append(entry) { enqueue(group, at: event.audio_seconds) }
            timer = event.audio_seconds + SpeechStatementBuffer.settlingSeconds
        }
        preview = ""; advance(to: (events.last?.audio_seconds ?? 0) + 30)
        try encoder.encode(windows).write(to: output.appendingPathComponent("windows.json"), options: .atomic)
        let profiles = Dictionary(uniqueKeysWithValues: Sensitivity.allCases.map { level in
            (level.rawValue, SessionConfiguration(prompt: scenario.rules.map(\.text).joined(separator: "\n"), sensitivity: level).evaluationProfileID)
        })
        try encoder.encode(profiles).write(to: output.appendingPathComponent("sensitivity-profiles.json"), options: .atomic)
        if args[6] == "profiles" { log(String(decoding: try encoder.encode(profiles), as: UTF8.self)); return }
        if args[6] == "windows" { log("Built \(windows.count) continuous speech windows"); return }
        let levels = args[6] == "all" ? Sensitivity.allCases : [Sensitivity(rawValue: args[6])!]
        let backend = LocalTextBackend()
        for sensitivity in levels {
            try await backend.load(paths: BackendPaths(worker: URL(fileURLWithPath: args[1]), model: URL(fileURLWithPath: args[2])))
            var results = windows, pending = CurrentSpeechWindow(), gate = AlertGate(), cursor = 0, now = 0.0
            var continuation = DeferredSpeechContinuation()
            var indices: [UUID: Int] = [:]
            let configuration = SessionConfiguration(prompt: scenario.rules.map(\.text).joined(separator: "\n"), sensitivity: sensitivity)
            func append(until time: Double) {
                while cursor < windows.count && windows[cursor].enqueuedAt <= time {
                    let w = windows[cursor]
                    let entry = TranscriptEntry(id: UUID(), date: date(w.finalTime), text: w.text, decision: .deferDecision, configurationVersion: 1)
                    indices[entry.id] = cursor
                    for dropped in pending.append(entry) { results[indices[dropped.id]!].status = "overflow" }
                    cursor += 1
                }
            }
            while cursor < windows.count || pending.latest != nil {
                if pending.latest == nil { now = max(now, windows[cursor].enqueuedAt) }
                append(until: now)
                for expired in pending.removeExpired(now: date(now)) { results[indices[expired.id]!].status = "expired" }
                guard let entry = pending.take(now: date(now)) else { continue }
                let index = indices[entry.id]!, started = Date()
                let continued = continuation.input(for: entry)
                results[index].inputText = continued.text
                results[index].continuedFrom = continued.continuedFrom.flatMap { indices[$0] }
                results[index].startedAt = now
                do {
                    let evaluation = try await backend.evaluate(text: continued.text, configuration: configuration, context: [])
                    continuation.remember(entry, decision: evaluation.result.decision)
                    now += Date().timeIntervalSince(started)
                    append(until: now)
                    results[index].status = "evaluated"
                    results[index].decision = evaluation.result.decision.rawValue
                    results[index].quote = evaluation.result.quote
                    results[index].suggestion = evaluation.result.suggestion
                    results[index].errors = evaluation.validationErrors
                    results[index].matchedRuleID = evaluation.matchedRuleIndex.map { scenario.rules[$0].id }
                    results[index].inferenceSeconds = evaluation.elapsedSeconds
                    results[index].presented = pending.canPresent(entry, now: date(now)) && gate.admit(evaluation.result, eventID: entry.id, isFinal: true, now: date(now))
                } catch {
                    now += Date().timeIntervalSince(started); append(until: now)
                    results[index].status = "invalid"; results[index].errors = [error.localizedDescription]
                    // Production stops listening on a worker error. Do not pretend
                    // later unavailable-worker requests are new inference results.
                    for later in results.indices where results[later].status == "pending" {
                        results[later].status = "blocked_after_worker_failure"
                        results[later].errors = [error.localizedDescription]
                    }
                }
                results[index].completedAt = now
                log("\(sensitivity.rawValue) W\(index) \(results[index].decision ?? results[index].status) presented=\(results[index].presented) \(String(format: "%.2f", now-results[index].startedAt!))s \(results[index].quote ?? "") \(results[index].suggestion ?? "")")
                try encoder.encode(Run(runID: runID, sensitivity: sensitivity.rawValue, evaluationProfileID: configuration.evaluationProfileID, windows: results)).write(to: output.appendingPathComponent("\(sensitivity.rawValue).json"), options: .atomic)
                if results[index].status == "invalid" { break }
            }
            try encoder.encode(Run(runID: runID, sensitivity: sensitivity.rawValue, evaluationProfileID: configuration.evaluationProfileID, windows: results)).write(to: output.appendingPathComponent("\(sensitivity.rawValue).json"), options: .atomic)
            await backend.shutdown()
        }
        await backend.shutdown()
    }
}
