import Darwin
import Foundation

public enum ARPTable: Sendable {
    public static func load(interfaceName: String? = nil) -> [IPv4Address: MACAddress] {
        var table = loadViaSysctl(interfaceName: interfaceName)
        if table.isEmpty {
            table = loadViaCommand(interfaceName: interfaceName)
        } else {
            let extras = loadViaCommand(interfaceName: interfaceName)
            for (ip, mac) in extras where table[ip] == nil {
                table[ip] = mac
            }
        }
        return table
    }

    public static func parseCommandOutput(_ output: String, interfaceName: String? = nil) -> [IPv4Address: MACAddress] {
        var table: [IPv4Address: MACAddress] = [:]
        let pattern = #"\(([0-9.]+)\) at ([0-9a-fA-F:]+) on ([A-Za-z0-9]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
        let ns = output as NSString
        let matches = regex.matches(in: output, range: NSRange(location: 0, length: ns.length))
        for match in matches {
            guard match.numberOfRanges == 4 else { continue }
            let ipString = ns.substring(with: match.range(at: 1))
            let macString = ns.substring(with: match.range(at: 2))
            let iface = ns.substring(with: match.range(at: 3))
            if let interfaceName, iface != interfaceName { continue }
            guard let ip = IPv4Address(ipString), let mac = MACAddress.parse(macString) else { continue }
            if shouldKeep(ip: ip, mac: mac) {
                table[ip] = mac
            }
        }
        return table
    }

    private static func loadViaCommand(interfaceName: String?) -> [IPv4Address: MACAddress] {
        let output = Command.run("/usr/sbin/arp", ["-an"])
        return parseCommandOutput(output, interfaceName: interfaceName)
    }

    private static func loadViaSysctl(interfaceName: String?) -> [IPv4Address: MACAddress] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO]
        var length = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else {
            return [:]
        }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0 else {
            return [:]
        }

        var table: [IPv4Address: MACAddress] = [:]
        var offset = 0
        let hdrSize = MemoryLayout<rt_msghdr>.stride

        while offset + hdrSize <= length {
            let messageLength: Int = buffer.withUnsafeBytes { raw in
                Int(raw.load(fromByteOffset: offset, as: rt_msghdr.self).rtm_msglen)
            }
            if messageLength <= 0 { break }
            defer { offset += messageLength }
            guard offset + messageLength <= length else { break }

            buffer.withUnsafeBytes { raw in
                let base = raw.baseAddress!.advanced(by: offset)
                let rtm = base.assumingMemoryBound(to: rt_msghdr.self)
                var addrPointer = base.advanced(by: hdrSize)
                let end = base.advanced(by: messageLength)
                var destination: IPv4Address?
                var hardware: MACAddress?

                var bit: Int32 = 1
                while bit <= RTA_IFP, addrPointer < end {
                    if rtm.pointee.rtm_addrs & bit != 0 {
                        let sa = addrPointer.assumingMemoryBound(to: sockaddr.self)
                        let saLen = Int(sa.pointee.sa_len)
                        let aligned = roundup(max(saLen, 1))
                        if bit == RTA_DST, sa.pointee.sa_family == sa_family_t(AF_INET), saLen >= 8 {
                            let sin = addrPointer.assumingMemoryBound(to: sockaddr_in.self)
                            destination = IPv4Address(raw: UInt32(bigEndian: sin.pointee.sin_addr.s_addr))
                        } else if bit == RTA_GATEWAY, sa.pointee.sa_family == sa_family_t(AF_LINK) {
                            let sdl = addrPointer.assumingMemoryBound(to: sockaddr_dl.self)
                            if sdl.pointee.sdl_alen == 6 {
                                let macBase = addrPointer.advanced(by: Int(MemoryLayout<UInt8>.size * 8 + Int(sdl.pointee.sdl_nlen)))
                                // sockaddr_dl: len, family, index(2), type, nlen, alen, slen, then sdl_data
                                let dataStart = UnsafeRawPointer(sdl).advanced(by: MemoryLayout<sockaddr_dl>.offset(of: \sockaddr_dl.sdl_data) ?? 8)
                                let macPtr = dataStart.advanced(by: Int(sdl.pointee.sdl_nlen))
                                let bytes = (0..<6).map { macPtr.load(fromByteOffset: $0, as: UInt8.self) }
                                hardware = MACAddress(bytes: bytes)
                                _ = macBase
                            }
                        }
                        addrPointer = addrPointer.advanced(by: aligned)
                    }
                    bit <<= 1
                }

                if let destination, let hardware, shouldKeep(ip: destination, mac: hardware) {
                    table[destination] = hardware
                }
            }
        }

        return table
    }

    private static func shouldKeep(ip: IPv4Address, mac: MACAddress) -> Bool {
        if ip.isMulticast || ip.isBroadcast || ip.isReserved { return false }
        if mac.isBroadcast || mac.isZero || mac.isMulticast { return false }
        return true
    }

    private static func roundup(_ value: Int) -> Int {
        let align = MemoryLayout<Int>.size
        return ((value + align - 1) & ~(align - 1))
    }
}
