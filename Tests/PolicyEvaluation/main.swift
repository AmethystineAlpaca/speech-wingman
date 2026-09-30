import Foundation
import WingmanCore

/// Uses the production prompt, language detection, worker, and output validator.
@main
struct PolicyCheck {
    struct Case: Decodable {
        let id: String
        let speech: String
        let policy: String
        let expected: String
        let history: String?
    }
    static func log(_ text: String) { FileHandle.standardOutput.write(Data((text + "\n").utf8)) }
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count >= 4 else {
            log("Usage: WingmanPolicyCheck TEXT_WORKER MODEL_FILE CASES_JSON [...]")
            exit(2)
        }
        let backend = LocalTextBackend()
        try await backend.load(paths: BackendPaths(worker: URL(fileURLWithPath: args[1]), model: URL(fileURLWithPath: args[2])))
        var passed = 0, total = 0
        for path in args.dropFirst(3) {
            let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
            for item in cases {
                total += 1
                do {
                    let history = item.history.map { [TranscriptEntry(id: UUID(), date: Date(), text: $0, decision: .alert, configurationVersion: 1)] } ?? []
                    let evaluation = try await backend.evaluate(text: item.speech, configuration: SessionConfiguration(prompt: item.policy), context: history)
                    let correct = evaluation.result.decision.rawValue == item.expected
                    if correct { passed += 1 }
                    log("\(correct ? "PASS" : "FAIL") \(item.id): \(evaluation.result.decision.rawValue), \(String(format: "%.2f", evaluation.elapsedSeconds))s; \(evaluation.result.suggestion)")
                } catch { log("FAIL \(item.id): \(error.localizedDescription)") }
            }
        }
        await backend.shutdown()
        log("Policy check: \(passed)/\(total) passed (synthetic text; not live-microphone accuracy)")
        if passed != total { exit(1) }
    }
}
