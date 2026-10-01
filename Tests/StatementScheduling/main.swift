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
        busy_sent=False
        for line in sys.stdin:
            r=json.loads(line)
            if r.get('output_mode')=='screen':
                print(json.dumps({'type':'result','id':r['id'],'output':'{"decision":"alert"}','elapsed_seconds':0.01}),flush=True)
                continue
            speech=json.loads(r['user'].split('完整发言：' if '完整发言：' in r['user'] else '当前发言：')[-1])
            if speech=='busy once' and not busy_sent:
                busy_sent=True
                print(json.dumps({'type':'error','id':r['id'],'message':'worker busy'}),flush=True)
                continue
            if speech.startswith('capacity') and '\n' in speech:
                print(json.dumps({'type':'error','id':r['id'],'message':'context capacity exceeded'}),flush=True)
                continue
            time.sleep(0.5)
            result={'decision':'defer'} if speech=='unfinished' else ({'decision':'no_alert'} if 'not buying' in speech or speech=='unfinished\ncontinuation' else {'decision':'alert','quote':speech[:80],'suggestion':'Review this statement.'})
            if r.get('output_mode')=='evidence': result.pop('suggestion',None)
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
        // A preview takes the same slot as finals. Finals arriving during it merge.
        controller.receiveText("preview", segment: 0, final: false, seconds: 0)
        try await Task.sleep(for: .milliseconds(400))
        precondition(controller.processing)
        controller.receiveText("first final", segment: 0, final: true, seconds: 0)
        controller.receiveText("second final", segment: 1, final: true, seconds: 0)
        controller.receiveText("third final", segment: 2, final: true, seconds: 0)
        try await Task.sleep(for: .seconds(3))
        precondition(controller.state == .listening && controller.failures == 0)
        precondition(controller.evaluations.count == 3)
        precondition(controller.evaluations.last?.inputText == "first final\nsecond final\nthird final")
        precondition(controller.evaluations.allSatisfy { $0.status == .evaluated })
        precondition(!controller.processing && controller.task == nil)

        controller.receiveText("busy once", segment: 3, final: true, seconds: 0)
        try await Task.sleep(for: .seconds(2))
        precondition(controller.evaluations.last?.status == .evaluated)
        precondition(controller.failures == 0 && controller.state == .listening)

        // A shown rolling alert suppresses both later revisions and its final.
        controller.unmute()
        controller.receiveText("alert preview", segment: 4, final: false, seconds: 0)
        try await Task.sleep(for: .seconds(2))
        precondition(controller.alerts.count == 1)
        let evaluatedCount = controller.evaluations.count
        controller.receiveText("alert preview revised", segment: 4, final: false, seconds: 0)
        controller.receiveText("alert preview final", segment: 4, final: true, seconds: 0)
        try await Task.sleep(for: .seconds(1))
        precondition(controller.evaluations.count == evaluatedCount && controller.alerts.count == 1)
        precondition(!controller.processing)
        controller.dismissAlert()

        // Also suppress a final already queued while the preview is still running.
        controller.receiveText("racing preview", segment: 5, final: false, seconds: 0)
        try await Task.sleep(for: .milliseconds(400))
        controller.receiveText("racing preview final", segment: 5, final: true, seconds: 0)
        try await Task.sleep(for: .seconds(2))
        precondition(controller.alerts.count == 2)
        precondition(controller.evaluations.last?.alertDisposition == "preview_presented")
        precondition(!controller.processing)
        controller.dismissAlert()

        controller.mute()
        controller.receiveText("unfinished", segment: 6, final: true, seconds: 0)
        try await Task.sleep(for: .seconds(1))
        controller.receiveText("continuation", segment: 7, final: true, seconds: 0)
        try await Task.sleep(for: .seconds(1))
        precondition(controller.evaluations.last?.inputText == "unfinished\ncontinuation")
        precondition(controller.evaluations.last?.decision == .noAlert)
        // Queued speech longer than 1500 characters must be merged, with no settling delay.
        controller.receiveText("hold worker", segment: 8, final: true, seconds: 0)
        controller.receiveText(String(repeating: "a", count: 900), segment: 9, final: true, seconds: 0)
        controller.receiveText(String(repeating: "b", count: 900), segment: 10, final: true, seconds: 0)
        try await Task.sleep(for: .seconds(3))
        precondition(controller.evaluations.last?.inputText?.count == 1801)
        let hold = controller.evaluations[controller.evaluations.count - 3]
        let merged = controller.evaluations.last!
        precondition(merged.startedAt!.timeIntervalSince(hold.completedAt!) < 0.3)
        precondition(controller.failures == 0)

        controller.receiveText("hold again", segment: 11, final: true, seconds: 0)
        controller.receiveText("capacity first", segment: 12, final: true, seconds: 0)
        controller.receiveText("capacity second", segment: 13, final: true, seconds: 0)
        try await Task.sleep(for: .seconds(3))
        precondition(controller.state == .listening && controller.failures == 0)
        precondition(controller.evaluations.suffix(2).allSatisfy { $0.status == .evaluated })
        precondition(controller.evaluations.last?.inputText == "capacity second")
        controller.receiveText("cancel me", segment: 14, final: true, seconds: 0)
        await controller.pause()
        precondition(controller.evaluations.last?.status == .cancelled)
        precondition(!controller.processing && controller.state == .paused)
        print("PASS: rolling/final serialization, merged queue, busy retry, alert deduplication, continuation, cancellation")
    }
}
