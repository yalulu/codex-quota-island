import Foundation

struct RateLimitWindow: Equatable, Sendable {
    let label: String
    let usedPercent: Int
    let resetAt: Date

    var remainingPercent: Int { max(0, min(100, 100 - usedPercent)) }
    var isLow: Bool { remainingPercent <= QuotaPolicy.warningThreshold }
}

struct QuotaSnapshot: Equatable, Sendable {
    let fiveHour: RateLimitWindow
    let weekly: RateLimitWindow
    let fetchedAt: Date

    var hasLowQuota: Bool { fiveHour.isLow || weekly.isLow }
    var lowWindows: [RateLimitWindow] { [fiveHour, weekly].filter(\.isLow) }
}

enum QuotaPolicy {
    static let warningThreshold = 10
    static let defaultRefreshInterval: TimeInterval = 60
    static let minimumRefreshInterval: TimeInterval = 10
    static let maximumRefreshInterval: TimeInterval = 3_600
    static let refreshIntervalDefaultsKey = "refreshIntervalSeconds"

    static func refreshInterval(configuredSeconds: Double?) -> TimeInterval {
        guard let configuredSeconds else { return defaultRefreshInterval }
        return min(max(configuredSeconds, minimumRefreshInterval), maximumRefreshInterval)
    }

    static func alertKeys(for snapshot: QuotaSnapshot) -> [String] {
        snapshot.lowWindows.map { "\($0.label)-\(Int($0.resetAt.timeIntervalSince1970))" }
    }
}

enum QuotaDecodeError: LocalizedError {
    case missingCodexBucket
    case missingWindow(String)

    var errorDescription: String? {
        switch self {
        case .missingCodexBucket: "未从 Codex 返回中找到额度桶。"
        case let .missingWindow(name): "Codex 未返回\(name)额度窗口。"
        }
    }
}

struct RateLimitResponse: Decodable {
    let rateLimitsByLimitId: [String: RateLimitBucket]

    struct RateLimitBucket: Decodable {
        let primary: Window?
        let secondary: Window?
    }

    struct Window: Decodable {
        let usedPercent: Int
        let windowDurationMins: Int
        let resetsAt: TimeInterval
    }

    func quotaSnapshot(now: Date = .now) throws -> QuotaSnapshot {
        guard let bucket = rateLimitsByLimitId["codex"] else {
            throw QuotaDecodeError.missingCodexBucket
        }
        guard let primary = bucket.primary else {
            throw QuotaDecodeError.missingWindow("5 小时")
        }
        guard let secondary = bucket.secondary else {
            throw QuotaDecodeError.missingWindow("一周")
        }
        return QuotaSnapshot(
            fiveHour: RateLimitWindow(label: primary.windowDurationMins == 300 ? "5小时" : "短周期", usedPercent: primary.usedPercent, resetAt: Date(timeIntervalSince1970: primary.resetsAt)),
            weekly: RateLimitWindow(label: secondary.windowDurationMins == 10_080 ? "1周" : "长周期", usedPercent: secondary.usedPercent, resetAt: Date(timeIntervalSince1970: secondary.resetsAt)),
            fetchedAt: now
        )
    }
}
