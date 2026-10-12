import Foundation

public enum DeviceKind: String, Sendable, Hashable, CaseIterable, Codable {
    case thisMac = "This Mac"
    case gateway = "Gateway"
    case printer = "Printer"
    case ipPhone = "IP phone"
    case computer = "Computer"
    case apple = "Apple device"
    case camera = "Camera"
    case nas = "NAS"
    case networkGear = "Network"
    case unknown = "Device"

    public var symbolName: String {
        switch self {
        case .thisMac: "laptopcomputer"
        case .gateway: "arrow.trianglehead.branch"
        case .printer: "printer.fill"
        case .ipPhone: "phone.connection.fill"
        case .computer: "desktopcomputer"
        case .apple: "apple.logo"
        case .camera: "web.camera.fill"
        case .nas: "externaldrive.fill.badge.wifi"
        case .networkGear: "switch.2"
        case .unknown: "questionmark.circle"
        }
    }
}

public enum DiscoverySource: String, Sendable, Hashable, Codable {
    case icmp
    case arp
    case tcp
    case bonjour
    case local
    case netbios
    case ssdp
}

public struct NetworkService: Sendable, Hashable, Identifiable, Codable {
    public var name: String
    public var port: UInt16
    public var url: URL?

    public var id: String { "\(port)/\(name)" }

    public init(name: String, port: UInt16, url: URL? = nil) {
        self.name = name
        self.port = port
        self.url = url
    }
}

public struct WebProbeResult: Sendable, Hashable, Codable {
    public var url: URL
    public var statusCode: Int
    public var title: String?
    public var server: String?
    public var isLogin: Bool
    public var isTLS: Bool

    public init(
        url: URL,
        statusCode: Int,
        title: String? = nil,
        server: String? = nil,
        isLogin: Bool,
        isTLS: Bool
    ) {
        self.url = url
        self.statusCode = statusCode
        self.title = title
        self.server = server
        self.isLogin = isLogin
        self.isTLS = isTLS
    }
}

public struct Device: Identifiable, Sendable, Hashable, Codable {
    public var ip: IPv4Address
    public var mac: MACAddress?
    public var vendor: String?
    public var hostname: String?
    public var model: String?
    public var kind: DeviceKind
    public var isLocal: Bool
    public var isGateway: Bool
    public var rttMilliseconds: Double?
    public var services: [NetworkService]
    public var webPages: [WebProbeResult]
    public var webTitle: String?
    public var sources: Set<DiscoverySource>
    public var interfaceName: String?

    public var id: String { ip.string }

    public init(
        ip: IPv4Address,
        mac: MACAddress? = nil,
        vendor: String? = nil,
        hostname: String? = nil,
        model: String? = nil,
        kind: DeviceKind = .unknown,
        isLocal: Bool = false,
        isGateway: Bool = false,
        rttMilliseconds: Double? = nil,
        services: [NetworkService] = [],
        webPages: [WebProbeResult] = [],
        webTitle: String? = nil,
        sources: Set<DiscoverySource> = [],
        interfaceName: String? = nil
    ) {
        self.ip = ip
        self.mac = mac
        self.vendor = vendor
        self.hostname = hostname
        self.model = model
        self.kind = kind
        self.isLocal = isLocal
        self.isGateway = isGateway
        self.rttMilliseconds = rttMilliseconds
        self.services = services
        self.webPages = webPages
        self.webTitle = webTitle
        self.sources = sources
        self.interfaceName = interfaceName
    }

    public var displayName: String {
        if let hostname, !hostname.isEmpty { return hostname }
        if let webTitle, !webTitle.isEmpty { return webTitle }
        if isLocal { return "This Mac" }
        if isGateway { return "Gateway" }
        if let vendor, !vendor.isEmpty { return vendor }
        return ip.string
    }

    public var loginPages: [WebProbeResult] {
        let logins = webPages.filter(\.isLogin)
        return logins.isEmpty ? webPages : logins
    }

