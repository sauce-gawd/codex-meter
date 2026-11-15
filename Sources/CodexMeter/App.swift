import SwiftUI
import AppKit

struct MeterApplication: App {
    @StateObject private var model = MeterModel(preview: CommandLine.arguments.contains("--preview"))
    var body: some Scene {
        MenuBarExtra { MeterPanel(model: model) } label: { MeterLabel(model: model) }
            .menuBarExtraStyle(.window)
    }
}

@main
enum Launcher {
    @MainActor
    static func main() async {
        if CommandLine.arguments.contains("--check-connection") {
            guard let executable = CodexLocation.find() else {
                print("FAIL: Codex executable not found."); exit(1)
            }
            do {
                let snapshot = try await CodexClient().fetch(executable: executable)
                print("PASS: Authenticated metadata connection; \(snapshot.limits.buckets.count) usage bucket(s).")
                print("Usage windows: \(snapshot.limits.buckets.reduce(0) { $0 + ($1.bucket.primary == nil ? 0 : 1) + ($1.bucket.secondary == nil ? 0 : 1) }).")
                print("Token activity: \(snapshot.activity == nil ? "unavailable" : "available").")
                print("No model turns started. No credentials or raw account data logged.")
            } catch { print("FAIL: \(error.localizedDescription)"); exit(1) }
            return
        }
        if let flag = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > flag + 1 {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let panel = NSHostingView(rootView: MeterPanel(model: MeterModel(preview: true)).environment(\.colorScheme, .light))
            panel.frame = NSRect(origin: .zero, size: panel.fittingSize)
            panel.layoutSubtreeIfNeeded()
            guard let bitmap = panel.bitmapImageRepForCachingDisplay(in: panel.bounds) else { exit(1) }
            panel.cacheDisplay(in: panel.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
            do { try png.write(to: URL(fileURLWithPath: CommandLine.arguments[flag + 1])) }
            catch { print("Preview export failed."); exit(1) }
            print("Rendered native panel preview.")
            return
        }
        NSApplication.shared.setActivationPolicy(.accessory)
        MeterApplication.main()
    }
}
