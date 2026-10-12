import AppKit
import Darwin
import Foundation
#if canImport(GrokIPCore)
import GrokIPCore
#endif
import Network
import Observation

/// Tracks macOS Local Network privacy (macOS 15+) for this app.
///
/// Without the privilege macOS drops our unicast/multicast traffic and hides the
/// kernel's ARP (neighbor) table, so a scan finds IPs via Bonjour at best and never
/// sees MAC addresses or vendors. Root processes and tools launched from Terminal
/// are exempt, which is why `sudo` appeared to fix it.
///
/// There is no API to query the state (FB8711182). Following Apple's TN3179 we
/// trigger the alert by connecting a UDP socket to a LAN address, then watch a
/// Bonjour browse: it waits with `kDNSServiceErr_PolicyDenied` while access is
/// denied (or the alert is still up) and becomes ready once it is allowed.
@MainActor
@Observable
final class LocalNetworkPermission {
    enum Status: Equatable {
        case checking
        case granted
        case denied
        case notRequired
    }

    private(set) var status: Status = .checking

    /// Running as root or on macOS 14: nothing to grant.
    static var isExempt: Bool {
        if geteuid() == 0 { return true }
        if #available(macOS 15, *) { return false }
        return true
    }

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")!

    nonisolated private static let policyDenied: Int32 = -65570 // kDNSServiceErr_PolicyDenied

    private var browser: NWBrowser?
    private var activationObserver: NSObjectProtocol?

    func start(probeAddresses: [IPv4Address]) {
        if Self.isExempt {
            status = .notRequired
            return
        }
        Self.triggerAlert(addresses: probeAddresses)
        restartBrowser()
        if activationObserver == nil {
            // Re-check when the user comes back from System Settings.
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.status != .granted, self.status != .notRequired else { return }
                    self.restartBrowser()
                }
            }
        }
    }

    /// Waits (up to `timeout`) for the browse to settle, so a scan started right
    /// after launch does not race the alert.
    func settle(timeout: Duration) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while status == .checking, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    func recheck() {
        guard status != .notRequired else { return }
        status = .checking
        restartBrowser()
    }

    func openSettings() {
        NSWorkspace.shared.open(Self.settingsURL)
    }

    private func restartBrowser() {
        browser?.cancel()
        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjour(type: "_http._tcp", domain: "local."), using: parameters)
        browser.stateUpdateHandler = { [weak self] state in
            let next: Status?
            switch state {
            case .ready:
                next = .granted
            case .waiting(let error):
                if case .dns(let code) = error, Int32(code) == LocalNetworkPermission.policyDenied {
                    next = .denied
                } else {
                    next = nil
                }
            case .failed(let error):
                if case .dns(let code) = error, Int32(code) == LocalNetworkPermission.policyDenied {
                    next = .denied
                } else {
                    next = nil
                }
            default:
                next = nil
            }
            guard let next else { return }
            Task { @MainActor [weak self] in
                self?.status = next
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard !results.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.status = .granted
            }
        }
        self.browser = browser
        browser.start(queue: .main)
    }

    /// TN3179: connecting a UDP socket to a local address brings up the alert
    /// without sending any traffic.
    private static func triggerAlert(addresses: [IPv4Address]) {
        for address in addresses {
            let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard fd >= 0 else { continue }
            defer { close(fd) }
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = UInt16(9).bigEndian
            addr.sin_addr = address.sinAddr
            _ = withUnsafePointer(to: &addr) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    Darwin.connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }
}
