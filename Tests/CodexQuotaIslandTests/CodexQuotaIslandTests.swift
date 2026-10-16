import XCTest
@testable import CodexQuotaIsland

final class CodexQuotaIslandTests: XCTestCase {
    func testRemainingPercentageAndThreshold() {
        let warning = RateLimitWindow(label: "5小时", usedPercent: 90, resetAt: .now)
        let normal = RateLimitWindow(label: "1周", usedPercent: 89, resetAt: .now)
        XCTAssertEqual(warning.remainingPercent, 10)
        XCTAssertTrue(warning.isLow)
        XCTAssertFalse(normal.isLow)
    }

    func testDecodesFiveHourAndWeeklyWindows() throws {
        let json = """
        {"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":90,"windowDurationMins":300,"resetsAt":1792133042},"secondary":{"usedPercent":24,"windowDurationMins":10080,"resetsAt":1792656619}}}}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(RateLimitResponse.self, from: json)
        let snapshot = try response.quotaSnapshot(now: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(snapshot.fiveHour.label, "5小时")
        XCTAssertEqual(snapshot.fiveHour.remainingPercent, 10)
        XCTAssertEqual(snapshot.weekly.label, "1周")
        XCTAssertEqual(snapshot.weekly.remainingPercent, 76)
        XCTAssertTrue(snapshot.hasLowQuota)
    }

    func testAlertKeysAreStablePerResetWindow() {
        let reset = Date(timeIntervalSince1970: 1_792_133_042)
        let snapshot = QuotaSnapshot(
            fiveHour: RateLimitWindow(label: "5小时", usedPercent: 91, resetAt: reset),
            weekly: RateLimitWindow(label: "1周", usedPercent: 20, resetAt: reset),
            fetchedAt: .now
        )
        XCTAssertEqual(QuotaPolicy.alertKeys(for: snapshot), ["5小时-1792133042"])
    }

    func testRefreshIntervalDefaultsAndBounds() {
        XCTAssertEqual(QuotaPolicy.refreshInterval(configuredSeconds: nil), 60)
        XCTAssertEqual(QuotaPolicy.refreshInterval(configuredSeconds: 10), 10)
        XCTAssertEqual(QuotaPolicy.refreshInterval(configuredSeconds: 3), 10)
        XCTAssertEqual(QuotaPolicy.refreshInterval(configuredSeconds: 7_200), 3_600)
    }
}
