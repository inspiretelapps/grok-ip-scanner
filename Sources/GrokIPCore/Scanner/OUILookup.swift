import Foundation

public final class OUILookup: Sendable {
    private let vendors: [String: String]

    public init(contents: String) {
        var map: [String: String] = [:]
        map.reserveCapacity(40_000)
        contents.split(separator: "\n", omittingEmptySubsequences: true).forEach { line in
            if line.first == "#" { return }
            guard let space = line.firstIndex(of: " ") else { return }
            let prefix = String(line[..<space]).uppercased()
            let vendor = line[line.index(after: space)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prefix.isEmpty, !vendor.isEmpty else { return }
            map[prefix] = vendor
        }
        self.vendors = map
    }

    public static func bundled() -> OUILookup {
        if let url = ResourceLocator.url(name: "nmap-mac-prefixes"),
           let contents = try? String(contentsOf: url, encoding: .utf8) {
            return OUILookup(contents: contents)
        }
        return OUILookup(contents: "")
    }

    public var isEmpty: Bool { vendors.isEmpty }

    public func vendor(for mac: MACAddress) -> String? {
        for prefix in mac.ouiPrefixes() {
            if let vendor = vendors[prefix] {
                return vendor
            }
        }
        if mac.isLocallyAdministered {
            return "Randomized MAC"
        }
        return nil
    }
}
