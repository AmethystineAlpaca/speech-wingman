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
    func applicationDidFinishLaunching(_ notification: Notification) {
        floatingControl.install(controller: AppSession.controller)
    }
    func applicationWillTerminate(_ notification: Notification) { floatingControl.close() }
}

@main
struct WingmanApp: App {
    @NSApplicationDelegateAdaptor(WingmanAppDelegate.self) private var delegate
    @StateObject private var controller = AppSession.controller
    var body: some Scene {
        MenuBarExtra("Speech Wingman", systemImage: controller.state == .listening ? "mic.fill" : "mic") {
            SessionView(controller: controller)
        }.menuBarExtraStyle(.window)
        Window(Text(controller.t("提醒设置")), id: "settings") { SettingsView(controller: controller) }
            .defaultSize(width: 620, height: 760)
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

struct SettingsView: View {
    @ObservedObject var controller: SessionController
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker(controller.t("界面语言"), selection: $controller.language) {
                ForEach(DisplayLanguage.allCases, id: \.self) { language in
                    Text(language.name).tag(language)
                }
            }
            Text(controller.t("只改变界面显示；录音始终自动识别中文、英文和中英混合。"))
                .font(.caption).foregroundStyle(.secondary)
            Toggle(controller.t("桌面悬浮按钮"), isOn: $controller.floatingControlVisible)
            Divider()
            Text(controller.t("本地语音处理")).font(.title2)
            Text(controller.t("中英自动 ASR + Qwen3 4B 文本判断"))
            Text(controller.t("中文、英文和混合发言自动识别，无需切换语言。模型已随应用打包，运行不联网。转录持续显示，判断在后台进行。"))
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Text(controller.t("提醒条件")).font(.title2)
            Text(controller.t("每行一条规则，命中任意一条就提醒。每条的例外条件写在同一行。提醒语言跟随当前发言。")).foregroundStyle(.secondary)
            Text(controller.t("例如：说到 banana 就提醒。\n说汤姆的坏话就提醒，赞扬他不提醒。"))
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $controller.prompt).font(.body)
                .padding(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray.opacity(0.3)))
            Picker(controller.t("敏感度"), selection: $controller.sensitivity) {
                Text(controller.t("低")).tag(Sensitivity.low)
                Text(controller.t("中")).tag(Sensitivity.medium)
                Text(controller.t("高")).tag(Sensitivity.high)
            }.pickerStyle(.segmented)
            HStack {
                Text(controller.language.format("%d / 4000 字", controller.prompt.count)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(controller.t("保存并应用")) { Task { await controller.applySettings() } }
                    .disabled(controller.state == .loading)
            }
            Text(controller.t("应用新条件时会取消旧判断，并从新的音频片段开始。麦克风中的其他人声也会参与判断。")).font(.caption).foregroundStyle(.secondary)
        }.padding(24)
            .environment(\.locale, controller.language.locale)
    }
}
