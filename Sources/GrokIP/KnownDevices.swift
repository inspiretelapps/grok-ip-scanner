import Foundation
#if canImport(GrokIPCore)
import GrokIPCore
#endif

/// Remembers every MAC address seen on earlier scans so new arrivals on the
/// network can be flagged (the "who just joined my Wi-Fi?" feature of Fing and co).
@MainActor
final class KnownDevices {
    private var firstSeen: [String: Date] = [:]
    private let url: URL?

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        url = base?
            .appendingPathComponent("Grok IP Scanner", isDirectory: true)
            .appendingPathComponent("known-devices.json")
        if let url,
           let data = try? Data(contentsOf: url),
           let stored = try? JSONDecoder().decode([String: Date].self, from: data) {
            firstSeen = stored
        }
    }

    /// Records the MACs from a finished scan and returns the ones never seen before.
    /// The very first scan establishes the baseline, so it reports nothing as new.
    func record(_ macs: [MACAddress]) -> Set<MACAddress> {
        let isBaseline = firstSeen.isEmpty
        var fresh = Set<MACAddress>()
        let now = Date()
        for mac in macs where firstSeen[mac.canonical] == nil {
            firstSeen[mac.canonical] = now
            fresh.insert(mac)
        }
        if !fresh.isEmpty { save() }
        return isBaseline ? [] : fresh
    }

    private func save() {
        guard let url else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(firstSeen) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
