import Foundation

enum ConnectionQuality: String, Equatable {
    case unknown
    case good
    case fair
    case poor

    var title: String {
        switch self {
        case .unknown: return "…"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        }
    }

    /// Compact tray glyph (single character keeps width stable).
    var trayGlyph: String {
        switch self {
        case .unknown: return "·"
        case .good: return "●"
        case .fair: return "◐"
        case .poor: return "○"
        }
    }
}

struct LatencyProbe: Equatable {
    /// Round-trip milliseconds when successful; nil means timeout / failure (counts as loss).
    let rttMs: Double?
}

enum ConnectionQualityCalculator {
    static let minSamples = 3
    static let windowSize = 12

    struct Thresholds: Equatable {
        var goodLatencyMaxMs: Double = 50
        var fairLatencyMaxMs: Double = 150
        var goodJitterMaxMs: Double = 15
        var fairJitterMaxMs: Double = 40
        var goodLossMaxPercent: Double = 5
        var fairLossMaxPercent: Double = 15

        static let `default` = Thresholds()
    }

    struct Stats: Equatable {
        var averageMs: Double?
        var jitterMs: Double?
        var lossPercent: Double
        var quality: ConnectionQuality
        var sampleCount: Int
    }

    static func evaluate(
        _ probes: [LatencyProbe],
        thresholds: Thresholds = .default,
        dnsLatencyMs: Double? = nil,
        weighDNS: Bool = false
    ) -> Stats {
        let recent = Array(probes.suffix(windowSize))
        guard !recent.isEmpty else {
            return Stats(averageMs: nil, jitterMs: nil, lossPercent: 0, quality: .unknown, sampleCount: 0)
        }

        let successes = recent.compactMap(\.rttMs)
        let loss = Double(recent.count - successes.count) / Double(recent.count) * 100.0

        guard successes.count >= minSamples else {
            return Stats(
                averageMs: successes.isEmpty ? nil : successes.reduce(0, +) / Double(successes.count),
                jitterMs: jitter(of: successes),
                lossPercent: loss,
                quality: .unknown,
                sampleCount: recent.count
            )
        }

        var average = successes.reduce(0, +) / Double(successes.count)
        if weighDNS, let dnsLatencyMs {
            average = (average * 0.7) + (dnsLatencyMs * 0.3)
        }
        let jitterMs = jitter(of: successes) ?? 0

        let quality: ConnectionQuality
        if loss < thresholds.goodLossMaxPercent,
           average < thresholds.goodLatencyMaxMs,
           jitterMs < thresholds.goodJitterMaxMs {
            quality = .good
        } else if loss < thresholds.fairLossMaxPercent,
                  average < thresholds.fairLatencyMaxMs,
                  jitterMs < thresholds.fairJitterMaxMs {
            quality = .fair
        } else {
            quality = .poor
        }

        return Stats(
            averageMs: average,
            jitterMs: jitterMs,
            lossPercent: loss,
            quality: quality,
            sampleCount: recent.count
        )
    }

    private static func jitter(of samples: [Double]) -> Double? {
        guard samples.count >= 2 else { return nil }
        var total = 0.0
        for i in 1..<samples.count {
            total += abs(samples[i] - samples[i - 1])
        }
        return total / Double(samples.count - 1)
    }
}

enum LatencyHost {
    static let presets: [(title: String, host: String)] = [
        ("Cloudflare DNS", "1.1.1.1"),
        ("Google DNS", "8.8.8.8"),
        ("Quad9 DNS", "9.9.9.9"),
        ("Cloudflare", "cloudflare.com"),
        ("Apple", "www.apple.com")
    ]

    static let defaultHost = "1.1.1.1"

    /// Builds an HTTPS HEAD target from a host or URL-ish string.
    static func probeURL(for raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), let scheme = url.scheme, scheme.hasPrefix("http"), url.host != nil {
            return url
        }

        var host = trimmed
        if host.hasPrefix("https://") {
            host = String(host.dropFirst(8))
        } else if host.hasPrefix("http://") {
            host = String(host.dropFirst(7))
        }
        if let slash = host.firstIndex(of: "/") {
            host = String(host[..<slash])
        }
        guard !host.isEmpty else { return nil }
        return URL(string: "https://\(host)")
    }
}
