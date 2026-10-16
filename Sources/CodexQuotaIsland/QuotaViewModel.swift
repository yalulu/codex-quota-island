import AppKit
import Foundation
import UserNotifications

@MainActor
final class QuotaViewModel: ObservableObject {
    enum ConnectionState: Equatable {
        case connecting
        case current
        case stale(String)
    }

    @Published private(set) var snapshot: QuotaSnapshot?
    @Published private(set) var connectionState: ConnectionState = .connecting
    @Published private(set) var isRefreshing = false

    private let client = AppServerClient()
    private var refreshTimer: Timer?
    private var hasStarted = false
    private let alertStoreKey = "alertedQuotaWindows"
    private let refreshInterval: TimeInterval

    init(userDefaults: UserDefaults = .standard) {
        let configuredSeconds = userDefaults.object(forKey: QuotaPolicy.refreshIntervalDefaultsKey) as? NSNumber
        refreshInterval = QuotaPolicy.refreshInterval(configuredSeconds: configuredSeconds?.doubleValue)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        client.onDisconnected = { [weak self] error in
            self?.connectionState = .stale(error.localizedDescription)
        }
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        connectionState = .connecting
        Task {
            defer { client.disconnect() }
            do {
                let freshSnapshot = try await client.readQuotaSnapshot()
                snapshot = freshSnapshot
                connectionState = .current
                deliverLowQuotaAlertIfNeeded(for: freshSnapshot)
            } catch {
                connectionState = .stale(error.localizedDescription)
            }
            isRefreshing = false
        }
    }

    func formattedReset(_ window: RateLimitWindow) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: window.resetAt)
    }

    private func deliverLowQuotaAlertIfNeeded(for snapshot: QuotaSnapshot) {
        let alreadyAlerted = Set(UserDefaults.standard.stringArray(forKey: alertStoreKey) ?? [])
        let freshKeys = QuotaPolicy.alertKeys(for: snapshot).filter { !alreadyAlerted.contains($0) }
        guard !freshKeys.isEmpty else { return }

        UserDefaults.standard.set(Array(Array(alreadyAlerted.union(freshKeys)).suffix(20)), forKey: alertStoreKey)
        let names = snapshot.lowWindows.map(\.label).joined(separator: "、")
        let content = UNMutableNotificationContent()
        content.title = "Codex 额度剩余不超过 10%"
        content.body = "\(names)额度已进入低余量状态，请留意后续使用。"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "codex-quota-low-\(freshKeys.joined(separator: "-"))", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        NSApp.requestUserAttention(.criticalRequest)
    }
}
