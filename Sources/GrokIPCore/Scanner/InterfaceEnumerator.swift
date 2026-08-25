import Darwin
import Foundation
import SystemConfiguration

public enum InterfaceEnumerator: Sendable {
    private static let skippedPrefixes = [
        "lo", "awdl", "llw", "utun", "gif", "stf", "anpi", "ap", "ipsec", "p2p", "vmenet"
    ]

    public static func snapshot() -> InterfaceSnapshot {
        let interfaces = ipv4Interfaces()
        let gateway = defaultGateway()
        return InterfaceSnapshot(
            interfaces: interfaces,
            gatewayIP: gateway?.ip,
            gatewayInterface: gateway?.interfaceName
        )
    }

    public static func ipv4Interfaces() -> [NetworkInterfaceInfo] {
        let localized = localizedNames()
        let macs = macAddresses()
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(first) }

        var result: [NetworkInterfaceInfo] = []
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let iface = current {
            defer { current = iface.pointee.ifa_next }
            guard let addr = iface.pointee.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            let name = String(cString: iface.pointee.ifa_name)
            if shouldSkip(name) { continue }

            let flags = Int32(iface.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0 && (flags & IFF_RUNNING) != 0
            let sin = UnsafeRawPointer(addr).assumingMemoryBound(to: sockaddr_in.self).pointee
            let ip = IPv4Address(raw: UInt32(bigEndian: sin.sin_addr.s_addr))
            if ip.isLoopback { continue }

            var netmask = IPv4Address(raw: 0xFFFF_FF00)
            if let maskPtr = iface.pointee.ifa_netmask {
                let maskSin = UnsafeRawPointer(maskPtr).assumingMemoryBound(to: sockaddr_in.self).pointee
                netmask = IPv4Address(raw: UInt32(bigEndian: maskSin.sin_addr.s_addr))
            }
            let prefix = ScanRange.prefixLength(mask: netmask.raw) ?? 24

            result.append(
                NetworkInterfaceInfo(
                    name: name,
                    localizedName: localized[name] ?? name,
                    ip: ip,
                    netmask: netmask,
                    prefix: prefix,
                    mac: macs[name],
                    isUp: isUp
                )
            )
        }

        return result.sorted { lhs, rhs in
            if lhs.isUp != rhs.isUp { return lhs.isUp && !rhs.isUp }
            return lhs.name < rhs.name
        }
    }

    public static func defaultGateway() -> (ip: IPv4Address, interfaceName: String)? {
        let output = Command.run("/sbin/route", ["-n", "get", "default"])
        var gateway: IPv4Address?
        var iface: String?
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("gateway:") {
                let value = trimmed.dropFirst("gateway:".count).trimmingCharacters(in: .whitespaces)
                gateway = IPv4Address(value)
            } else if trimmed.hasPrefix("interface:") {
                iface = trimmed.dropFirst("interface:".count).trimmingCharacters(in: .whitespaces)
            }
        }
        if let gateway, let iface {
            return (gateway, iface)
        }
        return nil
    }

    private static func shouldSkip(_ name: String) -> Bool {
        skippedPrefixes.contains { name == $0 || name.hasPrefix($0) }
    }

    private static func localizedNames() -> [String: String] {
        var map: [String: String] = [:]
        guard let list = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return map }
        for iface in list {
            if let bsd = SCNetworkInterfaceGetBSDName(iface) as String?,
               let local = SCNetworkInterfaceGetLocalizedDisplayName(iface) as String? {
                map[bsd] = local
            }
        }
        return map
    }

    private static func macAddresses() -> [String: MACAddress] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [:] }
        defer { freeifaddrs(first) }
        var map: [String: MACAddress] = [:]
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let iface = current {
            defer { current = iface.pointee.ifa_next }
            guard let addr = iface.pointee.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_LINK) else { continue }
            let name = String(cString: iface.pointee.ifa_name)
            let sdl = UnsafeRawPointer(addr).assumingMemoryBound(to: sockaddr_dl.self)
            guard sdl.pointee.sdl_alen == 6 else { continue }
            let dataOffset = MemoryLayout<sockaddr_dl>.offset(of: \sockaddr_dl.sdl_data) ?? 8
            let macPtr = UnsafeRawPointer(sdl).advanced(by: dataOffset + Int(sdl.pointee.sdl_nlen))
            let bytes = (0..<6).map { macPtr.load(fromByteOffset: $0, as: UInt8.self) }
            if let mac = Optional(MACAddress(bytes: bytes)), !mac.isZero {
                map[name] = mac
            }
        }
        return map
    }
}
