import Foundation
import Combine
import AppKit

struct SpeedSample: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let download: Double
    let upload: Double

    init(date: Date = Date(), download: Double, upload: Double) {
        self.id = UUID()
        self.date = date
        self.download = download
        self.upload = upload
    }
}

enum SpeedTestPhase: Equatable {
    case idle
    case download
    case upload
}

struct SpeedTestRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let download: String
    let upload: String

    init(id: UUID = UUID(), date: Date = Date(), download: String, upload: String) {
        self.id = id
        self.date = date
        self.download = download
        self.upload = upload
    }
}

enum ChartTimeRange: Double, CaseIterable, Identifiable {
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case sixtyMinutes = 3600

    var id: Double { rawValue }

    var title: String {
        switch self {
        case .oneMinute: return "1m"
        case .fiveMinutes: return "5m"
        case .fifteenMinutes: return "15m"
        case .sixtyMinutes: return "60m"
        }
    }
}

/// Live state shared between the menu-bar controller and the SwiftUI popover.
final class MonitorModel: ObservableObject {
    /// Hard cap so a 0.5s interval over 60m cannot unbounded-grow memory.
    static let absoluteMaxSamples = 7200

    @Published var samples: [SpeedSample] = []
    @Published var chartRange: ChartTimeRange = .oneMinute
    @Published var chartPaused: Bool = false
    @Published var currentDownload: Double = 0
    @Published var currentUpload: Double = 0
    @Published var latencyText: String = "Measuring…"
    @Published var latencyHost: String = LatencyHost.defaultHost
    @Published var jitterText: String = "—"
    @Published var lossText: String = "—"
    @Published var quality: ConnectionQuality = .unknown
    @Published var localIP: String = "Fetching…"
    @Published var publicIP: String = "Fetching…"
    @Published var selectedInterface: String = "All"
    @Published var showInBits: Bool = false
    @Published var compactMode: Bool = false
    /// Sampling period used to pin the chart's time window.
    @Published var updateInterval: TimeInterval = 1.0

    @Published var sessionIn: UInt64 = 0
    @Published var sessionOut: UInt64 = 0
    @Published var dailyIn: UInt64 = 0
    @Published var dailyOut: UInt64 = 0
    @Published var monthlyIn: UInt64 = 0
    @Published var monthlyOut: UInt64 = 0
    @Published var billingIn: UInt64 = 0
    @Published var billingOut: UInt64 = 0
    @Published var billingLimit: UInt64 = 0
    @Published var billingStartDay: Int = 1

    @Published var wifi: WiFiStatus = .disconnected
    @Published var vpnActive: Bool = false
    @Published var tunnelInterfaces: [String] = []
    @Published var monitorVPNOnly: Bool = false

    @Published var speedTestPhase: SpeedTestPhase = .idle
    @Published var lastDownloadResult: String?
    @Published var lastUploadResult: String?
    @Published var lastSpeedTestError: String?
    @Published var speedTestHistory: [SpeedTestRecord] = []

    var isSpeedTesting: Bool { speedTestPhase != .idle }

    static let speedTestHistoryKey = "SpeedTestHistory"
    static let speedTestHistoryLimit = 8

    func loadSpeedTestHistory() {
        guard let data = UserDefaults.standard.data(forKey: Self.speedTestHistoryKey),
              let decoded = try? JSONDecoder().decode([SpeedTestRecord].self, from: data) else {
            speedTestHistory = []
            return
        }
        speedTestHistory = decoded
    }

    func recordSpeedTest(download: String, upload: String) {
        lastDownloadResult = download
        lastUploadResult = upload
        var next = speedTestHistory
        next.insert(SpeedTestRecord(download: download, upload: upload), at: 0)
        if next.count > Self.speedTestHistoryLimit {
            next = Array(next.prefix(Self.speedTestHistoryLimit))
        }
        speedTestHistory = next
        if let data = try? JSONEncoder().encode(next) {
            UserDefaults.standard.set(data, forKey: Self.speedTestHistoryKey)
        }
    }

    var chartCapacity: Int {
        let interval = max(updateInterval, 0.5)
        let needed = Int(ceil(chartRange.rawValue / interval)) + 2
        return min(max(needed, 30), Self.absoluteMaxSamples)
    }

    var qualityColor: NSColor {
        switch quality {
        case .unknown: return .secondaryLabelColor
        case .good: return .systemGreen
        case .fair: return .systemOrange
        case .poor: return .systemRed
        }
    }

    func appendSample(download: Double, upload: Double) {
        currentDownload = download
        currentUpload = upload
        guard !chartPaused else { return }
        samples.append(SpeedSample(download: download, upload: upload))
        let capacity = chartCapacity
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }

    func trimSamplesToRange() {
        let capacity = chartCapacity
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }

    func clearChart() {
        samples.removeAll(keepingCapacity: true)
        currentDownload = 0
        currentUpload = 0
    }

    func applyLatencyStats(_ stats: ConnectionQualityCalculator.Stats) {
        quality = stats.quality
        if let avg = stats.averageMs {
            latencyText = String(format: "%.0fms", avg)
        }
        if let jitter = stats.jitterMs {
            jitterText = String(format: "%.0fms", jitter)
        } else {
            jitterText = "—"
        }
        lossText = String(format: "%.0f%%", stats.lossPercent)
    }

    func formatRate(_ bytesPerSecond: Double) -> String {
        NetworkMonFormat.formatBytes(
            UInt64(max(0, bytesPerSecond)),
            rate: true,
            showInBits: showInBits,
            compactMode: false
        )
    }

    func formatTotal(_ bytes: UInt64) -> String {
        NetworkMonFormat.formatBytes(
            bytes,
            rate: false,
            showInBits: showInBits,
            compactMode: false
        )
    }
}
