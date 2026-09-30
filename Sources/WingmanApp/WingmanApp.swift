import SwiftUI
import AppKit
import WingmanCore

@MainActor
private enum AppSession {
    static let controller = SessionController()
}

@MainActor
final class WingmanAppDelegate: NSObject, NSApplicationDelegate {
    private let floatingControl = FloatingControlPresenter()
    func installFloatingControl(openSettings: @escaping () -> Void) {
        floatingControl.install(controller: AppSession.controller, openSettings: openSettings)
    }
    func applicationWillTerminate(_ notification: Notification) { floatingControl.close() }
}

@main
struct WingmanApp: App {
    @NSApplicationDelegateAdaptor(WingmanAppDelegate.self) private var delegate
    @StateObject private var controller = AppSession.controller
    var body: some Scene {
        MenuBarExtra {
            SessionView(controller: controller)
        } label: {
            WingmanMenuBarLabel(controller: controller, delegate: delegate)
        }.menuBarExtraStyle(.window)
        Window(Text(controller.t("提醒设置")), id: "settings") { SettingsView(controller: controller) }
            .defaultSize(width: 680, height: 820)
    }
}

/// Capture the scene's window action inside SwiftUI before passing it to the
/// AppKit floating panel, which has no openWindow environment of its own.
private struct WingmanMenuBarLabel: View {
    @ObservedObject var controller: SessionController
    let delegate: WingmanAppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: controller.state == .listening ? "mic.fill" : "mic")
            .accessibilityLabel("Speech Wingman")
            .onAppear {
                delegate.installFloatingControl {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
    }
}

