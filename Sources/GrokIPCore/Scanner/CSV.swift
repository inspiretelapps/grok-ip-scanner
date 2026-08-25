public enum CSV: Sendable {
    public static func escape(_ fields: [String]) -> String {
        fields.map { field in
            if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
                let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\""
            }
            return field
        }.joined(separator: ",")
    }

    public static func document(devices: [Device]) -> String {
        var lines = [escape(Device.csvHeader())]
        for device in devices.sorted(by: { $0.ip < $1.ip }) {
            lines.append(escape(device.csvFields()))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
