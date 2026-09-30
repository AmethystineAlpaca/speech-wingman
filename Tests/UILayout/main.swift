import AppKit
import SwiftUI
import WingmanCore

@main
struct UILayoutCheck {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: .aqua)
        let suite = "local.speechwingman.ui-test." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let controller = SessionController(preferences: preferences)
        precondition(controller.language == .english)
        let publicDemo = CommandLine.arguments.contains("--public-demo")
        if publicDemo {
            controller.prompt = "Alert when I make a firm commitment without a clear deadline or delivery scope. Stay quiet for conditional statements or complete commitments."
        }
        let originalPrompt = controller.prompt
        controller.transcript = [TranscriptEntry(id: UUID(), date: Date(), text: "我们用 BigQuery 做 reconciliation. Let's check the deadline.", decision: .noAlert, configurationVersion: 1)]
        controller.preview = "中文、English，都能识别。"
        if publicDemo {
            controller.transcript = [TranscriptEntry(id: UUID(), date: Date(), text: "I guarantee I will get everything done.", decision: .alert, configurationVersion: 1)]
            controller.preview = "Let me clarify the scope and deadline."
        }
        let originalTranscript = controller.transcript.map(\.text)
        controller.state = .listening
        controller.status = "正在本机监听 · 中英自动识别"
        controller.processing = true
        controller.processingStartedAt = Date()
        controller.resultDelay = 2.4; controller.elapsed = 1.1
        let alert = AlertEntry(id: UUID(), date: Date(), quote: publicDemo ? "I guarantee I will get everything done." : "我肯定全部搞定。", suggestion: "Please clarify the deadline and delivery scope.", configurationVersion: 1)
        controller.activeAlert = alert
        let presenter = AlertPresenter()
        presenter.present(alert, language: .english, dismiss: {}, mute: {})
        let panel = app.windows.first { $0 is NSPanel && $0.title == "Speech Wingman Alert" }!
        precondition(panel.isVisible)
        let panelID = panel.windowNumber
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for language in (publicDemo ? [DisplayLanguage.english] : DisplayLanguage.allCases) {
            controller.language = language
            presenter.updateLanguage(language)
            precondition(panel.title == language.text("Speech Wingman 提醒"))
            precondition(panel.windowNumber == panelID && panel.isVisible)
            precondition(controller.state == .listening && controller.processing)
            precondition(controller.prompt == originalPrompt && controller.transcript.map(\.text) == originalTranscript)
            let restored = SessionController(preferences: preferences)
            precondition(restored.language == language)
            try snapshot(SettingsView(controller: controller), width: 620, height: 680, to: output.appendingPathComponent("settings-\(language.rawValue).png"))
            try snapshot(SessionView(controller: controller), width: 470, height: 720, to: output.appendingPathComponent("session-\(language.rawValue).png"))
            panel.displayIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            if let view = panel.contentView { try save(view, to: output.appendingPathComponent("alert-\(language.rawValue).png")) }
        }
        if publicDemo {
            // README-only examples. These are rendered UI illustrations, not inference results.
            let examples = [
                ("jargon", "The ETL pipeline feeds our OLAP layer.", "Briefly explain ETL and OLAP for your audience."),
                ("space-cat", "Let the cat captain our spaceship.", "You just proposed a feline space captain. Maybe choose a human pilot?")
            ]
            presenter.close()
            for (name, quote, suggestion) in examples {
                let example = AlertEntry(id: UUID(), date: Date(), quote: quote, suggestion: suggestion, configurationVersion: 1)
                presenter.present(example, language: .english, dismiss: {}, mute: {})
                let examplePanel = app.windows.first { $0 is NSPanel && $0.title == "Speech Wingman Alert" && $0.isVisible }!
                RunLoop.current.run(until: Date().addingTimeInterval(0.15))
                examplePanel.displayIfNeeded()
                try save(examplePanel.contentView!, to: output.appendingPathComponent("example-\(name)-en.png"))
                presenter.close()
            }
        }
        presenter.close()
        precondition(!panel.isVisible)
        print("PASS: language preference reload, preserved transcript/policy/listening state, and existing alert panel update. Saved \(publicDemo ? 5 : 6) rendered layouts with synthetic content.")
    }
    @MainActor static func snapshot<V: View>(_ view: V, width: CGFloat, height: CGFloat, to url: URL) throws {
        let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        try save(host, to: url)
        window.orderOut(nil)
    }
    @MainActor static func save(_ view: NSView, to url: URL) throws {
        view.layoutSubtreeIfNeeded()
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        // cacheDisplay preserves transparency; composite onto the same system background
        // so black text is visible in image viewers with a black transparency canvas.
        let image = NSImage(size: view.bounds.size)
        image.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: view.bounds.size)).fill()
        bitmap.draw(in: NSRect(origin: .zero, size: view.bounds.size))
        image.unlockFocus()
        let flattened = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let encoded = flattened.representation(using: .png, properties: [:])!
        // Publish only pixels/color information, never AppKit's textual image metadata.
        var clean = Data(encoded.prefix(8))
        var cursor = 8
        while cursor + 12 <= encoded.count {
            let length = encoded[cursor..<cursor + 4].reduce(0) { ($0 << 8) | Int($1) }
            let end = cursor + length + 12
            precondition(end <= encoded.count)
            let kind = String(decoding: encoded[cursor + 4..<cursor + 8], as: UTF8.self)
            if !["tEXt", "zTXt", "iTXt", "eXIf"].contains(kind) { clean.append(encoded[cursor..<end]) }
            cursor = end
        }
        try clean.write(to: url)
    }
}
