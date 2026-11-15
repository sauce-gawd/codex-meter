import SwiftUI
import Charts

private let meterTeal = Color(red: 0.02, green: 0.57, blue: 0.52)

func usageColor(_ remaining: Double) -> Color {
    remaining <= 10 ? .red : remaining <= 25 ? .orange : meterTeal
}

struct MeterPanel: View {
    @ObservedObject var model: MeterModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let error = model.error { errorBanner(error) }
                    if let snapshot = model.snapshot {
                        if snapshot.limits.blocked {
                            Label("Included usage is currently restricted", systemImage: "exclamationmark.circle.fill")
                                .font(.callout).foregroundStyle(.orange)
                        }
                        ForEach(snapshot.limits.buckets, id: \.id) { entry in
                            VStack(alignment: .leading, spacing: 18) {
                                if snapshot.limits.buckets.count > 1 {
                                    Text(entry.bucket.limitName ?? entry.id)
                                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                }
                                if let window = entry.bucket.primary { WindowSection(window: window) }
                                if let window = entry.bucket.secondary { WindowSection(window: window) }
                                if entry.bucket.primary == nil && entry.bucket.secondary == nil {
                                    Text("Usage windows aren’t available for this bucket.")
                                        .font(.callout).foregroundStyle(.secondary)
                                }
                                if let monthly = entry.bucket.individualLimit {
                                    WindowSection(window: UsageWindow(usedPercent: 100 - monthly.remainingPercent,
                                        windowDurationMins: nil, resetsAt: monthly.resetsAt), title: "Monthly credit limit")
                                }
                            }
                        }
                        Divider()
                        tokenSection(snapshot)
                    } else if model.refreshing {
                        VStack(spacing: 12) {
                            ProgressView().controlSize(.small)
                            Text("Reading your usage…").foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 36)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "gauge.with.dots.needle.33percent").font(.largeTitle).foregroundStyle(meterTeal)
                            Text("Your allowance, at a glance").font(.headline)
                            Text("Uses your existing Codex sign-in to read remaining allowance and reset times.")
                                .font(.callout).foregroundStyle(.secondary)
                            Button("Choose Codex…") { model.chooseExecutable() }
                        }.padding(.vertical, 12)
                    }
                }.padding(22)
            // MenuBarExtra asks for the minimum fitting size. A flexible
            // ScrollView can report zero height and hide its entire contents.
            // Reserve an explicit viewport, including before data arrives.
            }.frame(height: model.snapshot == nil ? 240 : 460)
            Divider()
            footer
        }
        .frame(width: 354)
        .background(.regularMaterial)
        .task { await model.refreshIfNeeded() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "gauge.with.dots.needle.67percent").font(.title3).foregroundStyle(meterTeal)
            VStack(alignment: .leading, spacing: 2) {
                Text("Codex Meter").font(.headline)
                Text("\(model.snapshot?.limits.mainBucket.planType?.capitalized ?? "Account") usage")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { Task { await model.refresh() } } label: {
                if model.refreshing { ProgressView().controlSize(.small) }
                else { Image(systemName: "arrow.clockwise") }
            }.buttonStyle(.borderless).disabled(model.refreshing || model.preview)
                .help("Refresh usage").accessibilityLabel("Refresh usage")
        }.padding(20)
    }

    private var footer: some View {
        HStack {
            Circle().fill(model.preview ? .orange : model.isStale || model.error != nil ? .orange : meterTeal)
                .frame(width: 5, height: 5)
            Text(model.statusText).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Menu {
                Picker("Refresh every", selection: $model.refreshMinutes) {
                    ForEach([1, 3, 5, 15], id: \.self) { Text("\($0) minutes").tag($0) }
                }
                Button(model.launchAtLogin ? "Disable launch at login" : "Launch at login") { model.toggleLogin() }
                Divider()
                Button("Choose Codex executable…") { model.chooseExecutable() }
                Button("Open Codex usage dashboard") {
                    NSWorkspace.shared.open(URL(string: "https://chatgpt.com/codex/settings/usage")!)
                }
                Divider()
                Button("Quit Codex Meter") { NSApp.terminate(nil) }.keyboardShortcut("q")
            } label: { Image(systemName: "gearshape") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Settings").accessibilityLabel("Settings")
        }.padding(.horizontal, 20).padding(.vertical, 14)
    }

    private func errorBanner(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(model.snapshot == nil ? "Connection needed" : "Couldn’t update", systemImage: "exclamationmark.triangle")
                .font(.callout.weight(.semibold))
            Text(error).font(.caption).textSelection(.enabled)
            if model.snapshot != nil { Text("Values below are from the last successful update.").font(.caption) }
        }.foregroundStyle(.secondary).padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }

    private func tokenSection(_ snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Token activity").font(.headline)
            if let activity = snapshot.activity, let day = activity.latest {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Latest daily tokens").font(.caption).foregroundStyle(.secondary)
                        Text(day.tokens.formatted(.number.notation(.compactName)))
                            .font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                    }
                    Spacer(minLength: 20)
                    if activity.days.count >= 2 {
                        Chart(Array(activity.days.suffix(7)), id: \.startDate) { point in
                            LineMark(x: .value("Day", point.startDate), y: .value("Tokens", point.tokens))
                                .foregroundStyle(meterTeal).lineStyle(StrokeStyle(lineWidth: 2))
                        }.chartXAxis(.hidden).chartYAxis(.hidden).frame(width: 120, height: 44)
                            .accessibilityLabel("Token activity for the last \(min(7, activity.days.count)) reported days")
                    }
                }
                Text("Reporting date: \(day.startDate)").font(.caption2).foregroundStyle(.secondary)
                if let total = activity.summary.lifetimeTokens {
                    Text("\(total.formatted(.number.notation(.compactName))) tokens lifetime").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Daily token activity is unavailable for this account.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Text("Token totals and allowance percentages are separate measures.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

private struct WindowSection: View {
    let window: UsageWindow
    var title: String? = nil
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 9) {
                Text(title ?? window.title).font(.system(size: 13, weight: .semibold))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int(window.remaining.rounded()))%")
                        .font(.system(size: 36, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("remaining").font(.callout).foregroundStyle(.secondary)
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.primary.opacity(0.08))
                        Capsule().fill(usageColor(window.remaining))
                            .frame(width: max(0, geometry.size.width * window.remaining / 100))
                    }
                }.frame(height: 7)
                    .accessibilityLabel("\(Int(window.remaining)) percent remaining")
                Text(window.resetText(now: context.date)).font(.caption).foregroundStyle(.secondary)
                    .help(window.resetDate?.formatted(date: .complete, time: .shortened) ?? "Reset time unavailable")
            }
        }
    }
}

struct MeterLabel: View {
    @ObservedObject var model: MeterModel
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: model.error != nil || model.isStale ? "exclamationmark.circle" : "gauge.with.dots.needle.67percent")
            if let remaining = model.snapshot?.limits.remaining {
                Text("\(Int(remaining.rounded()))%\(model.isStale ? " ·" : "")").monospacedDigit()
            } else { Text(model.refreshing ? "…" : "—") }
        }.accessibilityLabel("Codex Meter, \(model.snapshot?.limits.remaining.map { "\(Int($0)) percent remaining" } ?? "usage unavailable")")
    }
}
