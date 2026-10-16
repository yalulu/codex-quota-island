import SwiftUI

struct IslandView: View {
    @ObservedObject var model: QuotaViewModel

    private var isCritical: Bool { model.snapshot?.hasLowQuota == true }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: isCritical ? "exclamationmark.triangle.fill" : "bolt.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isCritical ? .red : .mint)
                .symbolEffect(.pulse, options: isCritical ? .repeating : .default, isActive: isCritical)

            Text("Codex")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Divider().overlay(.white.opacity(0.22))

            if let snapshot = model.snapshot {
                MetricView(window: snapshot.fiveHour)
                MetricView(window: snapshot.weekly)
            } else {
                Text(model.connectionState == .connecting ? "正在读取额度…" : "额度数据不可用")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.86))
            }

            Circle()
                .fill(connectionColor)
                .frame(width: 7, height: 7)
                .accessibilityLabel(connectionLabel)
        }
        .padding(.horizontal, 18)
        .frame(width: 352, height: 48)
        .background(.black.opacity(0.92), in: Capsule())
        .overlay(Capsule().stroke(isCritical ? Color.red.opacity(0.9) : .white.opacity(0.14), lineWidth: isCritical ? 1.5 : 1))
        .shadow(color: isCritical ? .red.opacity(0.36) : .black.opacity(0.35), radius: isCritical ? 15 : 9, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Codex 额度状态")
    }

    private var connectionColor: Color {
        switch model.connectionState {
        case .current: .green
        case .connecting: .orange
        case .stale: .red
        }
    }

    private var connectionLabel: String {
        switch model.connectionState {
        case .current: "数据已更新"
        case .connecting: "正在刷新"
        case .stale: "数据已过期"
        }
    }
}

private struct MetricView: View {
    let window: RateLimitWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(window.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
            Text("剩余 \(window.remainingPercent)%")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(window.isLow ? .red : .white)
        }
        .accessibilityLabel("\(window.label)额度剩余\(window.remainingPercent)%")
    }
}
