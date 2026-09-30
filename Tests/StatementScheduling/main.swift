import AppKit
import Foundation
import WingmanCore

/// Compiles the production controller with private access relaxed in a temporary copy.
/// No microphone, model weights, live preferences, or popup is used.
@main
struct StatementSchedulingCheck {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let worker = root.appendingPathComponent("worker")
        try #"""
        #!/usr/bin/python3
        import json,sys,time
        print('{"type":"ready"}',flush=True)
        for line in sys.stdin:
            r=json.loads(line)
            if r.get('output_mode')=='screen':
                print(json.dumps({'type':'result','id':r['id'],'output':'{"decision":"alert"}','elapsed_seconds':0.01}),flush=True)
                continue
            speech=json.loads(r['user'].split('当前发言：')[-1])
            time.sleep(2)
            result={'decision':'defer'} if speech=='unfinished' else ({'decision':'no_alert'} if 'not buying' in speech or speech=='unfinished\ncontinuation' else {'decision':'alert','quote':speech,'suggestion':'Review this statement.'})
            print(json.dumps({'type':'result','id':r['id'],'output':json.dumps(result),'elapsed_seconds':2}),flush=True)
        """#.write(to: worker, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: worker.path)
        let domain = "local.speechwingman.scheduling-test." + UUID().uuidString
        let preferences = UserDefaults(suiteName: domain)!
        defer { preferences.removePersistentDomain(forName: domain) }
        let controller = SessionController(preferences: preferences)
        try await controller.backend.load(paths: BackendPaths(worker: worker, model: worker))
        controller.state = .listening
        controller.mute() // Assert evaluation/disposition without presenting a desktop alert.
        controller.receiveText("Buy bananas.", segment: 0, final: true, seconds: 0)
        try await Task.sleep(for: .milliseconds(700))
        controller.receiveText("Actually", segment: 1, final: false, seconds: 0)
        // Keep a continuing preview beyond the settling window; it must not alert early.
        try await Task.sleep(for: .seconds(2))
        precondition(controller.evaluations.isEmpty)
        controller.receiveText("Actually, we are not buying bananas.", segment: 1, final: true, seconds: 0)
        try await Task.sleep(for: .seconds(4))
        precondition(controller.evaluations.count == 1)
        precondition(controller.evaluations[0].decision == .noAlert)
        precondition(controller.evaluations[0].segmentIDs.count == 2)
        controller.receiveText("Buy apples.", segment: 2, final: true, seconds: 0)
        try await Task.sleep(for: .milliseconds(1800))
        precondition(controller.processing)
        controller.receiveText("Buy pears.", segment: 3, final: true, seconds: 0)
        try await Task.sleep(for: .seconds(5))
        precondition(controller.evaluations.count == 3)
        precondition(controller.evaluations.dropFirst().allSatisfy { $0.status == .evaluated && $0.decision == .alert && $0.alertDisposition == "muted_or_limited" })
        precondition(controller.transcript.allSatisfy { $0.evaluationStatus == .evaluated })
        precondition(controller.alerts.isEmpty)
        controller.receiveText("unfinished", segment: 4, final: true, seconds: 0)
        try await Task.sleep(for: .seconds(4))
        precondition(controller.evaluations.last?.decision == .deferDecision)
        let predecessor = controller.evaluations.last!.id
        controller.receiveText("continuation", segment: 5, final: true, seconds: 0)
        try await Task.sleep(for: .seconds(4))
        precondition(controller.evaluations.last?.inputText == "unfinished\ncontinuation")
        precondition(controller.evaluations.last?.continuedFromID == predecessor)
        precondition(controller.evaluations.last?.decision == .noAlert)
        controller.receiveText("Buy oranges.", segment: 6, final: true, seconds: 0)
        try await Task.sleep(for: .milliseconds(1800))
        await controller.pause()
        precondition(controller.evaluations.last?.status == .cancelled)
        precondition(!controller.processing && controller.state == .paused)
        print("PASS: production controller joins speech and explicit deferrals, preserves FIFO work, records mute, and cancels on pause")
    }
}
