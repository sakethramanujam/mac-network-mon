import AppKit
import Darwin
import Foundation
import ServiceManagement
import SwiftUI
import UserNotifications

@main
struct NetworkMonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem?
    var timer: Timer?
    var latencyTimer: Timer?
    var dnsTimer: Timer?
    var publicIPTimer: Timer?
    var popover: NSPopover?
    let monitorModel = MonitorModel()
    /// Kept so in-place title refresh works while the menu is open.
    var statusMenu: NSMenu?

    var previousBytesIn: UInt64 = 0
    var previousBytesOut: UInt64 = 0
    var previousInterfaceBytes: [String: (UInt64, UInt64)] = [:]

    var initialBytesIn: UInt64 = 0
    var initialBytesOut: UInt64 = 0

    var availableInterfaces: [String] = []
    private var latencyTask: URLSessionDataTask?
    private var speedTestTask: URLSessionDataTask?

    var isSpeedTesting: Bool { monitorModel.isSpeedTesting }

    // MARK: - Settings

    /// Fixed menu-bar width so neighboring items do not jump as rates change.
    /// Fits quality glyph + `↓999.9M ↑999.9M` in 11pt monospaced digits.
    private let statusItemLength: CGFloat = 148

    private var latencyProbes: [LatencyProbe] = []
    private var wifiTimer: Timer?

    var updateInterval: TimeInterval {
        get {
            let v = UserDefaults.standard.double(forKey: "UpdateInterval")
            return v > 0 ? v : 1.0
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "UpdateInterval")
            monitorModel.updateInterval = newValue
            restartTimer()
            buildMenu()
        }
    }

    var showInBits: Bool {
        get { UserDefaults.standard.bool(forKey: "ShowInBits") }
        set {
            UserDefaults.standard.set(newValue, forKey: "ShowInBits")
            monitorModel.showInBits = newValue
            buildMenu()
            updateNetworkStats()
        }
    }

    var compactMode: Bool {
        get { UserDefaults.standard.bool(forKey: "CompactMode") }
        set {
            UserDefaults.standard.set(newValue, forKey: "CompactMode")
            monitorModel.compactMode = newValue
            buildMenu()
            updateNetworkStats()
        }
    }

    var hideInactive: Bool {
        get { UserDefaults.standard.bool(forKey: "HideInactive") }
        set {
            UserDefaults.standard.set(newValue, forKey: "HideInactive")
            buildMenu()
            updateNetworkStats()
        }
    }

    var monitorVPNOnly: Bool {
        get { UserDefaults.standard.bool(forKey: "MonitorVPNOnly") }
        set {
            UserDefaults.standard.set(newValue, forKey: "MonitorVPNOnly")
            monitorModel.monitorVPNOnly = newValue
            // Reset session counters when switching aggregation scope.
            let stats = getNetworkStatsPerInterface()
            let (totalIn, totalOut) = getAggregatedStats(stats)
            previousBytesIn = totalIn
            previousBytesOut = totalOut
            initialBytesIn = totalIn
            initialBytesOut = totalOut
            monitorModel.clearChart()
            buildMenu()
            updateNetworkStats()
        }
    }

    var selectedInterface: String {
        get { UserDefaults.standard.string(forKey: "SelectedInterface") ?? "All" }
        set {
            UserDefaults.standard.set(newValue, forKey: "SelectedInterface")
            monitorModel.selectedInterface = newValue
            buildMenu()
        }
    }

    var speedThreshold: Double {
        get {
            let v = UserDefaults.standard.double(forKey: "SpeedThreshold")
            return v > 0 ? v : 5_242_880.0
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "SpeedThreshold")
            buildMenu()
            updateNetworkStats()
        }
    }

    var dataLimit: UInt64 {
        get { UInt64Defaults.get("DataLimit") }
        set {
            UInt64Defaults.set(newValue, forKey: "DataLimit")
            buildMenu()
        }
    }

    var billingCycleLimit: UInt64 {
        get { UInt64Defaults.get("BillingCycleLimit") }
        set {
            UInt64Defaults.set(newValue, forKey: "BillingCycleLimit")
            monitorModel.billingLimit = newValue
            buildMenu()
        }
    }

    var billingCycleStartDay: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: "BillingCycleStartDay")
            return (1...28).contains(v) ? v : 1
        }
        set {
            let day = min(max(newValue, 1), 28)
            UserDefaults.standard.set(day, forKey: "BillingCycleStartDay")
            monitorModel.billingStartDay = day
            checkDateRollover()
            buildMenu()
        }
    }

    var billingBytesIn: UInt64 {
        get { UInt64Defaults.get("BillingBytesIn") }
        set { UInt64Defaults.set(newValue, forKey: "BillingBytesIn") }
    }
    var billingBytesOut: UInt64 {
        get { UInt64Defaults.get("BillingBytesOut") }
        set { UInt64Defaults.set(newValue, forKey: "BillingBytesOut") }
    }
    var currentBillingPeriodKey: String {
        get { UserDefaults.standard.string(forKey: "CurrentBillingPeriodKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "CurrentBillingPeriodKey") }
    }

    var latencyHost: String {
        get {
            let stored = UserDefaults.standard.string(forKey: "LatencyHost")?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let stored, !stored.isEmpty, LatencyHost.probeURL(for: stored) != nil {
                return stored
            }
            return LatencyHost.defaultHost
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard LatencyHost.probeURL(for: trimmed) != nil else { return }
            UserDefaults.standard.set(trimmed, forKey: "LatencyHost")
            monitorModel.latencyHost = trimmed
            latencyProbes.removeAll(keepingCapacity: true)
            monitorModel.quality = .unknown
            monitorModel.jitterText = "—"
            monitorModel.lossText = "—"
            currentLatency = "Measuring…"
            monitorModel.latencyText = currentLatency
            buildMenu()
            measureLatency()
        }
    }

    var dailyBytesIn: UInt64 {
        get { UInt64Defaults.get("DailyBytesIn") }
        set { UInt64Defaults.set(newValue, forKey: "DailyBytesIn") }
    }
    var dailyBytesOut: UInt64 {
        get { UInt64Defaults.get("DailyBytesOut") }
        set { UInt64Defaults.set(newValue, forKey: "DailyBytesOut") }
    }
    var monthlyBytesIn: UInt64 {
        get { UInt64Defaults.get("MonthlyBytesIn") }
        set { UInt64Defaults.set(newValue, forKey: "MonthlyBytesIn") }
    }
    var monthlyBytesOut: UInt64 {
        get { UInt64Defaults.get("MonthlyBytesOut") }
        set { UInt64Defaults.set(newValue, forKey: "MonthlyBytesOut") }
    }

    var currentDayString: String {
        get { UserDefaults.standard.string(forKey: "CurrentDayString") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "CurrentDayString") }
    }
    var currentMonthString: String {
        get { UserDefaults.standard.string(forKey: "CurrentMonthString") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "CurrentMonthString") }
    }

    var localIP: String = "Fetching..."
    var publicIP: String = "Fetching..."
    var currentLatency: String = "Measuring..."

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: statusItemLength)
        if let button = statusItem?.button {
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 11.0, weight: .regular)
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        setupPopover()

        let stats = getNetworkStatsPerInterface()
        availableInterfaces = Array(stats.keys).sorted()

        let (totalIn, totalOut) = getAggregatedStats(stats)
        previousBytesIn = totalIn
        previousBytesOut = totalOut
        initialBytesIn = totalIn
        initialBytesOut = totalOut

        monitorModel.showInBits = showInBits
        monitorModel.compactMode = compactMode
        monitorModel.selectedInterface = selectedInterface
        monitorModel.updateInterval = updateInterval
        monitorModel.latencyHost = latencyHost
        monitorModel.monitorVPNOnly = monitorVPNOnly
        if let raw = UserDefaults.standard.object(forKey: "ChartTimeRange") as? Double,
           let range = ChartTimeRange(rawValue: raw) {
            monitorModel.chartRange = range
        }
        monitorModel.loadSpeedTestHistory()
        monitorModel.billingLimit = billingCycleLimit
        monitorModel.billingStartDay = billingCycleStartDay

        checkDateRollover()
        fetchLocalIP()
        fetchPublicIP()
        refreshWiFiInfo()

        buildMenu()
        restartTimer()
    }

    private func setupPopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 360, height: 560)
        popover.contentViewController = NSHostingController(
            rootView: HistoryPopoverView(
                model: monitorModel,
                onRunSpeedTest: { [weak self] in self?.runSpeedTest() },
                onRefreshIPs: { [weak self] in self?.refreshIPs() },
                onQuit: { [weak self] in self?.quitApp() }
            )
        )
        self.popover = popover
    }

    @objc func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }
        let isRightClick = event.type == .rightMouseUp
            || event.modifierFlags.contains(.control)

        if isRightClick {
            closePopover()
            buildMenu()
            if let button = statusItem?.button, let menu = statusMenu {
                // Temporarily attach so AppKit positions the menu under the item.
                statusItem?.menu = menu
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
                statusItem?.menu = nil
            }
        } else {
            togglePopover()
        }
    }

    func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func closePopover() {
        popover?.performClose(nil)
    }

    @objc func showGraph() {
        if popover?.isShown != true {
            togglePopover()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        // no-op; hook kept for future focus handling
    }

    // MARK: - Period / IP / latency

    func checkDateRollover() {
        let today = UsagePeriod.dayString()
        if today != currentDayString {
            currentDayString = today
            dailyBytesIn = 0
            dailyBytesOut = 0
        }

        let thisMonth = UsagePeriod.monthString()
        if thisMonth != currentMonthString {
            currentMonthString = thisMonth
            monthlyBytesIn = 0
            monthlyBytesOut = 0
        }

        let billingKey = BillingCycle.periodKey(startDay: billingCycleStartDay)
        if billingKey != currentBillingPeriodKey {
            currentBillingPeriodKey = billingKey
            billingBytesIn = 0
            billingBytesOut = 0
            UserDefaults.standard.removeObject(forKey: "LastBillingLimitNotified")
            UserDefaults.standard.removeObject(forKey: "LastBillingWarnNotified")
        }
    }

    func fetchLocalIP() {
        var ipv4: String?
        var ipv6: String?

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            DispatchQueue.main.async {
                self.localIP = "Unavailable"
                self.monitorModel.localIP = "Unavailable"
                self.refreshInfoMenuItems()
            }
            return
        }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            guard let addr = current.pointee.ifa_addr else { continue }
            let family = addr.pointee.sa_family
            let name = String(cString: current.pointee.ifa_name)

            // Prefer primary Wi-Fi / Ethernet interfaces.
            guard name == "en0" || name == "en1" else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }

            var address = String(cString: hostname)
            if let percentIndex = address.firstIndex(of: "%") {
                address = String(address[..<percentIndex])
            }

            if family == UInt8(AF_INET), ipv4 == nil {
                ipv4 = address
            } else if family == UInt8(AF_INET6), ipv6 == nil {
                ipv6 = address
            }
        }

        let address = ipv4 ?? ipv6 ?? "Unavailable"
        DispatchQueue.main.async {
            self.localIP = address
            self.monitorModel.localIP = address
            self.refreshInfoMenuItems()
        }
    }

    func fetchPublicIP() {
        guard let url = URL(string: "https://api.ipify.org") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let ip: String
            if let data, let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                ip = text
            } else {
                ip = "Unavailable"
            }
            DispatchQueue.main.async {
                self?.publicIP = ip
                self?.monitorModel.publicIP = ip
                self?.refreshInfoMenuItems()
            }
        }.resume()
    }

    func measureLatency() {
        guard let url = LatencyHost.probeURL(for: latencyHost) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 2.0
        request.cachePolicy = .reloadIgnoringLocalCacheData

        latencyTask?.cancel()
        let start = Date()
        latencyTask = URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error, (error as NSError).code == NSURLErrorCancelled {
                    return
                }

                let httpOK: Bool = {
                    if error != nil { return false }
                    if let status = (response as? HTTPURLResponse)?.statusCode {
                        // Many hosts reject HEAD; still treat a fast response as reachability.
                        return status < 500
                    }
                    return true
                }()

                let probe: LatencyProbe
                if httpOK {
                    let ms = Date().timeIntervalSince(start) * 1000
                    probe = LatencyProbe(rttMs: ms)
                    self.currentLatency = String(format: "%.0fms", ms)
                } else {
                    probe = LatencyProbe(rttMs: nil)
                    self.currentLatency = "Timeout"
                }

                self.latencyProbes.append(probe)
                if self.latencyProbes.count > ConnectionQualityCalculator.windowSize {
                    self.latencyProbes.removeFirst(self.latencyProbes.count - ConnectionQualityCalculator.windowSize)
                }

                let stats = ConnectionQualityCalculator.evaluate(self.latencyProbes)
                self.monitorModel.applyLatencyStats(stats)
                // Keep latest single-probe text until we have a stable average.
                if stats.averageMs == nil {
                    self.monitorModel.latencyText = self.currentLatency
                }
                self.refreshInfoMenuItems()
                self.refreshMenuBarTitle()
            }
        }
        latencyTask?.resume()
    }

    func refreshWiFiInfo() {
        let status = WiFiInfoProvider.current()
        monitorModel.wifi = status
    }

    func measureDNSLatency() {
        let host = UserDefaults.standard.string(forKey: "DNSLatencyHost") ?? "example.com"
        monitorModel.dnsHost = host
        let start = Date()
        DispatchQueue.global(qos: .utility).async {
            var hints = addrinfo(
                ai_flags: AI_ADDRCONFIG,
                ai_family: AF_UNSPEC,
                ai_socktype: SOCK_STREAM,
                ai_protocol: 0,
                ai_addrlen: 0,
                ai_canonname: nil,
                ai_addr: nil,
                ai_next: nil
            )
            var result: UnsafeMutablePointer<addrinfo>?
            let status = getaddrinfo(host, "443", &hints, &result)
            if let result { freeaddrinfo(result) }
            let ms = Date().timeIntervalSince(start) * 1000
            DispatchQueue.main.async {
                if status == 0 {
                    self.monitorModel.dnsLatencyText = String(format: "%.0fms", ms)
                } else {
                    self.monitorModel.dnsLatencyText = "Fail"
                }
                self.refreshInfoMenuItems()
            }
        }
    }

    private var speedTestMeasID = ""

    @objc func runSpeedTest() {
        guard !isSpeedTesting else { return }

        speedTestMeasID = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        guard let downloadURL = URL(string: "https://speed.cloudflare.com/__down?bytes=20000000&measId=\(speedTestMeasID)") else { return }

        monitorModel.speedTestPhase = .download
        monitorModel.lastSpeedTestError = nil
        monitorModel.lastDownloadResult = nil
        monitorModel.lastUploadResult = nil
        buildMenu()

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.postNotification(
                    id: "SpeedTestStart",
                    title: "Speed Test Started",
                    body: "Download 20MB, then upload 10MB…"
                )
            }
        }

        var request = URLRequest(url: downloadURL)
        request.timeoutInterval = 120
        applyCloudflareHeaders(to: &request)

        let downloadStart = Date()
        speedTestTask = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }

                if let data, error == nil, !data.isEmpty {
                    let elapsed = max(Date().timeIntervalSince(downloadStart), 0.001)
                    let speedBytes = Double(data.count) / elapsed
                    let speedStr = self.formatData(UInt64(speedBytes), rate: true)
                    self.monitorModel.lastDownloadResult = speedStr
                    self.startUploadSpeedTest()
                } else {
                    let message = error?.localizedDescription ?? "Download failed"
                    self.finishSpeedTest(error: message)
                }
            }
        }
        speedTestTask?.resume()
    }

    private func applyCloudflareHeaders(to request: inout URLRequest) {
        request.setValue("https://speed.cloudflare.com", forHTTPHeaderField: "Origin")
        request.setValue("https://speed.cloudflare.com/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X) NetworkMon/1.3",
            forHTTPHeaderField: "User-Agent"
        )
    }

    private func startUploadSpeedTest() {
        guard let uploadURL = URL(string: "https://speed.cloudflare.com/__up?measId=\(speedTestMeasID)") else {
            finishSpeedTest(error: "Invalid upload URL")
            return
        }

        monitorModel.speedTestPhase = .upload
        buildMenu()

        let payloadSize = 10_000_000
        var payload = Data(count: payloadSize)
        payload.withUnsafeMutableBytes { rawBuffer in
            if let base = rawBuffer.baseAddress {
                arc4random_buf(base, payloadSize)
            }
        }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = payload
        applyCloudflareHeaders(to: &request)

        let uploadStart = Date()
        speedTestTask = URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async {
                guard let self else { return }

                let status = (response as? HTTPURLResponse)?.statusCode
                let ok: Bool = {
                    if error != nil { return false }
                    if let status { return (200...299).contains(status) }
                    return true
                }()
                if ok {
                    let elapsed = max(Date().timeIntervalSince(uploadStart), 0.001)
                    let speedBytes = Double(payloadSize) / elapsed
                    let speedStr = self.formatData(UInt64(speedBytes), rate: true)
                    self.monitorModel.lastUploadResult = speedStr
                    self.finishSpeedTest(error: nil)
                } else {
                    let message = error?.localizedDescription
                        ?? "Upload failed (HTTP \(status ?? 0))"
                    self.finishSpeedTest(error: message)
                }
            }
        }
        speedTestTask?.resume()
    }

    private func finishSpeedTest(error: String?) {
        monitorModel.speedTestPhase = .idle
        speedTestTask = nil
        buildMenu()

        if let error {
            monitorModel.lastSpeedTestError = error
            postNotification(id: "SpeedTestFailed", title: "Speed Test Failed", body: error)
            return
        }

        let down = monitorModel.lastDownloadResult ?? "—"
        let up = monitorModel.lastUploadResult ?? "—"
        monitorModel.recordSpeedTest(download: down, upload: up)
        postNotification(
            id: "SpeedTestDone",
            title: "Speed Test Complete",
            body: "↓ \(down)   ↑ \(up)"
        )
    }

    private func postNotification(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func checkDataCap() {
        if dataLimit > 0, (dailyBytesIn + dailyBytesOut) > dataLimit {
            let lastNotified = UserDefaults.standard.string(forKey: "LastDataLimitNotified") ?? ""
            if lastNotified != currentDayString {
                UserDefaults.standard.set(currentDayString, forKey: "LastDataLimitNotified")
                postNotification(
                    id: "DataLimit",
                    title: "Daily Data Limit Exceeded",
                    body: "You have exceeded your daily data limit of \(formatData(dataLimit, rate: false))."
                )
            }
        }

        let billingTotal = billingBytesIn + billingBytesOut
        guard billingCycleLimit > 0 else { return }

        let warnAt = UInt64(Double(billingCycleLimit) * 0.8)
        if billingTotal >= warnAt, billingTotal <= billingCycleLimit {
            let lastWarn = UserDefaults.standard.string(forKey: "LastBillingWarnNotified") ?? ""
            if lastWarn != currentBillingPeriodKey {
                UserDefaults.standard.set(currentBillingPeriodKey, forKey: "LastBillingWarnNotified")
                postNotification(
                    id: "BillingWarn",
                    title: "Billing Cycle 80% Used",
                    body: "You have used \(formatData(billingTotal, rate: false)) of \(formatData(billingCycleLimit, rate: false)) this cycle."
                )
            }
        }

        if billingTotal > billingCycleLimit {
            let lastHit = UserDefaults.standard.string(forKey: "LastBillingLimitNotified") ?? ""
            if lastHit != currentBillingPeriodKey {
                UserDefaults.standard.set(currentBillingPeriodKey, forKey: "LastBillingLimitNotified")
                postNotification(
                    id: "BillingLimit",
                    title: "Billing Cycle Limit Exceeded",
                    body: "You have exceeded your billing-cycle limit of \(formatData(billingCycleLimit, rate: false))."
                )
            }
        }
    }

    func getAggregatedStats(_ stats: [String: (UInt64, UInt64)]) -> (UInt64, UInt64) {
        if monitorVPNOnly {
            var totalIn: UInt64 = 0
            var totalOut: UInt64 = 0
            for (name, vals) in stats where TunnelDetect.isTunnelInterface(name) {
                totalIn += vals.0
                totalOut += vals.1
            }
            return (totalIn, totalOut)
        }
        if selectedInterface == "All" {
            var totalIn: UInt64 = 0
            var totalOut: UInt64 = 0
            for (_, vals) in stats {
                totalIn += vals.0
                totalOut += vals.1
            }
            return (totalIn, totalOut)
        }
        return stats[selectedInterface] ?? (0, 0)
    }

    // MARK: - Menu

    func buildMenu() {
        let menu = NSMenu()

        let (sessionIn, sessionOut) = sessionTotals()
        menu.addItem(disabledItem("Session: \(formatData(sessionIn, rate: false)) ↓, \(formatData(sessionOut, rate: false)) ↑"))
        menu.addItem(disabledItem("Today: \(formatData(dailyBytesIn, rate: false)) ↓, \(formatData(dailyBytesOut, rate: false)) ↑"))
        menu.addItem(disabledItem("This Month: \(formatData(monthlyBytesIn, rate: false)) ↓, \(formatData(monthlyBytesOut, rate: false)) ↑"))
        menu.addItem(.separator())

        let graphItem = NSMenuItem(title: "Show Graph", action: #selector(showGraph), keyEquivalent: "g")
        graphItem.target = self
        menu.addItem(graphItem)
        menu.addItem(.separator())

        let localIpItem = NSMenuItem(title: "Local IP: \(localIP)", action: #selector(copyLocalIP), keyEquivalent: "")
        localIpItem.target = self
        menu.addItem(localIpItem)

        let publicIpItem = NSMenuItem(title: "Public IP: \(publicIP)", action: #selector(copyPublicIP), keyEquivalent: "")
        publicIpItem.target = self
        menu.addItem(publicIpItem)

        let refreshIPItem = NSMenuItem(title: "Refresh IPs", action: #selector(refreshIPs), keyEquivalent: "r")
        refreshIPItem.target = self
        menu.addItem(refreshIPItem)

        menu.addItem(disabledItem("Quality: \(monitorModel.quality.title)  ·  \(currentLatency)  ·  j\(monitorModel.jitterText)  ·  loss \(monitorModel.lossText)"))

        let latencyHostItem = NSMenuItem(title: "Latency Host: \(latencyHost)", action: nil, keyEquivalent: "")
        let latencyHostMenu = NSMenu()
        for preset in LatencyHost.presets {
            let item = NSMenuItem(title: "\(preset.title) (\(preset.host))", action: #selector(setLatencyHost(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.host
            item.state = latencyHost == preset.host ? .on : .off
            latencyHostMenu.addItem(item)
        }
        latencyHostMenu.addItem(.separator())
        let customItem = NSMenuItem(title: "Custom…", action: #selector(promptCustomLatencyHost), keyEquivalent: "")
        customItem.target = self
        let isCustom = !LatencyHost.presets.contains(where: { $0.host == latencyHost })
        customItem.state = isCustom ? .on : .off
        latencyHostMenu.addItem(customItem)
        latencyHostItem.submenu = latencyHostMenu
        menu.addItem(latencyHostItem)

        if monitorModel.wifi.connected || monitorModel.wifi.poweredOn {
            menu.addItem(disabledItem(monitorModel.wifi.summaryLine))
        }
        if monitorModel.vpnActive {
            menu.addItem(disabledItem("VPN/tunnel: \(monitorModel.tunnelInterfaces.joined(separator: ", "))"))
        } else if monitorVPNOnly {
            menu.addItem(disabledItem("VPN/tunnel: none active"))
        }
        menu.addItem(.separator())

        let interfaceItem = NSMenuItem(title: "Interface: \(selectedInterface)", action: nil, keyEquivalent: "")
        let interfaceMenu = NSMenu()
        let allItem = NSMenuItem(title: "All", action: #selector(setInterface(_:)), keyEquivalent: "")
        allItem.target = self
        allItem.representedObject = "All"
        allItem.state = selectedInterface == "All" ? .on : .off
        interfaceMenu.addItem(allItem)
        for iface in availableInterfaces {
            let item = NSMenuItem(title: iface, action: #selector(setInterface(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = iface
            item.state = selectedInterface == iface ? .on : .off
            interfaceMenu.addItem(item)
        }
        interfaceItem.submenu = interfaceMenu
        menu.addItem(interfaceItem)

        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        let settingsMenu = NSMenu()

        let intervalMenuItem = NSMenuItem(title: "Update Interval", action: nil, keyEquivalent: "")
        let intervalMenu = NSMenu()
        for (title, value) in [("0.5s", 0.5), ("1s", 1.0), ("2s", 2.0), ("5s", 5.0)] as [(String, TimeInterval)] {
            let item = NSMenuItem(title: title, action: #selector(setInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = updateInterval == value ? .on : .off
            intervalMenu.addItem(item)
        }
        intervalMenuItem.submenu = intervalMenu
        settingsMenu.addItem(intervalMenuItem)

        let thresholdsMenuItem = NSMenuItem(title: "Warning Threshold", action: nil, keyEquivalent: "")
        let thresholdsMenu = NSMenu()
        let thresholds: [(String, Double)] = [
            ("1 MB/s", 1_048_576.0),
            ("5 MB/s", 5_242_880.0),
            ("10 MB/s", 10_485_760.0),
            ("50 MB/s", 52_428_800.0)
        ]
        for (title, value) in thresholds {
            let item = NSMenuItem(title: title, action: #selector(setThreshold(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = speedThreshold == value ? .on : .off
            thresholdsMenu.addItem(item)
        }
        thresholdsMenuItem.submenu = thresholdsMenu
        settingsMenu.addItem(thresholdsMenuItem)

        let limitMenuItem = NSMenuItem(title: "Daily Data Limit", action: nil, keyEquivalent: "")
        let limitMenu = NSMenu()
        let limits: [(String, UInt64)] = [
            ("Unlimited", 0),
            ("1 GB", 1_073_741_824),
            ("5 GB", 5_368_709_120),
            ("10 GB", 10_737_418_240),
            ("50 GB", 53_687_091_200)
        ]
        for (title, value) in limits {
            let item = NSMenuItem(title: title, action: #selector(setDataLimit(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = dataLimit == value ? .on : .off
            limitMenu.addItem(item)
        }
        limitMenuItem.submenu = limitMenu
        settingsMenu.addItem(limitMenuItem)

        let billingLimitItem = NSMenuItem(title: "Billing Cycle Limit", action: nil, keyEquivalent: "")
        let billingLimitMenu = NSMenu()
        for (title, value) in limits {
            let item = NSMenuItem(title: title, action: #selector(setBillingLimit(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = billingCycleLimit == value ? .on : .off
            billingLimitMenu.addItem(item)
        }
        billingLimitItem.submenu = billingLimitMenu
        settingsMenu.addItem(billingLimitItem)

        let cycleDayItem = NSMenuItem(title: "Cycle Start Day: \(billingCycleStartDay)", action: nil, keyEquivalent: "")
        let cycleDayMenu = NSMenu()
        for day in [1, 5, 10, 15, 20, 25, 28] {
            let item = NSMenuItem(title: "Day \(day)", action: #selector(setBillingStartDay(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = day
            item.state = billingCycleStartDay == day ? .on : .off
            cycleDayMenu.addItem(item)
        }
        cycleDayItem.submenu = cycleDayMenu
        settingsMenu.addItem(cycleDayItem)

        let bitsItem = NSMenuItem(title: "Show in Bits (Mbps)", action: #selector(toggleBits), keyEquivalent: "")
        bitsItem.target = self
        bitsItem.state = showInBits ? .on : .off
        settingsMenu.addItem(bitsItem)

        let compactItem = NSMenuItem(title: "Compact Mode", action: #selector(toggleCompact), keyEquivalent: "")
        compactItem.target = self
        compactItem.state = compactMode ? .on : .off
        settingsMenu.addItem(compactItem)

        let hideItem = NSMenuItem(title: "Hide when Inactive", action: #selector(toggleHide), keyEquivalent: "")
        hideItem.target = self
        hideItem.state = hideInactive ? .on : .off
        settingsMenu.addItem(hideItem)

        let vpnOnlyItem = NSMenuItem(title: "Monitor VPN/Tunnel Only", action: #selector(toggleVPNOnly), keyEquivalent: "")
        vpnOnlyItem.target = self
        vpnOnlyItem.state = monitorVPNOnly ? .on : .off
        settingsMenu.addItem(vpnOnlyItem)

        settingsItem.submenu = settingsMenu
        menu.addItem(settingsItem)

        let autoStartItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        autoStartItem.target = self
        autoStartItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(autoStartItem)

        menu.addItem(.separator())

        let speedTitle: String
        switch monitorModel.speedTestPhase {
        case .idle: speedTitle = "Run Speed Test (↓+↑)"
        case .download: speedTitle = "Speed Test: Downloading…"
        case .upload: speedTitle = "Speed Test: Uploading…"
        }
        let speedTestItem = NSMenuItem(title: speedTitle, action: #selector(runSpeedTest), keyEquivalent: "")
        speedTestItem.target = self
        speedTestItem.isEnabled = !isSpeedTesting
        menu.addItem(speedTestItem)

        let exitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        exitItem.target = self
        menu.addItem(exitItem)

        statusMenu = menu
        // Do not assign statusItem.menu permanently — left-click opens the graph popover.
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func sessionTotals() -> (UInt64, UInt64) {
        let sessionIn = previousBytesIn >= initialBytesIn ? previousBytesIn - initialBytesIn : 0
        let sessionOut = previousBytesOut >= initialBytesOut ? previousBytesOut - initialBytesOut : 0
        return (sessionIn, sessionOut)
    }

    /// Updates dynamic menu titles without rebuilding the whole menu (avoids flicker while open).
    func refreshInfoMenuItems() {
        let (sessionIn, sessionOut) = sessionTotals()
        monitorModel.sessionIn = sessionIn
        monitorModel.sessionOut = sessionOut
        monitorModel.dailyIn = dailyBytesIn
        monitorModel.dailyOut = dailyBytesOut
        monitorModel.monthlyIn = monthlyBytesIn
        monitorModel.monthlyOut = monthlyBytesOut
        monitorModel.billingIn = billingBytesIn
        monitorModel.billingOut = billingBytesOut
        monitorModel.billingLimit = billingCycleLimit
        monitorModel.billingStartDay = billingCycleStartDay

        guard let items = statusMenu?.items else { return }

        for item in items {
            if item.title.hasPrefix("Session:") {
                item.title = "Session: \(formatData(sessionIn, rate: false)) ↓, \(formatData(sessionOut, rate: false)) ↑"
            } else if item.title.hasPrefix("Today:") {
                item.title = "Today: \(formatData(dailyBytesIn, rate: false)) ↓, \(formatData(dailyBytesOut, rate: false)) ↑"
            } else if item.title.hasPrefix("This Month:") {
                item.title = "This Month: \(formatData(monthlyBytesIn, rate: false)) ↓, \(formatData(monthlyBytesOut, rate: false)) ↑"
            } else if item.title.hasPrefix("Local IP:") {
                item.title = "Local IP: \(localIP)"
            } else if item.title.hasPrefix("Public IP:") {
                item.title = "Public IP: \(publicIP)"
            } else if item.title.hasPrefix("Quality:") {
                item.title = "Quality: \(monitorModel.quality.title)  ·  \(currentLatency)  ·  j\(monitorModel.jitterText)  ·  loss \(monitorModel.lossText)"
            } else if item.title.hasPrefix("Latency Host:") {
                item.title = "Latency Host: \(latencyHost)"
            } else if item.title.contains(" dBm") || item.title.contains("Wi‑Fi") || item.title.contains("Mbps TX") {
                item.title = monitorModel.wifi.summaryLine
            }
        }
    }

    // MARK: - Actions

    @objc func setLatencyHost(_ sender: NSMenuItem) {
        guard let host = sender.representedObject as? String else { return }
        latencyHost = host
    }

    @objc func promptCustomLatencyHost() {
        let alert = NSAlert()
        alert.messageText = "Latency Host"
        alert.informativeText = "Enter a hostname or IP to probe over HTTPS (HEAD)."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(string: latencyHost)
        field.placeholderString = "1.1.1.1 or example.com"
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard LatencyHost.probeURL(for: value) != nil else {
            let err = NSAlert()
            err.messageText = "Invalid Host"
            err.informativeText = "Could not build an HTTPS probe URL from “\(value)”."
            err.runModal()
            return
        }
        latencyHost = value
    }

    @objc func setInterface(_ sender: NSMenuItem) {
        guard let val = sender.representedObject as? String else { return }
        selectedInterface = val

        let stats = getNetworkStatsPerInterface()
        let (totalIn, totalOut) = getAggregatedStats(stats)
        previousBytesIn = totalIn
        previousBytesOut = totalOut
        initialBytesIn = totalIn
        initialBytesOut = totalOut
        monitorModel.clearChart()
        updateNetworkStats()
    }

    @objc func setInterval(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? TimeInterval {
            updateInterval = value
        }
    }

    @objc func setThreshold(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? Double {
            speedThreshold = value
        }
    }

    @objc func setDataLimit(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? UInt64 {
            dataLimit = value
            if value > 0 {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            }
        }
    }

    @objc func setBillingLimit(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? UInt64 {
            billingCycleLimit = value
            if value > 0 {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            }
        }
    }

    @objc func setBillingStartDay(_ sender: NSMenuItem) {
        if let day = sender.representedObject as? Int {
            billingCycleStartDay = day
        }
    }

    @objc func copyLocalIP() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(localIP, forType: .string)
    }

    @objc func copyPublicIP() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(publicIP, forType: .string)
    }

    @objc func refreshIPs() {
        localIP = "Fetching…"
        publicIP = "Fetching…"
        monitorModel.localIP = localIP
        monitorModel.publicIP = publicIP
        refreshInfoMenuItems()
        fetchLocalIP()
        fetchPublicIP()
    }

    @objc func toggleBits() { showInBits.toggle() }
    @objc func toggleCompact() { compactMode.toggle() }
    @objc func toggleHide() { hideInactive.toggle() }
    @objc func toggleVPNOnly() { monitorVPNOnly.toggle() }

    @objc func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
            buildMenu()
        } catch {
            NSLog("Failed to toggle launch at login: \(error)")
        }
    }

    @objc func quitApp() { NSApp.terminate(nil) }

    // MARK: - Timers / stats

    func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.updateNetworkStats()
        }
        RunLoop.main.add(timer!, forMode: .common)
        updateNetworkStats()

        latencyTimer?.invalidate()
        latencyTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.measureLatency()
        }
        RunLoop.main.add(latencyTimer!, forMode: .common)
        measureLatency()

        dnsTimer?.invalidate()
        dnsTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            self?.measureDNSLatency()
        }
        RunLoop.main.add(dnsTimer!, forMode: .common)
        measureDNSLatency()

        publicIPTimer?.invalidate()
        publicIPTimer = Timer.scheduledTimer(withTimeInterval: 900.0, repeats: true) { [weak self] _ in
            self?.fetchPublicIP()
            self?.fetchLocalIP()
        }
        RunLoop.main.add(publicIPTimer!, forMode: .common)

        wifiTimer?.invalidate()
        wifiTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.refreshWiFiInfo()
        }
        RunLoop.main.add(wifiTimer!, forMode: .common)
        refreshWiFiInfo()
    }

    func updateNetworkStats() {
        let stats = getNetworkStatsPerInterface()
        let currentIfaces = Array(stats.keys).sorted()
        if currentIfaces != availableInterfaces {
            availableInterfaces = currentIfaces
            buildMenu()
        }

        let tunnels = TunnelDetect.tunnels(in: currentIfaces)
        let vpnNow = !tunnels.isEmpty
        if vpnNow != monitorModel.vpnActive || tunnels != monitorModel.tunnelInterfaces {
            monitorModel.vpnActive = vpnNow
            monitorModel.tunnelInterfaces = tunnels
            buildMenu()
        }

        let (bytesIn, bytesOut) = getAggregatedStats(stats)

        let diffIn = bytesIn >= previousBytesIn ? bytesIn - previousBytesIn : 0
        let diffOut = bytesOut >= previousBytesOut ? bytesOut - previousBytesOut : 0

        var rates: [InterfaceRate] = []
        for (name, vals) in stats {
            let prev = previousInterfaceBytes[name] ?? vals
            let dIn = vals.0 >= prev.0 ? vals.0 - prev.0 : 0
            let dOut = vals.1 >= prev.1 ? vals.1 - prev.1 : 0
            let rIn = Double(dIn) / updateInterval
            let rOut = Double(dOut) / updateInterval
            if rIn > 1 || rOut > 1 || TunnelDetect.isTunnelInterface(name) {
                rates.append(InterfaceRate(name: name, download: rIn, upload: rOut))
            }
        }
        rates.sort { $0.total > $1.total }
        monitorModel.interfaceRates = Array(rates.prefix(8))
        previousInterfaceBytes = stats

        checkDateRollover()
        dailyBytesIn += diffIn
        dailyBytesOut += diffOut
        monthlyBytesIn += diffIn
        monthlyBytesOut += diffOut
        billingBytesIn += diffIn
        billingBytesOut += diffOut

        previousBytesIn = bytesIn
        previousBytesOut = bytesOut

        let speedIn = Double(diffIn) / updateInterval
        let speedOut = Double(diffOut) / updateInterval

        monitorModel.appendSample(download: speedIn, upload: speedOut)

        checkDataCap()
        refreshInfoMenuItems()

        // Keep a fixed-width title even when idle so the item does not jump.
        let displayIn = (hideInactive && speedIn < 1 && speedOut < 1) ? 0.0 : speedIn
        let displayOut = (hideInactive && speedIn < 1 && speedOut < 1) ? 0.0 : speedOut
        statusItem?.button?.attributedTitle = menuBarTitle(download: displayIn, upload: displayOut)
    }

    private func refreshMenuBarTitle() {
        let idle = hideInactive && monitorModel.currentDownload < 1 && monitorModel.currentUpload < 1
        let displayIn = idle ? 0.0 : monitorModel.currentDownload
        let displayOut = idle ? 0.0 : monitorModel.currentUpload
        statusItem?.button?.attributedTitle = menuBarTitle(download: displayIn, upload: displayOut)
    }

    private func menuBarTitle(download: Double, upload: Double) -> NSAttributedString {
        let inStr = NetworkMonFormat.formatStableRate(download, showInBits: showInBits)
        let outStr = NetworkMonFormat.formatStableRate(upload, showInBits: showInBits)
        let inColor: NSColor = download > speedThreshold ? .systemGreen : .labelColor
        let outColor: NSColor = upload > speedThreshold ? .systemOrange : .labelColor
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11.0, weight: .regular)

        let attr = NSMutableAttributedString(
            string: "\(monitorModel.quality.trayGlyph) ",
            attributes: [.foregroundColor: monitorModel.qualityColor, .font: font]
        )
        attr.append(NSAttributedString(
            string: "↓\(inStr) ",
            attributes: [.foregroundColor: inColor, .font: font]
        ))
        attr.append(NSAttributedString(
            string: "↑\(outStr)",
            attributes: [.foregroundColor: outColor, .font: font]
        ))
        return attr
    }

    func formatData(_ bytes: UInt64, rate: Bool) -> String {
        NetworkMonFormat.formatBytes(bytes, rate: rate, showInBits: showInBits, compactMode: compactMode)
    }

    func getNetworkStatsPerInterface() -> [String: (UInt64, UInt64)] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len: size_t = 0
        if sysctl(&mib, 6, nil, &len, nil, 0) < 0 { return [:] }

        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: len)
        defer { buf.deallocate() }
        if sysctl(&mib, 6, buf, &len, nil, 0) < 0 { return [:] }

        let lim = buf.advanced(by: len)
        var next = buf
        var results: [String: (UInt64, UInt64)] = [:]

        while next < lim {
            let ifm = next.withMemoryRebound(to: if_msghdr.self, capacity: 1) { $0.pointee }
            if Int32(ifm.ifm_type) == RTM_IFINFO2 {
                let if2m = next.withMemoryRebound(to: if_msghdr2.self, capacity: 1) { $0.pointee }

                let nameBuf = UnsafeMutablePointer<CChar>.allocate(capacity: Int(IF_NAMESIZE))
                defer { nameBuf.deallocate() }
                if_indextoname(UInt32(ifm.ifm_index), nameBuf)
                let name = String(cString: nameBuf)

                if !name.isEmpty {
                    results[name] = (if2m.ifm_data.ifi_ibytes, if2m.ifm_data.ifi_obytes)
                }
            }
            next = next.advanced(by: Int(ifm.ifm_msglen))
        }
        return results
    }
}