    public var primaryLogin: WebProbeResult? {
        if let login = webPages.first(where: \.isLogin) { return login }
        let preferredPorts: [UInt16] = [80, 443, 8080, 8443, 631]
        for port in preferredPorts {
            if let page = webPages.first(where: { $0.url.port == Int(port) || (port == 80 && $0.url.port == nil && $0.url.scheme == "http") || (port == 443 && $0.url.port == nil && $0.url.scheme == "https") }) {
                return page
            }
        }
        return webPages.first
    }

    public var loginLabel: String {
        guard let page = primaryLogin else { return "" }
        return page.isLogin ? "Log in" : "Open"
    }

    public mutating func merge(_ other: Device) {
        guard ip == other.ip else { return }
        if mac == nil { mac = other.mac }
        vendor = Self.preferredText(vendor, other.vendor)
        hostname = Self.preferredHostname(hostname, other.hostname)
        model = Self.preferredText(model, other.model)
        isLocal = isLocal || other.isLocal
        isGateway = isGateway || other.isGateway
        if rttMilliseconds == nil { rttMilliseconds = other.rttMilliseconds }
        else if let otherRTT = other.rttMilliseconds, let current = rttMilliseconds {
            rttMilliseconds = min(current, otherRTT)
        }
        sources.formUnion(other.sources)
        if interfaceName == nil { interfaceName = other.interfaceName }

        var servicesByPort: [UInt16: NetworkService] = [:]
        for service in services + other.services {
            if let existing = servicesByPort[service.port], existing.url != nil, service.url == nil {
                continue
            }
            servicesByPort[service.port] = service
        }
        services = servicesByPort.values.sorted { $0.port < $1.port }

        var pagesByURL: [String: WebProbeResult] = [:]
        for page in webPages + other.webPages {
            pagesByURL[page.url.absoluteString] = page
        }
        webPages = pagesByURL.values.sorted { lhs, rhs in
            if lhs.isLogin != rhs.isLogin { return lhs.isLogin && !rhs.isLogin }
            return lhs.url.absoluteString < rhs.url.absoluteString
        }
        webTitle = Self.preferredText(webTitle, other.webTitle)
        if webTitle == nil {
            webTitle = webPages.first(where: { $0.title != nil })?.title
        }
        kind = DeviceClassifier.classify(self)
    }

    public static func csvHeader() -> [String] {
        ["IP", "Hostname", "MAC", "Vendor", "Model", "Kind", "Login URL", "Title", "Services", "RTT ms"]
    }

    public func csvFields() -> [String] {
        [
            ip.string,
            hostname ?? "",
            mac?.canonical ?? "",
            vendor ?? "",
            model ?? "",
            kind.rawValue,
            primaryLogin?.url.absoluteString ?? "",
            webTitle ?? "",
            services.map { "\($0.name):\($0.port)" }.joined(separator: " "),
            rttMilliseconds.map { String(format: "%.1f", $0) } ?? ""
        ]
    }

    private static func preferredText(_ a: String?, _ b: String?) -> String? {
        if let a, !a.isEmpty { return a }
        if let b, !b.isEmpty { return b }
        return a ?? b
    }

    private static func preferredHostname(_ current: String?, _ incoming: String?) -> String? {
        let cleanedCurrent = Self.cleanHostname(current)
        let cleanedIncoming = Self.cleanHostname(incoming)
        if let incoming = cleanedIncoming, incoming.lowercased().hasSuffix(".local") {
            return incoming
        }
        if cleanedCurrent == nil { return cleanedIncoming }
        return cleanedCurrent
    }

    private static func cleanHostname(_ value: String?) -> String? {
        guard var value, !value.isEmpty else { return nil }
        if value.hasSuffix(".") { value.removeLast() }
        if value.hasSuffix(".in-addr.arpa") { return nil }
        if IPv4Address(value) != nil { return nil }
        return value
    }
}
