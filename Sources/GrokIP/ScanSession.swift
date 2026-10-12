import AppKit
import Foundation
#if canImport(GrokIPCore)
import GrokIPCore
#endif
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class ScanSession {
    enum Phase: Equatable {
        case idle
        case scanning
        case complete
        case failed
    }

    var snapshot: InterfaceSnapshot
    var selectedInterfaceID: String?
    var rangeText: String = ""
    var filterText: String = ""
    var devices: [Device] = []
    var selection: String?
    var hoveredID: String?
    var phase: Phase = .idle
    var progressPhase: String = ""
    var completed: Int = 0
    var total: Int = 0
    var elapsed: TimeInterval = 0
    var errorMessage: String?
    var sortKey: SortKey = .ip
    var sortAscending: Bool = true
    /// MACs that showed up for the first time on the latest scan.
    var newMACs: Set<MACAddress> = []
    /// The scan found hosts but macOS handed back no MAC addresses at all,
    /// which is what a missing Local Network privilege looks like.
    var macsLikelyHidden = false

    let oui: OUILookup
    let permission: LocalNetworkPermission
    private let knownDevices: KnownDevices
    private let engine = ScanEngine()
    private var scanTask: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var startedAt: Date?
    /// True when the scanned range is this Mac's own subnet, the only case where
    /// every live host should come back with a MAC address.
    private var scanIsOnLink = false

    enum SortKey: String, CaseIterable {
        case ip = "IP"
        case hostname = "Hostname"
        case mac = "MAC"
        case vendor = "Vendor"
        case kind = "Kind"
    }

    init() {
        oui = OUILookup.bundled()
        permission = LocalNetworkPermission()
        knownDevices = KnownDevices()
        snapshot = InterfaceEnumerator.snapshot()
        selectedInterfaceID = snapshot.preferred?.id
        rangeText = snapshot.preferred?.cidr.description ?? ""
        permission.start(probeAddresses: Self.permissionProbes(snapshot))
    }

    /// Addresses to aim the Local Network alert trigger at: the gateway and a
    /// neighbor on the preferred subnet.
    private static func permissionProbes(_ snapshot: InterfaceSnapshot) -> [IPv4Address] {
        var probes: [IPv4Address] = []
        if let gateway = snapshot.gatewayIP { probes.append(gateway) }
        if let iface = snapshot.preferred {
            let neighbor = IPv4Address(raw: iface.ip.raw ^ 1)
            if iface.cidr.contains(neighbor), !probes.contains(neighbor) { probes.append(neighbor) }
        }
        return probes
    }

    var showsPermissionBanner: Bool {
        permission.status == .denied || macsLikelyHidden
    }

    func isNew(_ device: Device) -> Bool {
        guard let mac = device.mac else { return false }
        return newMACs.contains(mac)
    }

    func wake(_ device: Device) {
        guard let mac = device.mac else { return }
        WakeOnLAN.send(to: mac, subnetBroadcast: selectedInterface?.broadcast)
    }

    var selectedInterface: NetworkInterfaceInfo? {
        snapshot.interfaces.first { $0.id == selectedInterfaceID }
    }

    var selectedDevice: Device? {
        devices.first { $0.id == selection }
    }

    var isScanning: Bool { phase == .scanning }

    var liveIPs: Set<UInt32> {
        Set(devices.map(\.ip.raw))
    }

    var loginCount: Int {
        devices.filter { $0.primaryLogin != nil }.count
    }

    var filteredDevices: [Device] {
        let tokens = filterText
            .split(whereSeparator: \.isWhitespace)
            .map { $0.lowercased() }
        let filtered: [Device]
        if tokens.isEmpty {
            filtered = devices
        } else {
            filtered = devices.filter { device in
                let blob = [
                    device.ip.string,
                    device.hostname ?? "",
                    device.mac?.canonical ?? "",
                    device.vendor ?? "",
                    device.model ?? "",
                    device.kind.rawValue,
                    device.webTitle ?? "",
                    device.primaryLogin?.url.absoluteString ?? ""
                ].joined(separator: " ").lowercased()
                return tokens.allSatisfy { blob.contains($0) }
            }
        }
        return filtered.sorted { lhs, rhs in
            let ordered = compare(lhs, rhs)
            return sortAscending ? ordered : !ordered
        }
    }

    func reloadInterfaces() {
        snapshot = InterfaceEnumerator.snapshot()
        if selectedInterfaceID == nil || selectedInterface == nil {
            selectedInterfaceID = snapshot.preferred?.id
        }
        if let selectedInterface, rangeText.isEmpty {
            rangeText = selectedInterface.cidr.description
        }
    }

    func applyInterface(_ id: String?) {
        selectedInterfaceID = id
        if let selectedInterface {
            rangeText = selectedInterface.cidr.description
        }
    }

    func toggleSort(_ key: SortKey) {
        if sortKey == key {
            sortAscending.toggle()
        } else {
            sortKey = key
            sortAscending = true
        }
    }

    func scan() {
        reloadInterfaces()
        guard let range = ScanRange.parse(rangeText) else {
            phase = .failed
            errorMessage = "Could not parse that range. Try 192.168.1.0/24 or 192.168.1.1-254."
            return
        }
        stop()
        devices = []
        selection = nil
        errorMessage = nil
        newMACs = []
        macsLikelyHidden = false
        completed = 0
        total = range.hostCount
        elapsed = 0
        progressPhase = "Starting"
        phase = .scanning
        startedAt = Date()
        startTicker()

        let iface = selectedInterface
        scanIsOnLink = iface.map { range.contains($0.ip) } ?? false
        let config = ScanConfig(
            range: range,
            interfaceName: iface?.name,
            localIP: iface?.ip,
            localMAC: iface?.mac,
            gatewayIP: snapshot.gatewayIP
        )
        let oui = self.oui
        let permission = self.permission
        scanTask = Task { [engine] in
            if permission.status == .checking {
                // Give the Local Network alert a moment so the first scan is not wasted.
                self.progressPhase = "Waiting for Local Network access"
                await permission.settle(timeout: .seconds(3))
                if Task.isCancelled { return }
            }
            let stream = await engine.scan(config: config, oui: oui)
            for await event in stream {
                if Task.isCancelled { break }
                self.handle(event)
            }
        }
    }

    func stop() {
        scanTask?.cancel()
        scanTask = nil
        ticker?.cancel()
        ticker = nil
        if phase == .scanning {
            phase = devices.isEmpty ? .idle : .complete
            progressPhase = "Stopped"
        }
    }

    func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    func openLogin(_ device: Device) {
        guard let url = device.primaryLogin?.url else { return }
        NSWorkspace.shared.open(url)
    }

    func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "grokip-scan.csv"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let body = CSV.document(devices: filteredDevices)
        try? body.write(to: url, atomically: true, encoding: .utf8)
    }

    private func handle(_ event: ScanEvent) {
        switch event {
        case .started(let totalHosts, _):
            total = totalHosts
        case .progress(let phase, let completed, let total):
            progressPhase = phase
            self.completed = completed
            self.total = max(total, 1)
        case .hostFound(let device):
            if let index = devices.firstIndex(where: { $0.ip == device.ip }) {
                devices[index] = device
            } else {
                devices.append(device)
            }
        case .hostUpdated(let device):
            if let index = devices.firstIndex(where: { $0.ip == device.ip }) {
                devices[index] = device
            } else {
                devices.append(device)
            }
        case .finished(_, let elapsed):
            self.elapsed = elapsed
            let macs = devices.compactMap { $0.isLocal ? nil : $0.mac }
            newMACs = knownDevices.record(macs)
            let remote = devices.filter { !$0.isLocal }
            macsLikelyHidden = scanIsOnLink && !LocalNetworkPermission.isExempt && remote.count >= 2 && macs.isEmpty
            phase = .complete
            progressPhase = "Done"
            ticker?.cancel()
            ticker = nil
            scanTask = nil
        case .failed(let message):
            errorMessage = message
            phase = .failed
            ticker?.cancel()
            ticker = nil
            scanTask = nil
        }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, self.phase == .scanning, let startedAt = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(startedAt)
            }
        }
    }

    private func compare(_ lhs: Device, _ rhs: Device) -> Bool {
        switch sortKey {
        case .ip:
            return lhs.ip < rhs.ip
        case .hostname:
            return (lhs.hostname ?? lhs.displayName).localizedCaseInsensitiveCompare(rhs.hostname ?? rhs.displayName) == .orderedAscending
        case .mac:
            return (lhs.mac?.canonical ?? "") < (rhs.mac?.canonical ?? "")
        case .vendor:
            return (lhs.vendor ?? "") < (rhs.vendor ?? "")
        case .kind:
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
    }
}
