import Foundation
import SwiftUI
import ServiceManagement
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

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var timer: Timer?
    var latencyTimer: Timer?
    
    // Total byte tracking for speed
    var previousBytesIn: UInt64 = 0
    var previousBytesOut: UInt64 = 0
    
    // Sparkline history
    var historyIn: [Double] = Array(repeating: 0.0, count: 10)
    var historyOut: [Double] = Array(repeating: 0.0, count: 10)
    
    // Session byte tracking
    var initialBytesIn: UInt64 = 0
    var initialBytesOut: UInt64 = 0
    
    var availableInterfaces: [String] = []

    // Settings
    var updateInterval: TimeInterval {
        get { let v = UserDefaults.standard.double(forKey: "UpdateInterval"); return v > 0 ? v : 1.0 }
        set { UserDefaults.standard.set(newValue, forKey: "UpdateInterval"); restartTimer(); buildMenu() }
    }
    
    var showInBits: Bool {
        get { UserDefaults.standard.bool(forKey: "ShowInBits") }
        set { UserDefaults.standard.set(newValue, forKey: "ShowInBits"); buildMenu(); updateNetworkStats() }
    }
    
    var compactMode: Bool {
        get { UserDefaults.standard.bool(forKey: "CompactMode") }
        set { UserDefaults.standard.set(newValue, forKey: "CompactMode"); buildMenu(); updateNetworkStats() }
    }
    
    var hideInactive: Bool {
        get { UserDefaults.standard.bool(forKey: "HideInactive") }
        set { UserDefaults.standard.set(newValue, forKey: "HideInactive"); buildMenu(); updateNetworkStats() }
    }
    
    var selectedInterface: String {
        get { UserDefaults.standard.string(forKey: "SelectedInterface") ?? "All" }
        set { UserDefaults.standard.set(newValue, forKey: "SelectedInterface"); buildMenu() }
    }
    
    var speedThreshold: Double {
        get { let v = UserDefaults.standard.double(forKey: "SpeedThreshold"); return v > 0 ? v : 5242880.0 }
        set { UserDefaults.standard.set(newValue, forKey: "SpeedThreshold"); buildMenu(); updateNetworkStats() }
    }
    
    var dataLimit: UInt64 {
        get { UInt64(UserDefaults.standard.double(forKey: "DataLimit")) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "DataLimit"); buildMenu() }
    }

    // Daily & Monthly tracking properties
    var dailyBytesIn: UInt64 {
        get { UInt64(UserDefaults.standard.double(forKey: "DailyBytesIn")) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "DailyBytesIn") }
    }
    var dailyBytesOut: UInt64 {
        get { UInt64(UserDefaults.standard.double(forKey: "DailyBytesOut")) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "DailyBytesOut") }
    }
    var monthlyBytesIn: UInt64 {
        get { UInt64(UserDefaults.standard.double(forKey: "MonthlyBytesIn")) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "MonthlyBytesIn") }
    }
    var monthlyBytesOut: UInt64 {
        get { UInt64(UserDefaults.standard.double(forKey: "MonthlyBytesOut")) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "MonthlyBytesOut") }
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12.0, weight: .regular)
        
        let stats = getNetworkStatsPerInterface()
        self.availableInterfaces = Array(stats.keys).sorted()
        
        let (totalIn, totalOut) = getAggregatedStats(stats)
        self.previousBytesIn = totalIn
        self.previousBytesOut = totalOut
        self.initialBytesIn = totalIn
        self.initialBytesOut = totalOut

        checkDateRollover()
        fetchLocalIP()
        fetchPublicIP()

        buildMenu()
        restartTimer()
    }
    
    func checkDateRollover() {
        let formatter = DateFormatter()
        
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        if today != currentDayString {
            currentDayString = today
            dailyBytesIn = 0
            dailyBytesOut = 0
        }
        
        formatter.dateFormat = "yyyy-MM"
        let thisMonth = formatter.string(from: Date())
        if thisMonth != currentMonthString {
            currentMonthString = thisMonth
            monthlyBytesIn = 0
            monthlyBytesOut = 0
        }
    }

    func fetchLocalIP() {
        var address: String = "Unavailable"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                let interface = ptr?.pointee
                let addrFamily = interface?.ifa_addr.pointee.sa_family
                if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {
                    let name = String(cString: (interface?.ifa_name)!)
                    // Prioritize active Wi-Fi or Ethernet
                    if name == "en0" || name == "en1" {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(interface?.ifa_addr, socklen_t((interface?.ifa_addr.pointee.sa_len)!),
                                    &hostname, socklen_t(hostname.count),
                                    nil, socklen_t(0), NI_NUMERICHOST)
                        address = String(cString: hostname)
                        break
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        DispatchQueue.main.async {
            self.localIP = address
            self.buildMenu()
        }
    }

    func fetchPublicIP() {
        guard let url = URL(string: "https://api.ipify.org") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            if let data = data, let ip = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self?.publicIP = ip
                    self?.buildMenu()
                }
            } else {
                DispatchQueue.main.async {
                    self?.publicIP = "Unavailable"
                    self?.buildMenu()
                }
            }
        }.resume()
    }
    
    func measureLatency() {
        guard let url = URL(string: "https://1.1.1.1") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 2.0
        
        let start = Date()
        URLSession.shared.dataTask(with: request) { [weak self] _, _, error in
            DispatchQueue.main.async {
                if error == nil {
                    let ms = Int(Date().timeIntervalSince(start) * 1000)
                    self?.currentLatency = "\(ms)ms"
                } else {
                    self?.currentLatency = "Timeout"
                }
                self?.buildMenu()
            }
        }.resume()
    }
    
    @objc func runSpeedTest() {
        guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=20000000") else { return }
        let start = Date()
        
        let content = UNMutableNotificationContent()
        content.title = "Speed Test Started"
        content.body = "Downloading 20MB payload... Please wait."
        let req = UNNotificationRequest(identifier: "SpeedTestStart", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
        
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            DispatchQueue.main.async {
                if let data = data, error == nil {
                    let elapsed = Date().timeIntervalSince(start)
                    let speedBytes = Double(data.count) / elapsed
                    let speedStr = self?.formatData(UInt64(speedBytes), rate: true) ?? ""
                    
                    let doneContent = UNMutableNotificationContent()
                    doneContent.title = "Speed Test Complete"
                    doneContent.body = "Max Download Speed: \(speedStr)"
                    let doneReq = UNNotificationRequest(identifier: "SpeedTestDone", content: doneContent, trigger: nil)
                    UNUserNotificationCenter.current().add(doneReq)
                }
            }
        }.resume()
    }
    
    func generateSparkline(_ data: [Double]) -> String {
        let blocks = [" ", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
        let maxVal = data.max() ?? 0
        if maxVal == 0 { return String(repeating: " ", count: data.count) }
        
        var sparkline = ""
        for value in data {
            let ratio = value / maxVal
            let index = Int(ratio * Double(blocks.count - 1))
            let clampedIndex = max(0, min(blocks.count - 1, index))
            sparkline.append(blocks[clampedIndex])
        }
        return sparkline
    }
    
    func checkDataCap() {
        if dataLimit > 0 && (dailyBytesIn + dailyBytesOut) > dataLimit {
            let lastNotified = UserDefaults.standard.string(forKey: "LastDataLimitNotified") ?? ""
            if lastNotified != currentDayString {
                UserDefaults.standard.set(currentDayString, forKey: "LastDataLimitNotified")
                let content = UNMutableNotificationContent()
                content.title = "Data Limit Exceeded"
                content.body = "You have exceeded your daily data limit of \(formatData(dataLimit, rate: false))."
                let request = UNNotificationRequest(identifier: "DataLimit", content: content, trigger: nil)
                UNUserNotificationCenter.current().add(request)
            }
        }
    }
    
    func getAggregatedStats(_ stats: [String: (UInt64, UInt64)]) -> (UInt64, UInt64) {
        if selectedInterface == "All" {
            var totalIn: UInt64 = 0
            var totalOut: UInt64 = 0
            for (_, vals) in stats {
                totalIn += vals.0
                totalOut += vals.1
            }
            return (totalIn, totalOut)
        } else {
            let vals = stats[selectedInterface] ?? (0, 0)
            return (vals.0, vals.1)
        }
    }

    func buildMenu() {
        let menu = NSMenu()
        
        // Session Totals Info (Disabled item)
        let sessionIn = previousBytesIn >= initialBytesIn ? previousBytesIn - initialBytesIn : 0
        let sessionOut = previousBytesOut >= initialBytesOut ? previousBytesOut - initialBytesOut : 0
        
        let totalsTitle = "Session: \(formatData(sessionIn, rate: false)) ↓, \(formatData(sessionOut, rate: false)) ↑"
        let totalsItem = NSMenuItem(title: totalsTitle, action: nil, keyEquivalent: "")
        totalsItem.isEnabled = false
        menu.addItem(totalsItem)
        
        let dailyTitle = "Today: \(formatData(dailyBytesIn, rate: false)) ↓, \(formatData(dailyBytesOut, rate: false)) ↑"
        let dailyItem = NSMenuItem(title: dailyTitle, action: nil, keyEquivalent: "")
        dailyItem.isEnabled = false
        menu.addItem(dailyItem)
        
        let monthlyTitle = "This Month: \(formatData(monthlyBytesIn, rate: false)) ↓, \(formatData(monthlyBytesOut, rate: false)) ↑"
        let monthlyItem = NSMenuItem(title: monthlyTitle, action: nil, keyEquivalent: "")
        monthlyItem.isEnabled = false
        menu.addItem(monthlyItem)
        menu.addItem(NSMenuItem.separator())
        
        // IP Address Info
        let localIpItem = NSMenuItem(title: "Local IP: \(localIP)", action: #selector(copyLocalIP), keyEquivalent: "")
        localIpItem.target = self
        menu.addItem(localIpItem)
        
        let publicIpItem = NSMenuItem(title: "Public IP: \(publicIP)", action: #selector(copyPublicIP), keyEquivalent: "")
        publicIpItem.target = self
        menu.addItem(publicIpItem)
        
        let latencyItem = NSMenuItem(title: "Latency (1.1.1.1): \(currentLatency)", action: nil, keyEquivalent: "")
        latencyItem.isEnabled = false
        menu.addItem(latencyItem)
        menu.addItem(NSMenuItem.separator())
        
        // Interface Selection
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
        
        // Settings Submenu
        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        let settingsMenu = NSMenu()
        
        // Interval submenu
        let intervalMenuItem = NSMenuItem(title: "Update Interval", action: nil, keyEquivalent: "")
        let intervalMenu = NSMenu()
        let intervals: [(String, TimeInterval)] = [("0.5s", 0.5), ("1s", 1.0), ("2s", 2.0), ("5s", 5.0)]
        for (title, value) in intervals {
            let item = NSMenuItem(title: title, action: #selector(setInterval(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = value
            item.state = (self.updateInterval == value) ? .on : .off
            intervalMenu.addItem(item)
        }
        intervalMenuItem.submenu = intervalMenu
        settingsMenu.addItem(intervalMenuItem)
        
        // Thresholds submenu
        let thresholdsMenuItem = NSMenuItem(title: "Warning Threshold", action: nil, keyEquivalent: "")
        let thresholdsMenu = NSMenu()
        let thresholds: [(String, Double)] = [
            ("1 MB/s", 1048576.0),
            ("5 MB/s", 5242880.0),
            ("10 MB/s", 10485760.0),
            ("50 MB/s", 52428800.0)
        ]
        for (title, value) in thresholds {
            let item = NSMenuItem(title: title, action: #selector(setThreshold(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = value
            item.state = (self.speedThreshold == value) ? .on : .off
            thresholdsMenu.addItem(item)
        }
        thresholdsMenuItem.submenu = thresholdsMenu
        settingsMenu.addItem(thresholdsMenuItem)
        
        // Data Limit submenu
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
            item.target = self; item.representedObject = value
            item.state = (self.dataLimit == value) ? .on : .off
            limitMenu.addItem(item)
        }
        limitMenuItem.submenu = limitMenu
        settingsMenu.addItem(limitMenuItem)
        
        // Display Toggles
        let bitsItem = NSMenuItem(title: "Show in Bits (Mbps)", action: #selector(toggleBits), keyEquivalent: "")
        bitsItem.target = self; bitsItem.state = showInBits ? .on : .off
        settingsMenu.addItem(bitsItem)
        
        let compactItem = NSMenuItem(title: "Compact Mode", action: #selector(toggleCompact), keyEquivalent: "")
        compactItem.target = self; compactItem.state = compactMode ? .on : .off
        settingsMenu.addItem(compactItem)
        
        let hideItem = NSMenuItem(title: "Hide when Inactive", action: #selector(toggleHide), keyEquivalent: "")
        hideItem.target = self; hideItem.state = hideInactive ? .on : .off
        settingsMenu.addItem(hideItem)
        
        settingsItem.submenu = settingsMenu
        menu.addItem(settingsItem)
        
        let autoStartItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        autoStartItem.target = self
        autoStartItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(autoStartItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let speedTestItem = NSMenuItem(title: "Run Speed Test", action: #selector(runSpeedTest), keyEquivalent: "")
        speedTestItem.target = self
        menu.addItem(speedTestItem)
        
        let exitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        exitItem.target = self
        menu.addItem(exitItem)
        
        statusItem?.menu = menu
    }
    
    @objc func setInterface(_ sender: NSMenuItem) {
        if let val = sender.representedObject as? String {
            selectedInterface = val
            // Reset counters
            let stats = getNetworkStatsPerInterface()
            let (totalIn, totalOut) = getAggregatedStats(stats)
            self.previousBytesIn = totalIn
            self.previousBytesOut = totalOut
            self.initialBytesIn = totalIn
            self.initialBytesOut = totalOut
            updateNetworkStats()
        }
    }
    @objc func setInterval(_ sender: NSMenuItem) { if let value = sender.representedObject as? TimeInterval { self.updateInterval = value } }
    @objc func setThreshold(_ sender: NSMenuItem) { if let value = sender.representedObject as? Double { self.speedThreshold = value } }
    @objc func setDataLimit(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? UInt64 {
            dataLimit = value
            if value > 0 {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            }
        }
    }
    
    @objc func copyLocalIP() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(localIP, forType: .string)
    }
    
    @objc func copyPublicIP() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(publicIP, forType: .string)
    }
    @objc func toggleBits() { showInBits.toggle() }
    @objc func toggleCompact() { compactMode.toggle() }
    @objc func toggleHide() { hideInactive.toggle() }
    @objc func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
            buildMenu()
        } catch { print("Failed to toggle launch at login: \(error)") }
    }
    @objc func quitApp() { NSApp.terminate(nil) }

    func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: self.updateInterval, repeats: true) { [weak self] _ in
            self?.updateNetworkStats()
        }
        updateNetworkStats()
        
        latencyTimer?.invalidate()
        latencyTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.measureLatency()
        }
        measureLatency()
    }

    func updateNetworkStats() {
        let stats = getNetworkStatsPerInterface()
        // Update available interfaces if changed
        let currentIfaces = Array(stats.keys).sorted()
        if currentIfaces != availableInterfaces {
            self.availableInterfaces = currentIfaces
            buildMenu()
        }
        
        let (bytesIn, bytesOut) = getAggregatedStats(stats)
        
        let diffIn = bytesIn >= previousBytesIn ? bytesIn - previousBytesIn : 0
        let diffOut = bytesOut >= previousBytesOut ? bytesOut - previousBytesOut : 0
        
        checkDateRollover()
        dailyBytesIn += diffIn
        dailyBytesOut += diffOut
        monthlyBytesIn += diffIn
        monthlyBytesOut += diffOut
        
        self.previousBytesIn = bytesIn
        self.previousBytesOut = bytesOut
        
        let speedIn = Double(diffIn) / self.updateInterval
        let speedOut = Double(diffOut) / self.updateInterval
        
        historyIn.removeFirst()
        historyIn.append(speedIn)
        historyOut.removeFirst()
        historyOut.append(speedOut)
        
        checkDataCap()
        
        if hideInactive && Int(speedIn) == 0 && Int(speedOut) == 0 {
            let idleIcon = NSTextAttachment()
            if let img = NSImage(systemSymbolName: "network", accessibilityDescription: nil) {
                img.isTemplate = true
                idleIcon.image = img
                idleIcon.bounds = CGRect(x: 0, y: -2, width: 14, height: 14)
                statusItem?.button?.attributedTitle = NSAttributedString(attachment: idleIcon)
            } else {
                statusItem?.button?.title = "Net"
            }
            return
        }
        
        let inStr = formatData(UInt64(speedIn), rate: true)
        let outStr = formatData(UInt64(speedOut), rate: true)
        
        let sparkIn = generateSparkline(historyIn)
        let sparkOut = generateSparkline(historyOut)
        
        let attrString = NSMutableAttributedString()
        
        // Colors
        let inColor: NSColor = Double(speedIn) > speedThreshold ? .systemGreen : .labelColor
        let outColor: NSColor = Double(speedOut) > speedThreshold ? .systemOrange : .labelColor
        
        if compactMode {
            attrString.append(NSAttributedString(string: "↓\(inStr) \(sparkIn) ", attributes: [.foregroundColor: inColor]))
            attrString.append(NSAttributedString(string: "↑\(outStr) \(sparkOut)", attributes: [.foregroundColor: outColor]))
        } else {
            // Add SF symbols
            if let downImg = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil) {
                let attach = NSTextAttachment()
                downImg.isTemplate = true
                attach.image = downImg
                attach.bounds = CGRect(x: 0, y: -2, width: 12, height: 12)
                attrString.append(NSAttributedString(attachment: attach))
                attrString.append(NSAttributedString(string: " ", attributes: [.foregroundColor: inColor]))
            } else {
                attrString.append(NSAttributedString(string: "↓", attributes: [.foregroundColor: inColor]))
            }
            attrString.append(NSAttributedString(string: "\(inStr) \(sparkIn)  ", attributes: [.foregroundColor: inColor]))
            
            if let upImg = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: nil) {
                let attach = NSTextAttachment()
                upImg.isTemplate = true
                attach.image = upImg
                attach.bounds = CGRect(x: 0, y: -2, width: 12, height: 12)
                attrString.append(NSAttributedString(attachment: attach))
                attrString.append(NSAttributedString(string: " ", attributes: [.foregroundColor: outColor]))
            } else {
                attrString.append(NSAttributedString(string: "↑", attributes: [.foregroundColor: outColor]))
            }
            attrString.append(NSAttributedString(string: "\(outStr) \(sparkOut)", attributes: [.foregroundColor: outColor]))
        }
        
        statusItem?.button?.attributedTitle = attrString
        
        // Update session totals in menu
        if let totalsItem = statusItem?.menu?.items.first(where: { !$0.isEnabled && $0.title.hasPrefix("Session:") }) {
            let sessionIn = previousBytesIn >= initialBytesIn ? previousBytesIn - initialBytesIn : 0
            let sessionOut = previousBytesOut >= initialBytesOut ? previousBytesOut - initialBytesOut : 0
            totalsItem.title = "Session: \(formatData(sessionIn, rate: false)) ↓, \(formatData(sessionOut, rate: false)) ↑"
        }
        
        if let dailyItem = statusItem?.menu?.items.first(where: { !$0.isEnabled && $0.title.hasPrefix("Today:") }) {
            dailyItem.title = "Today: \(formatData(dailyBytesIn, rate: false)) ↓, \(formatData(dailyBytesOut, rate: false)) ↑"
        }
        
        if let monthlyItem = statusItem?.menu?.items.first(where: { !$0.isEnabled && $0.title.hasPrefix("This Month:") }) {
            monthlyItem.title = "This Month: \(formatData(monthlyBytesIn, rate: false)) ↓, \(formatData(monthlyBytesOut, rate: false)) ↑"
        }
    }
    
    func formatData(_ bytes: UInt64, rate: Bool) -> String {
        let value = showInBits ? Double(bytes) * 8 : Double(bytes)
        let suffix = rate ? (showInBits ? "bps" : "B/s") : (showInBits ? "b" : "B")
        
        let kb = showInBits ? 1000.0 : 1024.0
        let mb = kb * kb
        let gb = mb * kb
        
        var formatted = ""
        if value < kb {
            formatted = compactMode ? "\(Int(value))" : "\(Int(value)) \(suffix)"
        } else if value < mb {
            let prefix = compactMode ? "K" : (showInBits ? "K" : "K")
            formatted = String(format: "%.1f \(prefix)\(compactMode ? "" : suffix)", value / kb)
        } else if value < gb {
            let prefix = compactMode ? "M" : (showInBits ? "M" : "M")
            formatted = String(format: "%.1f \(prefix)\(compactMode ? "" : suffix)", value / mb)
        } else {
            let prefix = compactMode ? "G" : (showInBits ? "G" : "G")
            formatted = String(format: "%.2f \(prefix)\(compactMode ? "" : suffix)", value / gb)
        }
        return formatted
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
                
                let nameBuf = UnsafeMutablePointer<CChar>.allocate(capacity: 16)
                if_indextoname(UInt32(ifm.ifm_index), nameBuf)
                let name = String(cString: nameBuf)
                nameBuf.deallocate()
                
                let inBytes = if2m.ifm_data.ifi_ibytes
                let outBytes = if2m.ifm_data.ifi_obytes
                
                if !name.isEmpty {
                    results[name] = (inBytes, outBytes)
                }
            }
            next = next.advanced(by: Int(ifm.ifm_msglen))
        }
        return results
    }
}
