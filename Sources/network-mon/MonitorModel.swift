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

/// Live state shared between the menu-bar controller and the SwiftUI popover.
final class MonitorModel: ObservableObject {
    static let chartCapacity = 120

    @Published var samples: [SpeedSample] = []
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

    @Published var wifi: WiFiStatus = .disconnected

    @Published var speedTestPhase: SpeedTestPhase = .idle
    @Published var lastDownloadResult: String?
    @Published var lastUploadResult: String?
    @Published var lastSpeedTestError: String?

    var isSpeedTesting: Bool { speedTestPhase != .idle }

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
        samples.append(SpeedSample(download: download, upload: upload))
        if samples.count > Self.chartCapacity {
            samples.removeFirst(samples.count - Self.chartCapacity)
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
