import Foundation

public enum PortCatalog: Sendable {
    public static let servicePorts: [UInt16] = [
        22, 23, 80, 139, 443, 445, 515, 554, 631, 3389, 5060, 8000, 8080, 8443, 9100, 62078
    ]

    public static let webCandidates: [(port: UInt16, tls: Bool)] = [
        (80, false),
        (443, true),
        (631, false),
        (8000, false),
        (8080, false),
        (8443, true),
        (8888, false),
        (10443, true)
    ]

    public static func serviceName(for port: UInt16, tlsHint: Bool = false) -> String {
        switch port {
        case 22: "SSH"
        case 23: "Telnet"
        case 80: "HTTP"
        case 139: "NetBIOS"
        case 443: "HTTPS"
        case 445: "SMB"
        case 515: "LPD"
        case 554: "RTSP"
        case 631: "IPP"
        case 3389: "RDP"
        case 5060: "SIP"
        case 8000, 8080, 8888: "HTTP"
        case 8443, 10443: "HTTPS"
        case 9100: "JetDirect"
        case 62078: "Apple"
        default: tlsHint ? "HTTPS" : "TCP"
        }
    }

    public static func url(ip: IPv4Address, port: UInt16, tls: Bool) -> URL? {
        let scheme = tls ? "https" : "http"
        if (tls && port == 443) || (!tls && port == 80) {
            return URL(string: "\(scheme)://\(ip.string)/")
        }
        return URL(string: "\(scheme)://\(ip.string):\(port)/")
    }
}
