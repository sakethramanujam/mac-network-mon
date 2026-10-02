import Combine
import Foundation

/// Central UserDefaults-backed settings shared by the menu bar controller and Settings UI.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var updateInterval: TimeInterval {
        didSet { defaults.set(updateInterval, forKey: Keys.updateInterval) }
    }
    @Published var showInBits: Bool {
        didSet { defaults.set(showInBits, forKey: Keys.showInBits) }
    }
    @Published var compactMode: Bool {
        didSet { defaults.set(compactMode, forKey: Keys.compactMode) }
    }
    @Published var hideInactive: Bool {
        didSet { defaults.set(hideInactive, forKey: Keys.hideInactive) }
    }
    @Published var monitorVPNOnly: Bool {
        didSet { defaults.set(monitorVPNOnly, forKey: Keys.monitorVPNOnly) }
    }
    @Published var thresholdAlertsEnabled: Bool {
        didSet { defaults.set(thresholdAlertsEnabled, forKey: Keys.thresholdAlerts) }
    }
    @Published var trayPresetRaw: String {
        didSet { defaults.set(trayPresetRaw, forKey: Keys.trayPreset) }
    }
    @Published var latencyHost: String {
        didSet { defaults.set(latencyHost, forKey: Keys.latencyHost) }
    }
    @Published var dnsHost: String {
        didSet { defaults.set(dnsHost, forKey: Keys.dnsHost) }
    }
    @Published var speedThreshold: Double {
        didSet { defaults.set(speedThreshold, forKey: Keys.speedThreshold) }
    }
    @Published var dataLimit: UInt64 {
        didSet { UInt64Defaults.set(dataLimit, forKey: Keys.dataLimit, defaults: defaults) }
    }
    @Published var billingCycleLimit: UInt64 {
        didSet { UInt64Defaults.set(billingCycleLimit, forKey: Keys.billingLimit, defaults: defaults) }
    }
    @Published var billingCycleStartDay: Int {
        didSet { defaults.set(billingCycleStartDay, forKey: Keys.billingStartDay) }
    }

    // Quality tuning
    @Published var goodLatencyMaxMs: Double {
        didSet { defaults.set(goodLatencyMaxMs, forKey: Keys.goodLatency) }
    }
    @Published var fairLatencyMaxMs: Double {
        didSet { defaults.set(fairLatencyMaxMs, forKey: Keys.fairLatency) }
    }
    @Published var goodJitterMaxMs: Double {
        didSet { defaults.set(goodJitterMaxMs, forKey: Keys.goodJitter) }
    }
    @Published var fairJitterMaxMs: Double {
        didSet { defaults.set(fairJitterMaxMs, forKey: Keys.fairJitter) }
    }
    @Published var goodLossMaxPercent: Double {
        didSet { defaults.set(goodLossMaxPercent, forKey: Keys.goodLoss) }
    }
    @Published var fairLossMaxPercent: Double {
        didSet { defaults.set(fairLossMaxPercent, forKey: Keys.fairLoss) }
    }
    @Published var weighDNSInQuality: Bool {
        didSet { defaults.set(weighDNSInQuality, forKey: Keys.weighDNS) }
    }
    @Published var persistChartHistory: Bool {
        didSet { defaults.set(persistChartHistory, forKey: Keys.persistChart) }
    }

    private let defaults: UserDefaults

    enum Keys {
        static let updateInterval = "UpdateInterval"
        static let showInBits = "ShowInBits"
        static let compactMode = "CompactMode"
        static let hideInactive = "HideInactive"
        static let monitorVPNOnly = "MonitorVPNOnly"
        static let thresholdAlerts = "ThresholdAlertsEnabled"
        static let trayPreset = "TrayPreset"
        static let latencyHost = "LatencyHost"
        static let dnsHost = "DNSLatencyHost"
        static let speedThreshold = "SpeedThreshold"
        static let dataLimit = "DataLimit"
        static let billingLimit = "BillingCycleLimit"
        static let billingStartDay = "BillingCycleStartDay"
        static let goodLatency = "QualityGoodLatencyMaxMs"
        static let fairLatency = "QualityFairLatencyMaxMs"
        static let goodJitter = "QualityGoodJitterMaxMs"
        static let fairJitter = "QualityFairJitterMaxMs"
        static let goodLoss = "QualityGoodLossMaxPercent"
        static let fairLoss = "QualityFairLossMaxPercent"
        static let weighDNS = "QualityWeighDNS"
        static let persistChart = "PersistChartHistory"
    }

    var qualityThresholds: ConnectionQualityCalculator.Thresholds {
        .init(
            goodLatencyMaxMs: goodLatencyMaxMs,
            fairLatencyMaxMs: fairLatencyMaxMs,
            goodJitterMaxMs: goodJitterMaxMs,
            fairJitterMaxMs: fairJitterMaxMs,
            goodLossMaxPercent: goodLossMaxPercent,
            fairLossMaxPercent: fairLossMaxPercent
        )
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let interval = defaults.double(forKey: Keys.updateInterval)
        updateInterval = interval > 0 ? interval : 1.0
        showInBits = defaults.bool(forKey: Keys.showInBits)
        compactMode = defaults.bool(forKey: Keys.compactMode)
        hideInactive = defaults.bool(forKey: Keys.hideInactive)
        monitorVPNOnly = defaults.bool(forKey: Keys.monitorVPNOnly)
        thresholdAlertsEnabled = defaults.object(forKey: Keys.thresholdAlerts) == nil
            ? true
            : defaults.bool(forKey: Keys.thresholdAlerts)
        trayPresetRaw = defaults.string(forKey: Keys.trayPreset) ?? "rates"
        latencyHost = {
            let stored = defaults.string(forKey: Keys.latencyHost)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let stored, !stored.isEmpty, LatencyHost.probeURL(for: stored) != nil { return stored }
            return LatencyHost.defaultHost
        }()
        dnsHost = defaults.string(forKey: Keys.dnsHost) ?? "example.com"
        let threshold = defaults.double(forKey: Keys.speedThreshold)
        speedThreshold = threshold > 0 ? threshold : 5_242_880.0
        dataLimit = UInt64Defaults.get(Keys.dataLimit, defaults: defaults)
        billingCycleLimit = UInt64Defaults.get(Keys.billingLimit, defaults: defaults)
        let day = defaults.integer(forKey: Keys.billingStartDay)
        billingCycleStartDay = (1...28).contains(day) ? day : 1

        goodLatencyMaxMs = Self.double(defaults, Keys.goodLatency, 50)
        fairLatencyMaxMs = Self.double(defaults, Keys.fairLatency, 150)
        goodJitterMaxMs = Self.double(defaults, Keys.goodJitter, 15)
        fairJitterMaxMs = Self.double(defaults, Keys.fairJitter, 40)
        goodLossMaxPercent = Self.double(defaults, Keys.goodLoss, 5)
        fairLossMaxPercent = Self.double(defaults, Keys.fairLoss, 15)
        weighDNSInQuality = defaults.bool(forKey: Keys.weighDNS)
        persistChartHistory = defaults.object(forKey: Keys.persistChart) == nil
            ? true
            : defaults.bool(forKey: Keys.persistChart)
    }

    private static func double(_ defaults: UserDefaults, _ key: String, _ fallback: Double) -> Double {
        let value = defaults.double(forKey: key)
        return value > 0 ? value : fallback
    }

    func resetQualityDefaults() {
        goodLatencyMaxMs = 50
        fairLatencyMaxMs = 150
        goodJitterMaxMs = 15
        fairJitterMaxMs = 40
        goodLossMaxPercent = 5
        fairLossMaxPercent = 15
        weighDNSInQuality = false
    }
}
