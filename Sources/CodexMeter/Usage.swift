import Foundation

struct UsageWindow: Codable, Equatable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Double?

    var remaining: Double { min(100, max(0, 100 - usedPercent)) }
    var title: String {
        guard let minutes = windowDurationMins else { return "Usage window" }
        if minutes == 10_080 { return "Weekly" }
        if minutes == 1_440 { return "Daily" }
        if minutes % 60 == 0 { return "\(minutes / 60)-hour window" }
        return "\(minutes)-minute window"
    }
    func resetText(now: Date = Date()) -> String {
        guard let resetsAt else { return "Reset time unavailable" }
        let seconds = resetsAt - now.timeIntervalSince1970
        guard seconds > 0 else { return "Reset due · refresh to confirm" }
        let minutes = max(1, Int(ceil(seconds / 60)))
        if minutes >= 1_440 { return "Resets in \(minutes / 1_440)d \((minutes % 1_440) / 60)h" }
        if minutes >= 60 { return "Resets in \(minutes / 60)h \(minutes % 60)m" }
        return "Resets in \(minutes)m"
    }
    var resetDate: Date? { resetsAt.map(Date.init(timeIntervalSince1970:)) }
}

struct LimitBucket: Codable {
    let limitId: String?
    let limitName: String?
    let planType: String?
    let primary: UsageWindow?
    let secondary: UsageWindow?
    let rateLimitReachedType: String?
    let individualLimit: MonthlyLimit?
}

struct MonthlyLimit: Codable {
    let remainingPercent: Double
    let resetsAt: Double
}

struct LimitsResponse: Decodable {
    let accountId: String?
    let ordinaryUsageAllowed: Bool?
    let rateLimits: LimitBucket
    let rateLimitsByLimitId: [String: LimitBucket]?

    var buckets: [(id: String, bucket: LimitBucket)] {
        guard let values = rateLimitsByLimitId, !values.isEmpty else {
            return [(rateLimits.limitId ?? "codex", rateLimits)]
        }
        return values.keys.sorted { lhs, rhs in
            if lhs == rhs { return false }
            if lhs == "codex" { return true }
            if rhs == "codex" { return false }
            return lhs < rhs
        }.compactMap { key in values[key].map { (key, $0) } }
    }

    var mainBucket: LimitBucket { buckets.first?.bucket ?? rateLimits }
    var remaining: Double? { mainBucket.primary?.remaining ?? mainBucket.secondary?.remaining }
    var blocked: Bool {
        ordinaryUsageAllowed == false || mainBucket.rateLimitReachedType != nil
    }
}

struct TokenActivity: Decodable {
    struct Summary: Decodable { let lifetimeTokens: Int64? }
    struct Day: Decodable, Equatable {
        let startDate: String
        let tokens: Int64
    }
    let summary: Summary
    let dailyUsageBuckets: [Day]?
    var days: [Day] { (dailyUsageBuckets ?? []).sorted { $0.startDate < $1.startDate } }
    var latest: Day? { days.last }
}

struct UsageSnapshot {
    let limits: LimitsResponse
    let activity: TokenActivity?
    let activityUnavailable: Bool
    let fetchedAt: Date
}

enum MeterError: LocalizedError {
    case missingCLI, timeout, disconnected, invalidResponse, signedOut, apiKeyAccount, remote(String)
    var errorDescription: String? {
        switch self {
        case .missingCLI: return "Codex couldn’t be found. Choose its executable from the settings menu."
        case .timeout: return "The usage request timed out. Check your connection and try again."
        case .disconnected: return "The Codex connection closed. Try refreshing."
        case .invalidResponse: return "Codex returned an unsupported response. Update Codex and try again."
        case .signedOut: return "Sign in to Codex with your ChatGPT account, then refresh."
        case .apiKeyAccount: return "This connection uses an API key. Sign in to Codex with ChatGPT to read subscription limits."
        case .remote(let message): return message
        }
    }
}

enum CodexLocation {
    static func find(override: String? = nil) -> URL? {
        let bundled = "/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
        var paths = [override].compactMap { $0 }
        paths += ["/Applications/ChatGPT.app" + bundled,
                  "/Applications/Codex.app/Contents/Resources/codex",
                  "/Applications/Codex.app" + bundled,
                  NSHomeDirectory() + "/Applications/ChatGPT.app" + bundled,
                  "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        paths += (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map { String($0) + "/codex" }
        return paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map(URL.init(fileURLWithPath:))
    }
}
