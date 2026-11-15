#if STANDALONE_CHECKS
import Foundation
class XCTestCase {}
func XCTAssertEqual<T: Equatable>(_ lhs: T, _ rhs: T) { precondition(lhs == rhs, "Expected \(rhs), got \(lhs)") }
func XCTAssertTrue(_ value: Bool) { precondition(value) }
func XCTAssertNil<T>(_ value: T?) { precondition(value == nil) }
#else
import XCTest
@testable import CodexMeter
#endif

final class UsageTests: XCTestCase {
    func testRemainingIsClamped() {
        XCTAssertEqual(UsageWindow(usedPercent: 130, windowDurationMins: nil, resetsAt: nil).remaining, 0)
        XCTAssertEqual(UsageWindow(usedPercent: -10, windowDurationMins: nil, resetsAt: nil).remaining, 100)
    }

    func testWindowsUseServiceDurationRatherThanAssumingDailyQuota() {
        XCTAssertEqual(UsageWindow(usedPercent: 28, windowDurationMins: 300, resetsAt: nil).title, "5-hour window")
        XCTAssertEqual(UsageWindow(usedPercent: 28, windowDurationMins: 10080, resetsAt: nil).title, "Weekly")
        XCTAssertEqual(UsageWindow(usedPercent: 28, windowDurationMins: nil, resetsAt: nil).title, "Usage window")
    }

    func testElapsedResetDoesNotInventFreshAllowance() {
        let window = UsageWindow(usedPercent: 100, windowDurationMins: 300, resetsAt: 1000)
        XCTAssertEqual(window.resetText(now: Date(timeIntervalSince1970: 1100)), "Reset due · refresh to confirm")
        XCTAssertEqual(window.remaining, 0)
    }

    func testCountdownRoundsUpToAvoidZeroMinutes() {
        let window = UsageWindow(usedPercent: 20, windowDurationMins: 300, resetsAt: 1020)
        XCTAssertEqual(window.resetText(now: Date(timeIntervalSince1970: 1000)), "Resets in 1m")
    }

    func testMultiBucketAndBackendRestriction() throws {
        let limits = try JSONDecoder().decode(LimitsResponse.self, from: Data("""
        {"ordinaryUsageAllowed":false,"rateLimits":{},"rateLimitsByLimitId":{
        "other":{"primary":{"usedPercent":10}},"codex":{"primary":{"usedPercent":90}}}}
        """.utf8))
        XCTAssertEqual(limits.buckets.first?.id, "codex")
        XCTAssertEqual(limits.remaining, 10)
        XCTAssertTrue(limits.blocked)
    }

    func testLegacySingleBucketAndNullWindows() throws {
        let limits = try JSONDecoder().decode(LimitsResponse.self, from: Data("""
        {"rateLimits":{"primary":null,"secondary":null},"rateLimitsByLimitId":null}
        """.utf8))
        XCTAssertNil(limits.remaining)
        XCTAssertEqual(limits.buckets.count, 1)
    }

    func testDailyActivitySortsDatesAndDoesNotFillMissingDays() throws {
        let activity = try JSONDecoder().decode(TokenActivity.self, from: Data("""
        {"summary":{"lifetimeTokens":null},"dailyUsageBuckets":[
        {"startDate":"2026-11-15","tokens":100},{"startDate":"2026-11-13","tokens":200}]}
        """.utf8))
        XCTAssertEqual(activity.latest?.tokens, 100)
        XCTAssertEqual(activity.days.count, 2)
        XCTAssertNil(activity.summary.lifetimeTokens)
    }

    func testMissingDailyActivityIsNotReportedAsZero() throws {
        let activity = try JSONDecoder().decode(TokenActivity.self, from: Data("""
        {"summary":{},"dailyUsageBuckets":null}
        """.utf8))
        XCTAssertNil(activity.latest)
    }

    func testReadOnlyProtocolAndOptionalActivityFailure() async throws {
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let script = #"""
        #!/bin/sh
        exec /usr/bin/awk '
        /"method":"initialize"/ { print "{\"id\":1,\"result\":{}}"; fflush(); next }
        /"method":"account\/read"/ { print "{\"id\":2,\"result\":{\"account\":{\"type\":\"chatgpt\"}}}"; fflush(); next }
        /"method":"account\/rateLimits\/read"/ { print "{\"id\":3,\"result\":{\"rateLimits\":{\"primary\":{\"usedPercent\":37}}}}"; fflush(); next }
        /"method":"account\/usage\/read"/ { print "{\"id\":4,\"error\":{\"code\":-32601,\"message\":\"unavailable\"}}"; fflush(); next }
        /"method":"initialized"/ { next }
        { exit 9 }
        '
        """#
        try Data(script.utf8).write(to: fixture)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.path)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let snapshot = try await CodexClient().fetch(executable: fixture)
        XCTAssertEqual(snapshot.limits.remaining, 63)
        XCTAssertNil(snapshot.activity)
        XCTAssertTrue(snapshot.activityUnavailable)
    }
}

#if STANDALONE_CHECKS
@main
enum Checks {
    static func main() async throws {
        let tests = UsageTests()
        tests.testRemainingIsClamped()
        tests.testWindowsUseServiceDurationRatherThanAssumingDailyQuota()
        tests.testElapsedResetDoesNotInventFreshAllowance()
        tests.testCountdownRoundsUpToAvoidZeroMinutes()
        try tests.testMultiBucketAndBackendRestriction()
        try tests.testLegacySingleBucketAndNullWindows()
        try tests.testDailyActivitySortsDatesAndDoesNotFillMissingDays()
        try tests.testMissingDailyActivityIsNotReportedAsZero()
        try await tests.testReadOnlyProtocolAndOptionalActivityFailure()
        print("PASS: 9 checks, including the read-only protocol integration.")
    }
}
#endif
