public enum ICMPChecksum: Sendable {
    public static func compute(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var index = 0
        while index + 1 < bytes.count {
            let word = (UInt16(bytes[index]) << 8) | UInt16(bytes[index + 1])
            sum += UInt32(word)
            index += 2
        }
        if index < bytes.count {
            sum += UInt32(bytes[index]) << 8
        }
        while sum >> 16 != 0 {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }
        return ~UInt16(truncatingIfNeeded: sum)
    }
}
