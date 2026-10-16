import AppKit
import SwiftUI
import UserNotifications

@main
struct CodexQuotaIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Codex 额度", systemImage: "gauge.with.dots.needle.50percent") {
            QuotaMenuContent(model: AppRuntime.shared.model)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct QuotaMenuContent: View {
    @ObservedObject var model: QuotaViewModel

    var body: some View {
        Group {
            Button("立即刷新") { model.refresh() }
            Divider()
            if let snapshot = model.snapshot {
                Text("5小时：剩余 \(snapshot.fiveHour.remainingPercent)%")
                Text("一周：剩余 \(snapshot.weekly.remainingPercent)%")
            } else {
                Text("等待额度数据")
            }
            Divider()
            Button("退出 Codex 额度精灵岛") { NSApp.terminate(nil) }
        }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in AppRuntime.shared.start() }
    }
}

@MainActor
private final class AppRuntime {
    static let shared = AppRuntime()
    let model = QuotaViewModel()
    private var hasStarted = false

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        IslandPanelController.shared.show(model: model)
        model.start()
    }
}

@MainActor
final class IslandPanelController {
    static let shared = IslandPanelController()
    private var panel: NSPanel?

    func show(model: QuotaViewModel) {
        guard panel == nil else { return }
        let size = NSSize(width: 352, height: 48)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: IslandView(model: model))

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 8))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }
}
