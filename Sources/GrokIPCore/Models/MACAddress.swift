import Foundation

public struct MACAddress: Hashable, Sendable, CustomStringConvertible, Codable {
    public let raw: UInt64

    public init(raw: UInt64) {
        self.raw = raw & 0xFFFF_FFFF_FFFF
    }

    public init(bytes: [UInt8]) {
        precondition(bytes.count == 6)
        var value: UInt64 = 0
        for byte in bytes {
            value = (value << 8) | UInt64(byte)
        }
        self.init(raw: value)
    }

    public static func parse(_ string: String) -> MACAddress? {
        let hex = string.uppercased().filter(\.isHexDigit)
        guard hex.count == 12 else { return nil }
        guard let value = UInt64(hex, radix: 16) else { return nil }
        return MACAddress(raw: value)
    }

    public var bytes: [UInt8] {
        (0..<6).map { shift in
            UInt8(truncatingIfNeeded: raw >> (8 * (5 - shift)))
        }
    }

    public var canonical: String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    public var description: String { canonical }

    public var isMulticast: Bool { bytes[0] & 0x01 != 0 }
    public var isBroadcast: Bool { raw == 0xFFFF_FFFF_FFFF }
    public var isLocallyAdministered: Bool { bytes[0] & 0x02 != 0 }
    public var isZero: Bool { raw == 0 }

    public var hex: String {
        bytes.map { String(format: "%02X", $0) }.joined()
    }

    public func ouiPrefixes() -> [String] {
        let hex = self.hex
        return [
            String(hex.prefix(9)),
            String(hex.prefix(7)),
            String(hex.prefix(6))
        ]
    }
}
