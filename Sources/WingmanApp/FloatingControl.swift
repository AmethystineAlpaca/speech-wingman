import AppKit
import SwiftUI
import Combine
import WingmanCore

@MainActor
final class FloatingControlPresenter {
    private var panel: NSPanel?
    private var visibility: AnyCancellable?

    func install(controller: SessionController) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 244, height: 80),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Speech Wingman"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = FloatingHostingView(rootView: FloatingControlView(controller: controller))
        let restored = panel.setFrameUsingName("SpeechWingmanFloatingControl")
        if !restored || !NSScreen.screens.contains(where: { $0.visibleFrame.contains(panel.frame) }) {
            if let frame = NSScreen.main?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: frame.maxX - 268, y: frame.minY + 32))
            }
        }
        panel.setFrameAutosaveName("SpeechWingmanFloatingControl")
        self.panel = panel
        visibility = controller.$floatingControlVisible.sink { [weak panel] visible in
            if visible { panel?.orderFrontRegardless() } else { panel?.orderOut(nil) }
        }
    }
    func close() { visibility = nil; panel?.close(); panel = nil }
}

private final class FloatingHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }
}

struct FloatingControlView: View {
    @ObservedObject var controller: SessionController
    private var listening: Bool { controller.state == .listening }
    private var loading: Bool { controller.state == .loading }
    private var action: String { listening ? "停止监听" : loading ? "取消加载" : "开始监听" }
    private var status: String {
        if listening { return "正在监听" }
        if loading { return "加载中…" }
        return controller.state == .failed ? "点击重试" : "点击开始"
    }
    var body: some View {
        HStack(spacing: 12) {
            Button {
                Task { await controller.toggleListening() }
            } label: {
                ZStack {
                    Circle().fill(listening ? Color.green : Color.accentColor)
                    if loading {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: listening ? "stop.fill" : "mic.fill")
                            .font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                    }
                }.frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(controller.t(action))
            .help(controller.t(action))
            VStack(alignment: .leading, spacing: 5) {
                Text("Speech Wingman").font(.system(size: 13, weight: .semibold))
                HStack(spacing: 6) {
                    Circle().fill(listening ? .green : .secondary).frame(width: 5, height: 5)
                    Text(controller.t(status)).font(.system(size: 11)).foregroundStyle(.secondary)
                    if listening {
                        HStack(alignment: .center, spacing: 2) {
                            ForEach(0..<4) { index in
                                Capsule().fill(.green)
                                    .frame(width: 2, height: 3 + CGFloat(min(1, controller.inputLevel / 0.04)) * CGFloat([9, 15, 11, 6][index]))
                            }
                        }.frame(height: 16).accessibilityHidden(true)
                    }
                }
            }.allowsHitTesting(false)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(width: 244, height: 80)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.2)))
        .environment(\.locale, controller.language.locale)
        .help(controller.t("拖动空白处移动；点击按钮开始或停止监听"))
    }
}
