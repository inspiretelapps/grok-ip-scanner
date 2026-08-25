import Darwin
import Foundation

public enum ICMPSweep: Sendable {
    public static func sweep(hosts: [IPv4Address], timeout: TimeInterval) -> [IPv4Address: Double] {
        guard !hosts.isEmpty else { return [:] }
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { return [:] }
        defer { close(fd) }

        var rcvbuf: Int32 = 512 * 1024
        setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &rcvbuf, socklen_t(MemoryLayout.size(ofValue: rcvbuf)))
        let flags = fcntl(fd, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }

        let identifier = UInt16(truncatingIfNeeded: getpid())
        var sentAt: [IPv4Address: UInt64] = [:]
        sentAt.reserveCapacity(hosts.count)

        for (index, host) in hosts.enumerated() {
            let packet = echoPacket(identifier: identifier, sequence: UInt16(truncatingIfNeeded: index + 1))
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_addr = host.sinAddr
            _ = packet.withUnsafeBytes { buffer in
                withUnsafePointer(to: &addr) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        sendto(fd, buffer.baseAddress, buffer.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            sentAt[host] = DispatchTime.now().uptimeNanoseconds
        }

        var results: [IPv4Address: Double] = [:]
        let deadline = Date().addingTimeInterval(timeout)
        var recvBuf = [UInt8](repeating: 0, count: 512)

        while Date() < deadline {
            let remainingMs = max(Int32(deadline.timeIntervalSinceNow * 1000), 0)
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let pr = poll(&pfd, 1, remainingMs)
            if pr <= 0 { break }

            while true {
                var src = sockaddr_in()
                var srcLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                let n = withUnsafeMutablePointer(to: &src) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        recvfrom(fd, &recvBuf, recvBuf.count, 0, sa, &srcLen)
                    }
                }
                if n < 0 {
                    if errno == EAGAIN || errno == EWOULDBLOCK { break }
                    break
                }
                guard n >= 8 else { continue }

                var icmpOffset = 0
                if recvBuf[0] == 0x45 {
                    icmpOffset = Int((recvBuf[0] & 0x0F) * 4)
                }
                guard icmpOffset + 8 <= Int(n) else { continue }
                let type = recvBuf[icmpOffset]
                guard type == 0 else { continue }

                let ip = IPv4Address(raw: UInt32(bigEndian: src.sin_addr.s_addr))
                guard let start = sentAt[ip] else { continue }
                let elapsedNs = DispatchTime.now().uptimeNanoseconds &- start
                let ms = Double(elapsedNs) / 1_000_000
                if let existing = results[ip] {
                    results[ip] = min(existing, ms)
                } else {
                    results[ip] = ms
                }
            }
        }

        return results
    }

    static func echoPacket(identifier: UInt16, sequence: UInt16) -> [UInt8] {
        var packet: [UInt8] = [
            8, 0,
            0, 0,
            UInt8(truncatingIfNeeded: identifier >> 8),
            UInt8(truncatingIfNeeded: identifier),
            UInt8(truncatingIfNeeded: sequence >> 8),
            UInt8(truncatingIfNeeded: sequence)
        ]
        packet.append(contentsOf: [0x47, 0x72, 0x6F, 0x6B, 0x49, 0x50, 0x00, 0x00])
        let sum = ICMPChecksum.compute(packet)
        packet[2] = UInt8(truncatingIfNeeded: sum >> 8)
        packet[3] = UInt8(truncatingIfNeeded: sum)
        return packet
    }
}
