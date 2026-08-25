import Foundation

@main
struct SmokeScan {
    static func main() async {
        let snapshot = InterfaceEnumerator.snapshot()
        print("interfaces:")
        for iface in snapshot.interfaces {
            print("  \(iface.menuLabel) mac=\(iface.mac?.canonical ?? "-")")
        }
        print("gateway:", snapshot.gatewayIP?.string ?? "-")
        guard let iface = snapshot.preferred else {
            print("no interface")
            exit(1)
        }

        let range = iface.cidr
        print("scanning", range.description, "hosts=\(range.hostCount)")

        let config = ScanConfig(
            range: range,
            interfaceName: iface.name,
            localIP: iface.ip,
            localMAC: iface.mac,
            gatewayIP: snapshot.gatewayIP
        )
        let engine = ScanEngine()
        let oui = OUILookup.bundled()
        var found: [Device] = []
        for await event in await engine.scan(config: config, oui: oui) {
            switch event {
            case .hostFound(let device), .hostUpdated(let device):
                if let index = found.firstIndex(where: { $0.ip == device.ip }) {
                    found[index] = device
                } else {
                    found.append(device)
                }
                print("  \(device.ip.string)  host=\(device.hostname ?? "-")  mac=\(device.mac?.canonical ?? "-")  vendor=\(device.vendor ?? "-")  login=\(device.primaryLogin?.url.absoluteString ?? "-")")
            case .finished(let count, let elapsed):
                print("done count=\(count) elapsed=\(String(format: "%.2f", elapsed))s unique=\(found.count)")
            case .failed(let message):
                print("failed:", message)
                exit(1)
            default:
                break
            }
        }
        if found.isEmpty {
            print("no devices found")
            exit(1)
        }
        if found.contains(where: { $0.isLocal && $0.mac != nil }) {
            print("local MAC present")
        }
    }
}
