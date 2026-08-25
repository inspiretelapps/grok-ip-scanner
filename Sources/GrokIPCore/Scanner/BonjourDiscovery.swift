import Foundation

public struct BonjourHit: Sendable, Hashable {
    public var name: String
    public var type: String
    public var hostname: String?
    public var ip: IPv4Address?
    public var port: Int
    public var txt: [String: String]

    public init(
        name: String,
        type: String,
        hostname: String?,
        ip: IPv4Address?,
        port: Int,
        txt: [String: String]
    ) {
        self.name = name
        self.type = type
        self.hostname = hostname
        self.ip = ip
        self.port = port
        self.txt = txt
    }

    public var serviceName: String {
        let trimmed = type.trimmingCharacters(in: CharacterSet(charactersIn: "._"))
        if trimmed.hasPrefix("ipp") { return "IPP" }
        if trimmed.hasPrefix("http") { return "HTTP" }
        if trimmed.hasPrefix("https") { return "HTTPS" }
        if trimmed.hasPrefix("ssh") { return "SSH" }
        if trimmed.hasPrefix("smb") { return "SMB" }
        if trimmed.hasPrefix("printer") || trimmed.hasPrefix("pdl") { return "Printer" }
        if trimmed.hasPrefix("airplay") || trimmed.hasPrefix("raop") { return "AirPlay" }
        if trimmed.hasPrefix("sip") { return "SIP" }
        if trimmed.hasPrefix("rfb") { return "VNC" }
        if trimmed.hasPrefix("rdp") { return "RDP" }
        return trimmed.split(separator: ".").first.map(String.init)?.uppercased() ?? "Bonjour"
    }

    public var webURL: URL? {
        let isHTTP = type.contains("http") || type.contains("ipp")
        guard isHTTP, let ip else { return nil }
        let tls = type.contains("https") || type.contains("ipps")
        var path = txt["path"] ?? "/"
        if !path.hasPrefix("/") { path = "/" + path }
        return PortCatalog.url(ip: ip, port: UInt16(port), tls: tls).flatMap { base in
            URL(string: path, relativeTo: base)?.absoluteURL
        }
    }
}

public final class BonjourDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate, @unchecked Sendable {
    public static let serviceTypes = [
        "_http._tcp.",
        "_https._tcp.",
        "_ipp._tcp.",
        "_ipps._tcp.",
        "_printer._tcp.",
        "_pdl-datastream._tcp.",
        "_scanner._tcp.",
        "_uscan._tcp.",
        "_airplay._tcp.",
        "_raop._tcp.",
        "_ssh._tcp.",
        "_sftp-ssh._tcp.",
        "_smb._tcp.",
        "_afpovertcp._tcp.",
        "_device-info._tcp.",
        "_companion-link._tcp.",
        "_googlecast._tcp.",
        "_workstation._tcp.",
        "_rfb._tcp.",
        "_airport._tcp.",
        "_hap._tcp.",
        "_sip._udp.",
        "_sip._tcp.",
        "_rdp._tcp.",
        "_adisk._tcp."
    ]

    private var browsers: [NetServiceBrowser] = []
    private var resolving: [String: NetService] = [:]
    private var handler: (@Sendable (BonjourHit) -> Void)?
    private let lock = NSLock()

    public func start(handler: @escaping @Sendable (BonjourHit) -> Void) {
        lock.lock()
        self.handler = handler
        lock.unlock()
        DispatchQueue.main.async {
            self.stopBrowsers()
            for type in Self.serviceTypes {
                let browser = NetServiceBrowser()
                browser.delegate = self
                browser.searchForServices(ofType: type, inDomain: "local.")
                self.browsers.append(browser)
            }
        }
    }

    public func stop() {
        let teardown = {
            self.stopBrowsers()
        }
        if Thread.isMainThread {
            teardown()
        } else {
            DispatchQueue.main.sync(execute: teardown)
        }
        lock.lock()
        handler = nil
        lock.unlock()
    }

    private func stopBrowsers() {
        browsers.forEach { $0.stop() }
        browsers.removeAll()
        resolving.values.forEach { $0.stop() }
        resolving.removeAll()
    }

    public func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        let key = "\(service.name).\(service.type)\(service.domain)"
        service.delegate = self
        resolving[key] = service
        service.resolve(withTimeout: 2.0)
    }

    public func netServiceDidResolveAddress(_ sender: NetService) {
        let addresses = sender.addresses ?? []
        var ipv4: IPv4Address?
        for data in addresses {
            ipv4 = Self.ipv4(from: data)
            if ipv4 != nil { break }
        }
        var txt: [String: String] = [:]
        if let record = sender.txtRecordData() {
            let parsed = NetService.dictionary(fromTXTRecord: record)
            for (key, value) in parsed {
                txt[key] = String(data: value, encoding: .utf8) ?? ""
            }
        }
        let hit = BonjourHit(
            name: sender.name,
            type: sender.type,
            hostname: HostnameResolver.clean(sender.hostName),
            ip: ipv4,
            port: sender.port,
            txt: txt
        )
        lock.lock()
        let handler = self.handler
        lock.unlock()
        handler?(hit)
    }

    public func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        let key = "\(sender.name).\(sender.type)\(sender.domain)"
        resolving.removeValue(forKey: key)
    }

    private static func ipv4(from data: Data) -> IPv4Address? {
        data.withUnsafeBytes { raw in
            guard raw.count >= MemoryLayout<sockaddr>.size else { return nil }
            let sa = raw.load(as: sockaddr.self)
            guard sa.sa_family == sa_family_t(AF_INET) else { return nil }
            let sin = raw.load(as: sockaddr_in.self)
            return IPv4Address(raw: UInt32(bigEndian: sin.sin_addr.s_addr))
        }
    }
}
