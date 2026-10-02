import Darwin
import Foundation

enum NetworkSampler {
    /// Returns interface name → (bytes in, bytes out) using `sysctl` NET_RT_IFLIST2.
    static func statsPerInterface() -> [String: (UInt64, UInt64)] {
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
