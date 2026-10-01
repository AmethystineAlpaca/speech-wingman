import AppKit
import SwiftUI
import WingmanCore

struct Segment: Decodable { let language: String; let code: String; let start: Double; let end: Double }
struct DemoInput: Decodable { let rule: String; let timeline: [Segment]; let duration: Double; let audio_sha256: String }
@MainActor final class ReplayState: ObservableObject {
    @Published var seconds = 0.0
    @Published var index = 0
    @Published var complete = false
    let input: DemoInput
    init(_ input: DemoInput) { self.input = input }
}
struct DemoView: View {
    @ObservedObject var controller: SessionController
    @ObservedObject var replay: ReplayState
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Speech Wingman").font(.system(size: 28, weight: .bold))
                Spacer()
                Text("MULTILINGUAL · ON DEVICE").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("One session.\nFive languages.").font(.system(size: 32, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                    Text("No recognition-language switch.").font(.system(size: 18)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("THE RULE · ENGLISH REMINDERS").font(.caption.bold()).foregroundStyle(.secondary)
                        Text(replay.input.rule).font(.system(size: 18, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 10) {
                        Text("AUDIO INPUT · CONTINUOUS PLAYBACK").font(.caption.bold()).foregroundStyle(.secondary)
                        ForEach(Array(replay.input.timeline.enumerated()), id: \.offset) { index, segment in
                            HStack(spacing: 10) {
                                Image(systemName: replay.index == index ? "waveform" : (replay.seconds > segment.end ? "checkmark.circle.fill" : "circle"))
                                    .foregroundStyle(replay.index == index ? Color.blue : Color.secondary)
                                Text(segment.code == "mixed" ? "Mixed-language conversation" : segment.language)
                                    .font(.system(size: 16, weight: replay.index == index ? .semibold : .regular))
                                Spacer()
                            }
                        }
                    }
                    FloatingControlView(controller: controller).frame(width: 244, height: 164).clipShape(RoundedRectangle(cornerRadius: 14))
                    Spacer(minLength: 0)
                }.frame(width: 470)
                VStack(alignment: .leading, spacing: 6) {
                    Text("ACTUAL APP VIEW · REAL MODEL OUTPUT").font(.caption.bold()).foregroundStyle(.secondary)
                    SessionView(controller: controller).background(.white, in: RoundedRectangle(cornerRadius: 14))
                }.frame(width: 470)
            }
            Spacer(minLength: 0)
            HStack {
                Text("Synthetic voice replay · Real ASR + rule evaluation · 1× speed").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%02d:%02d / %02d:%02d", Int(replay.seconds)/60, Int(replay.seconds)%60, Int(replay.input.duration)/60, Int(replay.input.duration)%60)).monospacedDigit().font(.caption)
            }
            ProgressView(value: min(replay.seconds, replay.input.duration), total: replay.input.duration).tint(.blue)
        }.padding(30).frame(width: 1040, height: 820).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .light)
    }
}
@main struct MultilingualReplay {
    @MainActor static func main() async throws {
        let app = NSApplication.shared; app.setActivationPolicy(.accessory); app.appearance = NSAppearance(named: .aqua)
        let root = URL(fileURLWithPath: CommandLine.arguments[1]); let work = root.appendingPathComponent("local-evaluation/multilingual-demo")
        let input = try JSONDecoder().decode(DemoInput.self, from: Data(contentsOf: work.appendingPathComponent("input.json")))
        let domain = "local.speechwingman.multilingual-demo." + UUID().uuidString
        let preferences = UserDefaults(suiteName: domain)!; defer { preferences.removePersistentDomain(forName: domain) }
        preferences.set(input.rule, forKey: "alertPrompt")
        let controller = SessionController(preferences: preferences)
        let resources = work.appendingPathComponent("workers")
        let models = root.appendingPathComponent("build/Speech Wingman.app/Contents/Resources/Models")
        try await controller.backend.load(paths: BackendPaths(worker: resources.appendingPathComponent("text-worker"), model: models.appendingPathComponent("Qwen3-4B-Instruct-2507-Q4_K_M.gguf")))
        let replay = ReplayState(input)
        let view = NSHostingView(rootView: DemoView(controller: controller, replay: replay))
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1040, height: 820), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Speech Wingman — Multilingual replay"; window.contentView = view; window.orderFrontRegardless()
        controller.state = .listening; controller.status = "正在本机监听 · 多语言自动识别"
        var events: [[String: Any]] = []; var failures: [String] = []
        var began = Date()
        try await controller.speech.start(worker: resources.appendingPathComponent("asr-worker"), models: models, onText: { text, segment, final, seconds in
            events.append(["text": text, "segment": segment, "final": final, "audio_seconds": seconds, "wall_seconds": Date().timeIntervalSince(began)])
            controller.receiveText(text, segment: segment, final: final, seconds: seconds)
        }, onFailure: { message in failures.append(message) })
        let data = try Data(contentsOf: work.appendingPathComponent("continuous.f32"))
        let samples = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let frames = work.appendingPathComponent("frames"); try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        began = Date(); var frame = 0; var lastIndex = 0; var nextFrame = 0.0
        for offset in stride(from: 0, to: samples.count, by: 1600) {
            let target = Double(offset)/16000
            let wait = target - Date().timeIntervalSince(began)
            if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
            replay.seconds = Date().timeIntervalSince(began)
            replay.index = input.timeline.lastIndex(where: { $0.start <= target }) ?? 0
            if replay.index != lastIndex { controller.dismissAlert(); lastIndex = replay.index }
            try controller.speech.append(Array(samples[offset..<min(offset+1600, samples.count)]))
            if target >= nextFrame {
                try capture(view, to: frames.appendingPathComponent(String(format: "%05d.png", frame)))
                frame += 1; nextFrame += 0.5
            }
        }
        try await controller.speech.finish()
        for _ in 0..<24 {
            try await Task.sleep(for: .milliseconds(500)); replay.seconds = Date().timeIntervalSince(began)
            try capture(view, to: frames.appendingPathComponent(String(format: "%05d.png", frame))); frame += 1
            if controller.task == nil && !controller.processing { break }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        let records = try JSONSerialization.jsonObject(with: encoder.encode(controller.evaluations))
        let alerts = try JSONSerialization.jsonObject(with: encoder.encode(controller.alerts))
        let report: [String: Any] = ["synthetic_audio": true, "realtime": true, "response_language": controller.language.rawValue, "rule": input.rule, "audio_sha256": input.audio_sha256, "events": events, "evaluations": records, "alerts": alerts, "errors": failures, "frames": frame, "fps": 2, "source": "Production SpeechStream, SessionController, LocalTextBackend and SwiftUI views; PCM replay replaces microphone input only."]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: work.appendingPathComponent("report.json"))
        print("Recorded \(frame) real UI frames, \(events.filter { $0["final"] as? Bool == true }.count) finalized segments, \(controller.alerts.count) alerts. Errors: \(failures)")
        await controller.backend.shutdown(); controller.speech.stop(); controller.dismissAlert(); window.close()
    }
    @MainActor static func capture(_ view: NSView, to url: URL) throws {
        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let output = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1040, pixelsHigh: 820, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: output)
        NSImage(cgImage: bitmap.cgImage!, size: view.bounds.size).draw(in: NSRect(x: 0, y: 0, width: 1040, height: 820))
        NSGraphicsContext.restoreGraphicsState()
        try output.representation(using: .png, properties: [:])!.write(to: url)
    }
}
