import Charts
import SwiftUI

struct HistoryPopoverView: View {
    @ObservedObject var model: MonitorModel
    var onRunSpeedTest: () -> Void
    var onRefreshIPs: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            qualitySection
            wifiSection
            vpnSection
            interfaceBreakdownSection
            chartSection
            totalsSection
            speedTestSection
            footer
        }
        .padding(14)
        .frame(width: 360)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NetworkMon")
                    .font(.headline)
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Label(model.formatRate(model.currentDownload), systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(.body, design: .rounded).monospacedDigit())
                Label(model.formatRate(model.currentUpload), systemImage: "arrow.up.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(.body, design: .rounded).monospacedDigit())
            }
        }
    }

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Quality")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(model.quality.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(qualitySwiftColor)
            }
            HStack {
                metric("Latency", model.latencyText)
                metric("Jitter", model.jitterText)
                metric("Loss", model.lossText)
                metric("DNS", model.dnsLatencyText)
            }
            Text("HTTPS \(model.latencyHost) · DNS \(model.dnsHost)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var headerSubtitle: String {
        if model.monitorVPNOnly {
            return model.vpnActive ? "VPN only · \(model.tunnelInterfaces.joined(separator: ", "))" : "VPN only · no tunnel"
        }
        if model.selectedInterface == "All" {
            return model.vpnActive ? "All interfaces · VPN on" : "All interfaces"
        }
        return model.selectedInterface
    }

    private var wifiSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            HStack {
                Image(systemName: "wifi")
                Text(model.wifi.summaryLine)
                    .lineLimit(2)
                Spacer()
                if model.wifi.rssiDbm != nil {
                    Text(model.wifi.signalLabel)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
    }

    private var vpnSection: some View {
        Group {
            if model.vpnActive || model.monitorVPNOnly {
                HStack {
                    Image(systemName: model.vpnActive ? "lock.shield.fill" : "lock.shield")
                        .foregroundStyle(model.vpnActive ? .green : .secondary)
                    Text(model.vpnActive
                         ? "VPN/tunnel: \(model.tunnelInterfaces.joined(separator: ", "))"
                         : "No active tunnel interfaces")
                    .lineLimit(2)
                    Spacer()
                }
                .font(.caption)
            }
        }
    }

    private var interfaceBreakdownSection: some View {
        Group {
            if !model.interfaceRates.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                    Text("Top interfaces")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ForEach(model.interfaceRates.prefix(5)) { rate in
                        HStack {
                            Text(rate.name)
                                .frame(width: 64, alignment: .leading)
                            Text("↓ \(model.formatRate(rate.download))")
                                .foregroundStyle(.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("↑ \(model.formatRate(rate.upload))")
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.caption2)
                        .monospacedDigit()
                    }
                    Text("Per-app top talkers need a privileged helper outside the App Sandbox.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var qualitySwiftColor: Color {
        switch model.quality {
        case .unknown: return .secondary
        case .good: return .green
        case .fair: return .orange
        case .poor: return .red
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Seconds from the newest sample (0 = newest). Negative values are older.
    private var chartWindowSeconds: Double {
        model.chartRange.rawValue
    }

    private var chartAnchor: Date {
        model.samples.last?.date ?? Date()
    }

    private var xAxisValues: [Double] {
        let window = chartWindowSeconds
        var marks: [Double] = [0]
        let step: Double
        if window <= 60 {
            step = 15
        } else if window <= 180 {
            step = 30
        } else {
            step = 60
        }
        var t = -step
        while t >= -window - 0.1 {
            marks.append(t)
            t -= step
        }
        return marks.sorted()
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Range", selection: $model.chartRange) {
                    ForEach(ChartTimeRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: model.chartRange) { newValue in
                    model.trimSamplesToRange()
                    UserDefaults.standard.set(newValue.rawValue, forKey: "ChartTimeRange")
                }

                Button(model.chartPaused ? "Resume" : "Pause") {
                    model.chartPaused.toggle()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            Text(chartCaption)
                .font(.caption)
                .foregroundStyle(.secondary)

            Chart {
                ForEach(model.samples) { sample in
                    let x = sample.date.timeIntervalSince(chartAnchor)
                    LineMark(
                        x: .value("Age", x),
                        y: .value("Down", displayValue(sample.download))
                    )
                    .foregroundStyle(.green)
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Age", x),
                        y: .value("Up", displayValue(sample.upload))
                    )
                    .foregroundStyle(.orange)
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartXScale(domain: -chartWindowSeconds...0)
            .chartXAxis {
                AxisMarks(values: xAxisValues) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let offset = value.as(Double.self) {
                            Text(NetworkMonFormat.relativeTimeLabel(secondsFromNewest: offset))
                                .font(.caption2)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let raw = value.as(Double.self) {
                            Text(axisLabel(raw))
                                .font(.caption2)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .frame(height: 160)
            .opacity(model.samples.isEmpty ? 0.35 : 1)

            HStack(spacing: 12) {
                legendSwatch(color: .green, title: "Download")
                legendSwatch(color: .orange, title: "Upload")
            }
            .font(.caption2)

            if model.samples.isEmpty {
                Text("Collecting samples…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var chartCaption: String {
        let paused = model.chartPaused ? " · paused" : ""
        let minutes = chartWindowSeconds / 60
        if minutes >= 1.5 {
            return String(format: "Last %.0f min (relative)%@", minutes, paused)
        }
        return String(format: "Last %.0f sec (relative)%@", chartWindowSeconds, paused)
    }

    private var totalsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            gridRow("Session", model.formatTotal(model.sessionIn), model.formatTotal(model.sessionOut))
            gridRow("Today", model.formatTotal(model.dailyIn), model.formatTotal(model.dailyOut))
            gridRow("Month", model.formatTotal(model.monthlyIn), model.formatTotal(model.monthlyOut))
            if model.billingLimit > 0 {
                gridRow("Cycle", model.formatTotal(model.billingIn), model.formatTotal(model.billingOut))
                Text("Cycle day \(model.billingStartDay) · limit \(model.formatTotal(model.billingLimit))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Latency")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.latencyText)
                    .monospacedDigit()
            }
            .font(.caption)
            HStack {
                Text("Local / Public")
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onRefreshIPs) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh IPs")
            }
            .font(.caption)
            Text("\(model.localIP)  ·  \(model.publicIP)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }

    private var speedTestSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack {
                Text("Speed Test")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(action: onRunSpeedTest) {
                    if model.isSpeedTesting {
                        ProgressView()
                            .controlSize(.small)
                        Text(phaseLabel)
                            .font(.caption)
                    } else {
                        Label("Run", systemImage: "gauge.with.needle")
                    }
                }
                .disabled(model.isSpeedTesting)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if let down = model.lastDownloadResult {
                Text("↓ \(down)")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if let up = model.lastUploadResult {
                Text("↑ \(up)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let err = model.lastSpeedTestError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if model.lastDownloadResult == nil, model.lastUploadResult == nil, model.lastSpeedTestError == nil, !model.isSpeedTesting {
                Text("Downloads 20MB, then uploads 10MB via Cloudflare.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !model.speedTestHistory.isEmpty {
                Text("Recent")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(model.speedTestHistory.prefix(5)) { record in
                    HStack {
                        Text(record.date, style: .relative)
                            .foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .leading)
                        Text("↓ \(record.download)")
                            .foregroundStyle(.green)
                        Text("↑ \(record.upload)")
                            .foregroundStyle(.orange)
                        Spacer(minLength: 0)
                    }
                    .font(.caption2)
                    .monospacedDigit()
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Left-click graph · Right-click menu")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Quit", action: onQuit)
                .buttonStyle(.borderless)
                .controlSize(.small)
        }
    }

    private var phaseLabel: String {
        switch model.speedTestPhase {
        case .idle: return ""
        case .download: return "Downloading…"
        case .upload: return "Uploading…"
        }
    }

    private func legendSwatch(color: Color, title: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(title)
                .foregroundStyle(.secondary)
        }
    }

    private func gridRow(_ title: String, _ down: String, _ up: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            Text("↓ \(down)")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("↑ \(up)")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
        .monospacedDigit()
    }

    /// Chart Y values follow bits/bytes preference.
    private func displayValue(_ bytesPerSecond: Double) -> Double {
        model.showInBits ? bytesPerSecond * 8 : bytesPerSecond
    }

    private func axisLabel(_ value: Double) -> String {
        let bytes = model.showInBits ? value / 8 : value
        return NetworkMonFormat.formatStableRate(bytes, showInBits: model.showInBits)
    }
}
