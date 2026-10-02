import CoreWLAN
import Foundation

struct WiFiStatus: Equatable {
    var interfaceName: String?
    var ssid: String?
    var rssiDbm: Int?
    var transmitMbps: Double?
    var poweredOn: Bool
    var connected: Bool

    static let disconnected = WiFiStatus(
        interfaceName: nil,
        ssid: nil,
        rssiDbm: nil,
        transmitMbps: nil,
        poweredOn: false,
        connected: false
    )

    var summaryLine: String {
        guard connected || poweredOn else { return "Wi‑Fi unavailable" }

        var parts: [String] = []
        if let ssid, !ssid.isEmpty {
            parts.append(ssid)
        } else if let interfaceName {
            parts.append(interfaceName)
        } else {
            parts.append("Wi‑Fi")
        }

        if let rssiDbm {
            parts.append("\(rssiDbm) dBm")
        }
        if let transmitMbps, transmitMbps > 0 {
            parts.append(String(format: "%.0f Mbps TX", transmitMbps))
        }
        return parts.joined(separator: " · ")
    }

    var signalLabel: String {
        guard let rssiDbm else { return "—" }
        switch rssiDbm {
        case (-50)...0: return "Excellent"
        case (-60)..<(-50): return "Good"
        case (-70)..<(-60): return "Fair"
        default: return "Weak"
        }
    }
}

enum WiFiInfoProvider {
    static func current() -> WiFiStatus {
        let client = CWWiFiClient.shared()
        guard let iface = client.interface() else {
            return .disconnected
        }

        let powered = iface.powerOn()
        let rssi = iface.rssiValue()
        let tx = iface.transmitRate()
        let ssid = iface.ssid()
        let name = iface.interfaceName

        // rssiValue() returns 0 when not associated.
        let connected = powered && (ssid != nil || rssi < 0)

        return WiFiStatus(
            interfaceName: name,
            ssid: ssid,
            rssiDbm: rssi < 0 ? rssi : nil,
            transmitMbps: tx > 0 ? tx : nil,
            poweredOn: powered,
            connected: connected
        )
    }
}
