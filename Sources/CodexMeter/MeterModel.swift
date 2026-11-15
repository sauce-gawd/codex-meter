import AppKit
import Combine
import ServiceManagement

@MainActor
final class MeterModel: ObservableObject {
    @Published var snapshot: UsageSnapshot?
    @Published var refreshing = false
    @Published var error: String?
    @Published var lastAttempt: Date?
    @Published var refreshMinutes: Int {
        didSet { UserDefaults.standard.set(refreshMinutes, forKey: "refreshMinutes"); schedule() }
    }
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    let preview: Bool
    private var timer: Timer?
    private let client = CodexClient()

    init(preview: Bool = false) {
        self.preview = preview
        let saved = UserDefaults.standard.integer(forKey: "refreshMinutes")
        refreshMinutes = [1, 3, 5, 15].contains(saved) ? saved : 3
        if preview { snapshot = Self.example }
        else { schedule(); Task { await refresh() } }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in await self?.refresh() } }
    }

    var isStale: Bool {
        guard let snapshot else { return false }
        return error != nil || Date().timeIntervalSince(snapshot.fetchedAt) > Double(refreshMinutes * 120)
    }

    var statusText: String {
        if preview { return "Preview · sample data" }
        if refreshing { return "Refreshing…" }
        if isStale { return "Last known usage · update needed" }
        guard let date = snapshot?.fetchedAt else { return "Not connected" }
        return "Updated \(date.formatted(date: .omitted, time: .shortened))"
    }

    func schedule() {
        timer?.invalidate()
        guard !preview else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Double(refreshMinutes * 60), repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        timer?.tolerance = 15
    }

    func refreshIfNeeded() async {
        guard !preview else { return }
        if let lastAttempt, Date().timeIntervalSince(lastAttempt) < 30 { return }
        await refresh()
    }

    func refresh() async {
        guard !refreshing, !preview else { return }
        refreshing = true
        lastAttempt = Date()
        defer { refreshing = false }
        guard let executable = CodexLocation.find(override: UserDefaults.standard.string(forKey: "codexPath")) else {
            error = MeterError.missingCLI.localizedDescription
            return
        }
        do {
            snapshot = try await client.fetch(executable: executable)
            error = nil
        } catch {
            // Authentication changes must not keep another account's previous snapshot visible.
            if let issue = error as? MeterError {
                switch issue {
                case .signedOut, .apiKeyAccount: snapshot = nil
                default: break
                }
            }
            self.error = error.localizedDescription
        }
    }

    func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.title = "Choose the Codex executable"
        panel.message = "Select the codex command-line executable, or ChatGPT/Codex app containing it."
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path: String
        if url.pathExtension == "app" {
            let candidates = [url.appendingPathComponent("Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"),
                              url.appendingPathComponent("Contents/Resources/codex")]
            guard let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
                error = "That app does not contain a supported Codex executable."; return
            }
            path = found.path
        } else { path = url.path }
        guard FileManager.default.isExecutableFile(atPath: path) else {
            error = "Select an executable file."; return
        }
        UserDefaults.standard.set(path, forKey: "codexPath")
        snapshot = nil
        Task { await refresh() }
    }

    func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval {
                error = "Allow Codex Meter in System Settings → General → Login Items."
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch { self.error = "Couldn’t change launch at login. Open the app from a permanent location and try again." }
    }

    static var example: UsageSnapshot {
        let reset = Date().addingTimeInterval(8_040).timeIntervalSince1970
        let limits = try! JSONDecoder().decode(LimitsResponse.self, from: Data("""
        {"ordinaryUsageAllowed":true,"rateLimits":{"limitId":"codex","planType":"plus",
        "primary":{"usedPercent":28,"windowDurationMins":300,"resetsAt":\(reset)},
        "secondary":{"usedPercent":46,"windowDurationMins":10080,"resetsAt":\(reset + 259200)}}}
        """.utf8))
        let activity = try! JSONDecoder().decode(TokenActivity.self, from: Data("""
        {"summary":{"lifetimeTokens":4821400},"dailyUsageBuckets":[
        {"startDate":"2026-11-09","tokens":48200},{"startDate":"2026-11-10","tokens":72100},
        {"startDate":"2026-11-11","tokens":58100},{"startDate":"2026-11-12","tokens":103500},
        {"startDate":"2026-11-13","tokens":84900},{"startDate":"2026-11-14","tokens":92300},
        {"startDate":"2026-11-15","tokens":128400}]}
        """.utf8))
        return UsageSnapshot(limits: limits, activity: activity, activityUnavailable: false, fetchedAt: Date())
    }
}
