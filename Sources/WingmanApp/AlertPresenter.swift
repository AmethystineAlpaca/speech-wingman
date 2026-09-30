import AppKit
import SwiftUI
import WingmanCore

@MainActor
final class AlertPresenter {
    private var panel: NSPanel?
    private var popup: AlertPopup?
    func updateLanguage(_ language: DisplayLanguage) {
        guard var popup else { return }
        popup.language = language
        self.popup = popup
        panel?.title = language.text("Speech Wingman 提醒")
        panel?.contentView = NSHostingView(rootView: popup)
    }
    func present(_ alert: AlertEntry, language: DisplayLanguage, dismiss: @escaping () -> Void, mute: @escaping () -> Void) {
        close()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 210),
            styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = language.text("Speech Wingman 提醒")
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let popup = AlertPopup(alert: alert, language: language, dismiss: dismiss, mute: mute)
        self.popup = popup
        panel.contentView = NSHostingView(rootView: popup)
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: visible.maxX - 440, y: visible.maxY - 240))
        }
        self.panel = panel
        panel.orderFrontRegardless()
    }
    func close() { panel?.close(); panel = nil; popup = nil }
}

private struct AlertPopup: View {
    let alert: AlertEntry
    var language: DisplayLanguage
    let dismiss: () -> Void
    let mute: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(language.text("原话")).font(.caption).foregroundStyle(.secondary)
            Text(alert.quote).lineLimit(3).textSelection(.enabled)
            Text(alert.suggestion).fontWeight(.medium).lineLimit(3)
            HStack {
                Button(language.text("关闭"), action: dismiss)
                Button(language.text("静音一小时"), action: mute)
            }
        }.padding(20).frame(width: 420, height: 210, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.locale, language.locale)
    }
}
