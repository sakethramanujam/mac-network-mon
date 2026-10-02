import Foundation

enum NetworkMonFormat {
    /// Formats a byte count for display. When `rate` is true, appends `/s` units.
    static func formatBytes(
        _ bytes: UInt64,
        rate: Bool,
        showInBits: Bool,
        compactMode: Bool
    ) -> String {
        let value = showInBits ? Double(bytes) * 8 : Double(bytes)
        let suffix = rate ? (showInBits ? "bps" : "B/s") : (showInBits ? "b" : "B")

        // Decimal for bits (SI), binary for bytes (IEC-style KB/MB).
        let unit = showInBits ? 1000.0 : 1024.0
        let mb = unit * unit
        let gb = mb * unit

        if value < unit {
            return compactMode ? "\(Int(value))" : "\(Int(value)) \(suffix)"
        }

        if value < mb {
            let scaled = value / unit
            return compactMode
                ? String(format: "%.1f K", scaled)
                : String(format: "%.1f K\(suffix)", scaled)
        }
        if value < gb {
            let scaled = value / mb
            return compactMode
                ? String(format: "%.1f M", scaled)
                : String(format: "%.1f M\(suffix)", scaled)
        }
        let scaled = value / gb
        return compactMode
            ? String(format: "%.2f G", scaled)
            : String(format: "%.2f G\(suffix)", scaled)
    }

    /// Fixed-width rate for the menu bar so the status item does not resize as values change.
    /// Always returns 6 characters: ` 12.3M`, `999.9K`, `  0.0B`.
    static func formatStableRate(_ bytesPerSecond: Double, showInBits: Bool) -> String {
        let value = max(0, showInBits ? bytesPerSecond * 8 : bytesPerSecond)
        let step = showInBits ? 1000.0 : 1024.0
        let (scaled, unit): (Double, String)
        if value < step {
            scaled = value
            unit = showInBits ? "b" : "B"
        } else if value < step * step {
            scaled = value / step
            unit = "K"
        } else if value < step * step * step {
            scaled = value / (step * step)
            unit = "M"
        } else {
            scaled = value / (step * step * step)
            unit = "G"
        }
        // Keep the numeric field at most 5 characters wide (e.g. "999.9", " 12.3", "  0.0").
        let number = String(format: "%5.1f", min(scaled, 999.9))
        return number + unit
    }

    static func relativeTimeLabel(secondsFromNewest offset: Double) -> String {
        if offset >= -0.5 { return "now" }
        let seconds = Int((-offset).rounded())
        if seconds < 60 { return "-\(seconds)s" }
        let minutes = seconds / 60
        let rem = seconds % 60
        if rem == 0 { return "-\(minutes)m" }
        return String(format: "-%d:%02d", minutes, rem)
    }
}

enum UsagePeriod {
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM"
        return f
    }()

    static func dayString(from date: Date = Date()) -> String {
        dayFormatter.string(from: date)
    }

    static func monthString(from date: Date = Date()) -> String {
        monthFormatter.string(from: date)
    }
}

enum UInt64Defaults {
    static func get(_ key: String, defaults: UserDefaults = .standard) -> UInt64 {
        if let number = defaults.object(forKey: key) as? NSNumber {
            return number.uint64Value
        }
        return 0
    }

    static func set(_ value: UInt64, forKey key: String, defaults: UserDefaults = .standard) {
        defaults.set(NSNumber(value: value), forKey: key)
    }
}
