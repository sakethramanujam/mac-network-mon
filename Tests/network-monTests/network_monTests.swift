import Foundation
import XCTest
@testable import network_mon

final class NetworkMonTests: XCTestCase {
    func testConnectionQualityGoodPath() {
        let probes = (0..<6).map { _ in LatencyProbe(rttMs: 20) }
        let stats = ConnectionQualityCalculator.evaluate(probes)
        XCTAssertEqual(stats.quality, .good)
        XCTAssertEqual(stats.lossPercent, 0, accuracy: 0.01)
    }

    func testConnectionQualityPoorOnLoss() {
        var probes: [LatencyProbe] = (0..<4).map { _ in LatencyProbe(rttMs: 30) }
        probes.append(contentsOf: (0..<4).map { _ in LatencyProbe(rttMs: nil) })
        let stats = ConnectionQualityCalculator.evaluate(probes)
        XCTAssertEqual(stats.quality, .poor)
        XCTAssertGreaterThan(stats.lossPercent, 40)
    }

    func testLatencyHostProbeURL() {
        XCTAssertEqual(LatencyHost.probeURL(for: "1.1.1.1")?.absoluteString, "https://1.1.1.1")
        XCTAssertEqual(LatencyHost.probeURL(for: "https://example.com/path")?.host, "example.com")
        XCTAssertNil(LatencyHost.probeURL(for: "   "))
    }

    func testFormatStableRateIsFixedWidth() {
        let samples: [Double] = [0, 500, 1_500, 1_500_000, 50_000_000]
        for sample in samples {
            let text = NetworkMonFormat.formatStableRate(sample, showInBits: false)
            XCTAssertEqual(text.count, 6, "expected fixed width for \(sample), got '\(text)'")
        }
    }

    func testRelativeTimeLabel() {
        XCTAssertEqual(NetworkMonFormat.relativeTimeLabel(secondsFromNewest: 0), "now")
        XCTAssertEqual(NetworkMonFormat.relativeTimeLabel(secondsFromNewest: -12), "-12s")
        XCTAssertEqual(NetworkMonFormat.relativeTimeLabel(secondsFromNewest: -60), "-1m")
        XCTAssertEqual(NetworkMonFormat.relativeTimeLabel(secondsFromNewest: -90), "-1:30")
    }

    func testFormatBytesCompactUsesShortPrefixes() {
        let text = NetworkMonFormat.formatBytes(1_500, rate: true, showInBits: false, compactMode: true)
        XCTAssertTrue(text.contains("K"))
        XCTAssertFalse(text.contains("B/s"))
    }

    func testFormatBytesNonCompactIncludesUnit() {
        let text = NetworkMonFormat.formatBytes(1_500, rate: true, showInBits: false, compactMode: false)
        XCTAssertEqual(text, "1.5 KB/s")
    }

    func testFormatBytesBitsUsesDecimalUnits() {
        let text = NetworkMonFormat.formatBytes(125, rate: true, showInBits: true, compactMode: false)
        XCTAssertTrue(text.contains("K"))
        XCTAssertTrue(text.contains("bps"))
    }

    func testFormatBytesGigabytes() {
        let oneGB: UInt64 = 1_073_741_824
        let text = NetworkMonFormat.formatBytes(oneGB, rate: false, showInBits: false, compactMode: false)
        XCTAssertTrue(text.contains("G"))
    }

    func testUsagePeriodDayAndMonthFormats() {
        let now = Date()
        let day = UsagePeriod.dayString(from: now)
        let month = UsagePeriod.monthString(from: now)
        XCTAssertEqual(day.count, 10)
        XCTAssertEqual(day.split(separator: "-").count, 3)
        XCTAssertEqual(month.count, 7)
        XCTAssertEqual(month.split(separator: "-").count, 2)
        XCTAssertTrue(day.hasPrefix(month))
    }

    func testUInt64DefaultsRoundTripsLargeValues() {
        let suite = "network-mon.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let value: UInt64 = 9_007_199_254_740_991
        UInt64Defaults.set(value, forKey: "test", defaults: defaults)
        XCTAssertEqual(UInt64Defaults.get("test", defaults: defaults), value)
    }
}
