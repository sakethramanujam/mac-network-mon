import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    var onOpenAccessibility: () -> Void
    var onClearChartHistory: () -> Void

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            qualityTab
                .tabItem { Label("Quality", systemImage: "speedometer") }
            usageTab
                .tabItem { Label("Usage", systemImage: "externaldrive") }
            advancedTab
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 460, height: 360)
        .padding()
    }

    private var generalTab: some View {
        Form {
            Picker("Update interval", selection: $store.updateInterval) {
                Text("0.5s").tag(0.5)
                Text("1s").tag(1.0)
                Text("2s").tag(2.0)
                Text("5s").tag(5.0)
            }
            Toggle("Show in bits (Mbps)", isOn: $store.showInBits)
            Toggle("Compact mode", isOn: $store.compactMode)
            Toggle("Hide when inactive", isOn: $store.hideInactive)
            Toggle("Monitor VPN/tunnel only", isOn: $store.monitorVPNOnly)
            Toggle("Speed threshold alerts", isOn: $store.thresholdAlertsEnabled)
            Picker("Tray layout", selection: $store.trayPresetRaw) {
                Text("Quality + Rates").tag("rates")
                Text("Download only").tag("downOnly")
                Text("Upload only").tag("upOnly")
                Text("Quality dot only").tag("qualityOnly")
            }
        }
    }

    private var qualityTab: some View {
        Form {
            TextField("Latency host", text: $store.latencyHost)
            TextField("DNS host", text: $store.dnsHost)
            Toggle("Weigh DNS in quality score", isOn: $store.weighDNSInQuality)
            Section("Good thresholds") {
                HStack {
                    Text("Latency ≤")
                    TextField("", value: $store.goodLatencyMaxMs, format: .number)
                    Text("ms")
                }
                HStack {
                    Text("Jitter ≤")
                    TextField("", value: $store.goodJitterMaxMs, format: .number)
                    Text("ms")
                }
                HStack {
                    Text("Loss ≤")
                    TextField("", value: $store.goodLossMaxPercent, format: .number)
                    Text("%")
                }
            }
            Section("Fair thresholds") {
                HStack {
                    Text("Latency ≤")
                    TextField("", value: $store.fairLatencyMaxMs, format: .number)
                    Text("ms")
                }
                HStack {
                    Text("Jitter ≤")
                    TextField("", value: $store.fairJitterMaxMs, format: .number)
                    Text("ms")
                }
                HStack {
                    Text("Loss ≤")
                    TextField("", value: $store.fairLossMaxPercent, format: .number)
                    Text("%")
                }
            }
            Button("Reset quality defaults") {
                store.resetQualityDefaults()
            }
        }
    }

    private var usageTab: some View {
        Form {
            Picker("Daily data limit", selection: $store.dataLimit) {
                Text("Unlimited").tag(UInt64(0))
                Text("1 GB").tag(UInt64(1_073_741_824))
                Text("5 GB").tag(UInt64(5_368_709_120))
                Text("10 GB").tag(UInt64(10_737_418_240))
                Text("50 GB").tag(UInt64(53_687_091_200))
            }
            Picker("Billing cycle limit", selection: $store.billingCycleLimit) {
                Text("Unlimited").tag(UInt64(0))
                Text("1 GB").tag(UInt64(1_073_741_824))
                Text("5 GB").tag(UInt64(5_368_709_120))
                Text("10 GB").tag(UInt64(10_737_418_240))
                Text("50 GB").tag(UInt64(53_687_091_200))
            }
            Picker("Cycle start day", selection: $store.billingCycleStartDay) {
                ForEach([1, 5, 10, 15, 20, 25, 28], id: \.self) { day in
                    Text("Day \(day)").tag(day)
                }
            }
            Picker("Warning threshold", selection: $store.speedThreshold) {
                Text("1 MB/s").tag(1_048_576.0)
                Text("5 MB/s").tag(5_242_880.0)
                Text("10 MB/s").tag(10_485_760.0)
                Text("50 MB/s").tag(52_428_800.0)
            }
        }
    }

    private var advancedTab: some View {
        Form {
            Toggle("Persist chart history across launches", isOn: $store.persistChartHistory)
            Button("Clear saved chart history") {
                onClearChartHistory()
            }
            Divider()
            Text("Graph hotkey: Control-Option-N")
                .foregroundStyle(.secondary)
            if HotkeyAccessibility.isTrusted {
                Label("Accessibility allowed for global hotkey", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Global hotkey needs Accessibility permission", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Button("Enable Accessibility…") {
                    onOpenAccessibility()
                }
            }
            Text("Per-app top talkers require a privileged helper. See docs/TOP_TALKERS.md.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
