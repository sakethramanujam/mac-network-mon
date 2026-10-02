import Foundation

enum UsageExport {
    static func csv(
        sessionIn: UInt64,
        sessionOut: UInt64,
        dailyIn: UInt64,
        dailyOut: UInt64,
        monthlyIn: UInt64,
        monthlyOut: UInt64,
        billingIn: UInt64,
        billingOut: UInt64,
        billingPeriod: String,
        exportedAt: Date = Date()
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let lines = [
            "period,download_bytes,upload_bytes",
            "session,\(sessionIn),\(sessionOut)",
            "today,\(dailyIn),\(dailyOut)",
            "month,\(monthlyIn),\(monthlyOut)",
            "billing_cycle,\(billingIn),\(billingOut)",
            "",
            "billing_period_key,\(billingPeriod)",
            "exported_at,\(formatter.string(from: exportedAt))"
        ]
        return lines.joined(separator: "\n") + "\n"
    }
}
