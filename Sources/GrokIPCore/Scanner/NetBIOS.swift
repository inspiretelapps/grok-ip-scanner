import Darwin
import Foundation

public enum NetBIOS: Sendable {
    public static func query(ip: IPv4Address, timeout: TimeInterval = 0.45) -> String? {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        let flags = fcntl(fd, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }

        var packet = nodeStatusQuery()
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(137).bigEndian
        addr.sin_addr = ip.sinAddr

        let sent = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                sendto(fd, &packet, packet.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard sent > 0 else { return nil }

        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let pr = poll(&pfd, 1, Int32(timeout * 1000))
        guard pr > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: 1024)
        let n = recv(fd, &buffer, buffer.count, 0)
        guard n > 56 else { return nil }
        return parseNodeStatus(buffer, length: Int(n))
    }

    static func encodeName(_ name: String) -> [UInt8] {
        var padded = Array(name.utf8.prefix(15))
        while padded.count < 16 { padded.append(0x20) }
        padded[15] = 0x00
        var encoded: [UInt8] = [0x20]
        for byte in padded {
            encoded.append(((byte >> 4) & 0x0F) + 0x41)
            encoded.append((byte & 0x0F) + 0x41)
        }
        encoded.append(0x00)
        return encoded
    }

    static func nodeStatusQuery() -> [UInt8] {
        var packet: [UInt8] = [
            0x12, 0x34,
            0x00, 0x00,
            0x00, 0x01,
            0x00, 0x00,
            0x00, 0x00,
            0x00, 0x00
        ]
        packet.append(contentsOf: encodeName("*"))
        packet.append(contentsOf: [0x00, 0x21, 0x00, 0x01])
        return packet
    }

    static func parseNodeStatus(_ buffer: [UInt8], length: Int) -> String? {
        guard length > 13 else { return nil }
        var offset = 12
        guard offset < length else { return nil }
        let nameLen = Int(buffer[offset])
        offset += 1 + nameLen
        if offset < length, buffer[offset] == 0 { offset += 1 }
        offset += 4 // type + class
        offset += 4 // ttl
        guard offset + 2 <= length else { return nil }
        let rdLength = (Int(buffer[offset]) << 8) | Int(buffer[offset + 1])
        offset += 2
        guard offset + rdLength <= length, offset < length else { return nil }
        let nameCount = Int(buffer[offset])
        offset += 1
        var firstName: String?
        for _ in 0..<nameCount {
            guard offset + 18 <= length else { break }
            let nameBytes = buffer[offset..<(offset + 15)]
            let flags = buffer[offset + 15]
            offset += 18
            let name = String(bytes: nameBytes, encoding: .ascii)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
            guard let name, !name.isEmpty, name != "*" else { continue }
            let isGroup = flags & 0x80 != 0
            if !isGroup {
                return name
            }
            if firstName == nil { firstName = name }
        }
        return firstName
    }
}
