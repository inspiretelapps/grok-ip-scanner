import Darwin
import Foundation

public struct IPv4Address: Hashable, Sendable, Comparable, CustomStringConvertible, Codable {
    public let raw: UInt32

    public init(raw: UInt32) {
        self.raw = raw
    }

    public init(octets a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) {
        raw = (UInt32(a) << 24) | (UInt32(b) << 16) | (UInt32(c) << 8) | UInt32(d)
    }

    public init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(4)
        for part in parts {
            guard let value = UInt8(part) else { return nil }
            bytes.append(value)
        }
        self.init(octets: bytes[0], bytes[1], bytes[2], bytes[3])
    }

    public var octets: (UInt8, UInt8, UInt8, UInt8) {
        (
            UInt8(truncatingIfNeeded: raw >> 24),
            UInt8(truncatingIfNeeded: raw >> 16),
            UInt8(truncatingIfNeeded: raw >> 8),
            UInt8(truncatingIfNeeded: raw)
        )
    }

    public var string: String {
        let o = octets
        return "\(o.0).\(o.1).\(o.2).\(o.3)"
    }

    public var description: String { string }

    public var sinAddr: in_addr {
        in_addr(s_addr: raw.bigEndian)
    }

    public var isMulticast: Bool { (raw >> 28) == 0xE }
    public var isBroadcast: Bool { raw == 0xFFFF_FFFF }
    public var isLoopback: Bool { (raw >> 24) == 127 }
    public var isLinkLocal: Bool { (raw >> 16) == 0xA9FE }
    public var isReserved: Bool { (raw >> 24) == 0 }

    public static func < (lhs: IPv4Address, rhs: IPv4Address) -> Bool {
        lhs.raw < rhs.raw
    }
}

public struct ScanRange: Sendable, Hashable, CustomStringConvertible {
    public var start: IPv4Address
    public var end: IPv4Address
    public var prefix: Int?

    public init(start: IPv4Address, end: IPv4Address, prefix: Int? = nil) {
        self.start = start
        self.end = end
        self.prefix = prefix
    }

    public var hostCount: Int {
        guard start.raw <= end.raw else { return 0 }
        return Int(end.raw - start.raw) + 1
    }

    public var hosts: [IPv4Address] {
        guard start.raw <= end.raw else { return [] }
        var result: [IPv4Address] = []
        result.reserveCapacity(hostCount)
        var value = start.raw
        while true {
            result.append(IPv4Address(raw: value))
            if value == end.raw || value == UInt32.max { break }
            value += 1
        }
        return result
    }

    public var description: String {
        if let prefix {
            let mask = Self.mask(prefix: prefix)
            let network = IPv4Address(raw: start.raw & mask)
            return "\(network.string)/\(prefix)"
        }
        if start == end { return start.string }
        return "\(start.string)-\(end.string)"
    }

    public var isOctetGrid: Bool {
        start.raw >> 8 == end.raw >> 8 && (end.raw - start.raw) < 256
    }

    public func contains(_ ip: IPv4Address) -> Bool {
        ip.raw >= start.raw && ip.raw <= end.raw
    }

    public static func mask(prefix: Int) -> UInt32 {
        guard prefix > 0 else { return 0 }
        if prefix >= 32 { return ~UInt32(0) }
        return ~UInt32(0) << (32 - prefix)
    }

    public static func prefixLength(mask: UInt32) -> Int? {
        let prefix = mask.nonzeroBitCount
        let expected = Self.mask(prefix: prefix)
        return expected == mask ? prefix : nil
    }

    public static func cidr(address: IPv4Address, prefix: Int) -> ScanRange? {
        guard (0...32).contains(prefix) else { return nil }
        let mask = Self.mask(prefix: prefix)
        let network = address.raw & mask
        let broadcast = network | ~mask
        if prefix >= 31 {
            return ScanRange(
                start: IPv4Address(raw: network),
                end: IPv4Address(raw: broadcast),
                prefix: prefix
            )
        }
        let first = network + 1
        let last = broadcast &- 1
        guard first <= last else { return nil }
        return ScanRange(
            start: IPv4Address(raw: first),
            end: IPv4Address(raw: last),
            prefix: prefix
        )
    }

    public static func parse(_ string: String) -> ScanRange? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let slash = trimmed.firstIndex(of: "/") {
            let ipPart = String(trimmed[..<slash])
            let prefixPart = String(trimmed[trimmed.index(after: slash)...])
            guard let address = IPv4Address(ipPart), let prefix = Int(prefixPart) else { return nil }
            return cidr(address: address, prefix: prefix)
        }

        if let dash = trimmed.firstIndex(of: "-") {
            let left = String(trimmed[..<dash]).trimmingCharacters(in: .whitespaces)
            let right = String(trimmed[trimmed.index(after: dash)...]).trimmingCharacters(in: .whitespaces)
            guard let start = IPv4Address(left) else { return nil }
            if let end = IPv4Address(right) {
                guard start.raw <= end.raw else { return nil }
                return ScanRange(start: start, end: end, prefix: nil)
            }
            if let lastOctet = UInt8(right) {
                let o = start.octets
                let end = IPv4Address(octets: o.0, o.1, o.2, lastOctet)
                guard start.raw <= end.raw else { return nil }
                return ScanRange(start: start, end: end, prefix: nil)
            }
            return nil
        }

        guard let ip = IPv4Address(trimmed) else { return nil }
        return ScanRange(start: ip, end: ip, prefix: 32)
    }
}
