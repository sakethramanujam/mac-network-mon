import Foundation

enum TunnelDetect {
    static func isTunnelInterface(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("utun")
            || lower.hasPrefix("ipsec")
            || lower.hasPrefix("ppp")
            || lower.hasPrefix("wg")
            || lower.hasPrefix("tun")
            || lower.hasPrefix("tap")
    }

    static func tunnels(in interfaces: [String]) -> [String] {
        interfaces.filter(isTunnelInterface).sorted()
    }
}
