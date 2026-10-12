import Darwin
import Foundation

public enum WakeOnLAN: Sendable {
    /// Six 0xFF bytes followed by the target MAC repeated sixteen times.
    public static func magicPacket(for mac: MACAddress) -> [UInt8] {
        var packet = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 {
            packet.append(contentsOf: mac.bytes)
        }
        return packet
    }

    /// Sends the magic packet to the subnet broadcast (when known) and 255.255.255.255
    /// on UDP 9 and 7. Returns true if at least one datagram left the socket.
    @discardableResult
    public static func send(to mac: MACAddress, subnetBroadcast: IPv4Address?) -> Bool {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(MemoryLayout.size(ofValue: on)))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout.size(ofValue: on)))

        var targets: [IPv4Address] = []
        if let subnetBroadcast { targets.append(subnetBroadcast) }
        targets.append(IPv4Address(raw: 0xFFFF_FFFF))

        let packet = magicPacket(for: mac)
        var sentAny = false
        for target in targets {
            for port: UInt16 in [9, 7] {
                var addr = sockaddr_in()
                addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = port.bigEndian
                addr.sin_addr = target.sinAddr
                let sent = packet.withUnsafeBytes { buffer in
                    withUnsafePointer(to: &addr) { pointer in
                        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                            sendto(fd, buffer.baseAddress, buffer.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                }
                if sent == packet.count { sentAny = true }
            }
        }
        return sentAny
    }
}
