import Foundation

enum BillingCycle {
    /// Bytes counted toward the current billing period (from cycle start day through now).
    static func periodKey(startDay: Int, now: Date = Date(), calendar: Calendar = .current) -> String {
        let day = min(max(startDay, 1), 28)
        let comps = calendar.dateComponents([.year, .month, .day], from: now)
        guard let year = comps.year, let month = comps.month, let today = comps.day else {
            return UsagePeriod.monthString(from: now)
        }

        var periodYear = year
        var periodMonth = month
        if today < day {
            periodMonth -= 1
            if periodMonth == 0 {
                periodMonth = 12
                periodYear -= 1
            }
        }
        return String(format: "%04d-%02d-%02d", periodYear, periodMonth, day)
    }
}