struct SessionView: View {
    @ObservedObject var controller: SessionController
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(controller.t("Speech Wingman 实验版")).font(.headline)
                Spacer()
                if controller.processing { ProgressView().controlSize(.small) }
                Text(controller.t("中英双语 · 离线")).foregroundStyle(.secondary)
            }
            Text(controller.t(controller.status)).font(.caption).foregroundStyle(.secondary)
            if controller.state == .listening {
                HStack {
                    Text(controller.t("麦克风")).font(.caption2)
                    ProgressView(value: Double(min(1, controller.inputLevel / 0.04))).frame(width: 100)
                    if let started = controller.processingStartedAt {
                        TimelineView(.periodic(from: started, by: 1)) { tick in
                            Text(controller.language.format("本次判断已处理 %.0f 秒", tick.date.timeIntervalSince(started)))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            HStack {
                switch controller.state {
                case .idle, .failed:
                    Button(controller.t("开始监听")) { Task { await controller.start() } }
                case .loading: Text(controller.t("加载中…"))
                case .listening: Button(controller.t("暂停")) { Task { await controller.pause() } }
                case .paused: Button(controller.t("继续")) { Task { await controller.resume() } }
                }
                if controller.state != .idle {
                    Button(controller.t("停止并清空")) { Task { await controller.stop() } }
                }
                Spacer()
                Button(controller.t("设置")) { openWindow(id: "settings"); NSApp.activate(ignoringOtherApps: true) }
            }
            if let alert = controller.activeAlert {
                let alertLanguage = controller.activeAlertLanguage
                VStack(alignment: .leading, spacing: 8) {
                    Text(alertLanguage.text("提醒")).font(.headline)
                    Text(alertLanguage.format("原话：%@", alert.quote)).textSelection(.enabled)
                    Text(alert.suggestion).fontWeight(.medium)
                    HStack {
                        Button(alertLanguage.text("关闭")) { controller.dismissAlert() }
                        Button(alertLanguage.text("静音一小时")) { controller.mute() }
                    }
                }.padding().background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
            if let until = controller.mutedUntil, until > Date() {
                HStack {
                    Text(controller.language.format("提醒静音至 %@", until.formatted(.dateTime.hour().minute().locale(controller.language.locale)))).font(.caption)
                    Button(controller.t("取消静音")) { controller.unmute() }
                }
            }
            Toggle(controller.t("桌面悬浮按钮"), isOn: $controller.floatingControlVisible)
            Text(controller.t("当前会话转写")).font(.subheadline)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if controller.transcript.isEmpty && controller.preview.isEmpty {
                        Text(controller.t("手动开始后监听麦克风中的所有人声。未满足提醒条件时保持安静。"))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(controller.transcript) { entry in
                        Text(entry.text)
                            .foregroundStyle(Color.primary)
                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }
                    if !controller.preview.isEmpty {
                        Text(controller.preview).foregroundStyle(.secondary)
                        Text(controller.t("实时转录中…")).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }.frame(minHeight: 100, maxHeight: 260)
            HStack {
                Button(controller.t("主动导出会话")) { controller.export() }.disabled(controller.transcript.isEmpty)
                Spacer()
                if controller.elapsed > 0 { Text(controller.language.format("判断 %.1f 秒", controller.elapsed)).font(.caption2) }
            }
            if controller.resultDelay > 0 {
                Text(controller.language.format("转录定稿后 %.1f 秒完成判断（排队 %.1f 秒）", controller.resultDelay, controller.queueDelay))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text(controller.t("默认不保存音频。选择“停止并清空”会清空本次转写与提醒。")).font(.caption2).foregroundStyle(.secondary)
            Divider()
            Button(controller.t("退出")) { Task { await controller.stop(); NSApp.terminate(nil) } }
        }.padding(18).frame(width: 470)
            .environment(\.locale, controller.language.locale)
    }
}

// Use the property wrapper explicitly when SDKs also expose a State macro.
private typealias SettingsState<Value> = State<Value>

struct SettingsView: View {
    @ObservedObject var controller: SessionController
    @SettingsState private var saved = false

    private var validPrompt: Bool {
        !controller.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && controller.prompt.count <= 4_000
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(controller.t("提醒条件")).font(.title2.bold())
                        help("每行一条规则，命中任意一条就提醒。每条的例外条件写在同一行。提醒语言跟随当前发言。")
                        TextEditor(text: $controller.prompt)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .padding(12)
                            .frame(height: 240)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.primary.opacity(0.15)))
                            .accessibilityLabel(controller.t("提醒条件"))
                        HStack(alignment: .top) {
                            Text(controller.t("回车新建规则；长句会自动换行。"))
                            Spacer()
                            Text(controller.language.format("%d / 4000 字", controller.prompt.count))
                                .foregroundStyle(controller.prompt.count > 4_000 ? Color.red : Color.secondary)
                        }.font(.caption).foregroundStyle(.secondary)
                        DisclosureGroup(controller.t("查看规则示例")) {
                            help("例如：说到 banana 就提醒。\n说汤姆的坏话就提醒，赞扬他不提醒。")
                                .padding(.top, 4)
                        }.font(.caption)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(controller.t("敏感度")).font(.headline)
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(Sensitivity.allCases, id: \.self) { sensitivity in
                                sensitivityButton(sensitivity)
                            }
                        }
                        help(controller.sensitivity.descriptionKey)
                        help("所有档位都遵守规则中的例外条件。高敏感度可能增加误报，也不能保证不漏报。")
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Picker(controller.t("界面语言"), selection: $controller.language) {
                            ForEach(DisplayLanguage.allCases, id: \.self) { language in
                                Text(language.name).tag(language)
                            }
                        }
                        help("只改变界面显示；录音始终自动识别中文、英文和中英混合。")
                        Toggle(controller.t("桌面悬浮按钮"), isOn: $controller.floatingControlVisible)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Label(controller.t("本地语音处理"), systemImage: "desktopcomputer").font(.headline)
                        Text(controller.t("中英自动 ASR + Qwen3 4B 文本判断")).font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        help("中文、英文和混合发言自动识别，无需切换语言。模型已随应用打包，运行不联网。转录持续显示，判断在后台进行。")
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if !validPrompt {
                        Text(controller.t("请填写最多 4000 字的提醒条件")).foregroundStyle(.red)
                    } else if saved {
                        Label(controller.t("提醒条件已保存"), systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(controller.t("保存并应用")) {
                        Task {
                            await controller.applySettings()
                            saved = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(controller.state == .loading || !validPrompt)
                }.font(.callout)
                help("应用新条件时会取消旧判断，并从新的音频片段开始。麦克风中的其他人声也会参与判断。")
            }.padding(.horizontal, 24).padding(.vertical, 16)
        }
        .frame(minWidth: 540, minHeight: 520)
        .environment(\.locale, controller.language.locale)
        .onChange(of: controller.prompt) { _, _ in saved = false }
        .onChange(of: controller.sensitivity) { _, _ in saved = false }
    }

    private func help(_ key: String) -> some View {
        Text(controller.t(key)).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sensitivityButton(_ value: Sensitivity) -> some View {
        let selected = controller.sensitivity == value
        return Button { controller.sensitivity = value } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(controller.t(value.titleKey)).font(.body.weight(.semibold))
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                }
                Text(controller.t(value.summaryKey)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12).frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
            .background(selected ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(controller.t(value.descriptionKey))
    }
}
