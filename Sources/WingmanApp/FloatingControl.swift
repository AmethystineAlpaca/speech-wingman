import AppKit
import SwiftUI
import Combine
import WingmanCore

@MainActor
final class FloatingControlPresenter {
    private var panel: NSPanel?
    private var visibility: AnyCancellable?
    private var sizing: AnyCancellable?

    func install(controller: SessionController, openMainPanel: @escaping () -> Void = {}) {
        guard panel == nil else { return }
        let height = FloatingControlView.height(state: controller.state, hasText: !controller.transcript.isEmpty || !controller.preview.isEmpty)
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 244, height: height),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Speech Wingman"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = FloatingHostingView(rootView: FloatingControlView(controller: controller, openMainPanel: openMainPanel))
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
        sizing = Publishers.CombineLatest3(controller.$state, controller.$transcript, controller.$preview)
            .map { state, transcript, preview in
                FloatingControlView.height(state: state, hasText: !transcript.isEmpty || !preview.isEmpty)
            }
            .removeDuplicates()
            // @Published emits before storing the value. Resize only after the
            // controller has changed, since setFrame can render SwiftUI immediately.
            .receive(on: RunLoop.main)
            .sink { [weak panel] height in
                guard let panel else { return }
                var frame = panel.frame
                frame.size = NSSize(width: 244, height: height)
                if let screen = panel.screen ?? NSScreen.main {
                    let visible = screen.visibleFrame
                    frame.origin.x = max(visible.minX, min(frame.minX, visible.maxX - frame.width))
                    frame.origin.y = max(visible.minY, min(frame.minY, visible.maxY - frame.height))
                }
                panel.setFrame(frame, display: true)
            }
    }
    func close() { visibility = nil; sizing = nil; panel?.close(); panel = nil }
}

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class FloatingHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { false }
}

/// Use native window dragging explicitly: SwiftUI content and NSTextView can
/// consume mouse-downs before NSPanel's background-dragging behavior sees them.
struct FloatingDragHandle: NSViewRepresentable {
    let help: String
    func makeNSView(context: Context) -> FloatingDragHandleView { FloatingDragHandleView() }
    func updateNSView(_ view: FloatingDragHandleView, context: Context) { view.toolTip = help }
}

final class FloatingDragHandleView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) {
        NSCursor.closedHand.push()
        defer { NSCursor.pop() }
        window?.performDrag(with: event)
    }
}

private final class FloatingTranscriptTextView: NSTextView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func copy(_ sender: Any?) {
        _ = writeSelection(to: .general, types: [.string])
    }
    override func writeSelection(to pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        let selection = selectedRange()
        guard types.contains(.string), selection.length > 0,
              NSMaxRange(selection) <= (string as NSString).length else { return false }
        pasteboard.clearContents()
        return pasteboard.setString((string as NSString).substring(with: selection), forType: .string)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "c" {
            copy(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

struct FloatingControlView: View {
    @ObservedObject var controller: SessionController
    var openMainPanel: () -> Void = {}
    static func height(state: SessionController.State, hasText: Bool) -> CGFloat {
        state == .listening || hasText ? 164 : 80
    }
    private var height: CGFloat {
        Self.height(state: controller.state, hasText: !controller.transcript.isEmpty || !controller.preview.isEmpty)
    }
    private var recentText: String {
        // Bound rendering work independently of the full session history.
        String((controller.transcript.suffix(3).map(\.text) + [controller.preview])
            .filter { !$0.isEmpty }.joined(separator: "\n").suffix(1800))
    }
    private var listening: Bool { controller.state == .listening }
    private var loading: Bool { controller.state == .loading }
    private var action: String { listening ? "停止监听" : loading ? "取消加载" : "开始监听" }
    private var status: String {
        if listening { return "正在监听" }
        if loading { return "加载中…" }
        if controller.state == .paused { return "已暂停" }
        return controller.state == .failed ? "点击重试" : "点击开始"
    }
    var body: some View {
        VStack(spacing: 0) {
            controls
            if height > 80 {
                Divider().padding(.horizontal, 16)
                FloatingTranscriptView(text: recentText, placeholder: controller.t("等待语音…"),
                                       accessibilityLabel: controller.t("当前会话转写"))
                    .frame(height: 64)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 11)
            }
        }
        .frame(width: 244, height: height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.2)))
        .environment(\.locale, controller.language.locale)
    }
    private var controls: some View {
        HStack(spacing: 8) {
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .overlay(FloatingDragHandle(help: controller.t("拖动标题移动；选择文字后按 ⌘C 复制")))
            Button(action: openMainPanel) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(controller.t("打开主面板"))
            .help(controller.t("打开主面板"))
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 12)
        }
        .padding(.horizontal, 16)
        .frame(width: 244, height: 80)
    }
}

/// A fixed-height viewport that follows the last line after every ASR revision.
struct FloatingTranscriptView: NSViewRepresentable {
    let text: String
    let placeholder: String
    let accessibilityLabel: String

    func makeNSView(context: Context) -> FloatingTranscriptScrollView {
        FloatingTranscriptScrollView()
    }
    func updateNSView(_ view: FloatingTranscriptScrollView, context: Context) {
        view.update(text: text, placeholder: placeholder, accessibilityLabel: accessibilityLabel)
    }
}

final class FloatingTranscriptScrollView: NSScrollView {
    private let transcript = FloatingTranscriptTextView()
    private var followsLatest = true
    private var viewportSize = NSSize.zero

    init() {
        super.init(frame: .zero)
        drawsBackground = false
        hasVerticalScroller = false
        hasHorizontalScroller = false
        transcript.drawsBackground = false
        transcript.isEditable = false
        transcript.isSelectable = true
        transcript.textContainerInset = .zero
        transcript.textContainer?.lineFragmentPadding = 0
        transcript.textContainer?.widthTracksTextView = true
        transcript.textContainer?.containerSize = NSSize(width: 212, height: CGFloat.greatestFiniteMagnitude)
        transcript.font = .systemFont(ofSize: 12)
        documentView = transcript
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(text: String, placeholder: String, accessibilityLabel: String) {
        transcript.setAccessibilityLabel(accessibilityLabel)
        transcript.textColor = text.isEmpty ? .secondaryLabelColor : .labelColor
        let displayed = text.isEmpty ? placeholder : text
        guard transcript.string != displayed else { return }
        let selection = transcript.selectedRange()
        transcript.string = displayed
        if selection.length > 0, NSMaxRange(selection) <= (displayed as NSString).length {
            transcript.setSelectedRange(selection)
        }
        followsLatest = selection.length == 0
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let size = contentView.bounds.size
        guard size.width > 0, followsLatest || viewportSize != size else { return }
        followsLatest = false
        viewportSize = size
        guard let container = transcript.textContainer, let manager = transcript.layoutManager else { return }
        container.containerSize = NSSize(width: size.width, height: CGFloat.greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        let textHeight = ceil(manager.usedRect(for: container).height)
        transcript.setFrameSize(NSSize(width: size.width, height: max(size.height, textHeight)))
        contentView.scroll(to: NSPoint(x: 0, y: max(0, transcript.frame.height - size.height)))
        reflectScrolledClipView(contentView)
    }
}
