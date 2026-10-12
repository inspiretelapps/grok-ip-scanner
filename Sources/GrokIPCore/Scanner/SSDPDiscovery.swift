import Darwin
import Foundation

/// One reply to an SSDP M-SEARCH (UPnP discovery). TVs, routers, NAS boxes,
/// speakers, printers and media players answer these even when they ignore ping.
public struct SSDPResponse: Sendable, Hashable {
    public var ip: IPv4Address
    public var location: URL?
    public var server: String?
    public var searchTarget: String?
    public var usn: String?

    public init(ip: IPv4Address, location: URL?, server: String?, searchTarget: String?, usn: String?) {
        self.ip = ip
        self.location = location
        self.server = server
        self.searchTarget = searchTarget
        self.usn = usn
    }

    public static func parse(_ text: String, from ip: IPv4Address) -> SSDPResponse? {
        let lines = text.split(whereSeparator: \.isNewline)
        guard let status = lines.first?.uppercased(),
              status.hasPrefix("HTTP/1.1 200") || status.hasPrefix("NOTIFY") else {
            return nil
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if headers[key] == nil { headers[key] = value }
        }
        return SSDPResponse(
            ip: ip,
            location: headers["location"].flatMap { URL(string: $0) },
            server: headers["server"],
            searchTarget: headers["st"] ?? headers["nt"],
            usn: headers["usn"]
        )
    }
}

/// The interesting bits of a UPnP device description (the XML behind LOCATION).
public struct UPnPDescription: Sendable, Hashable {
    public var friendlyName: String?
    public var manufacturer: String?
    public var modelName: String?
    public var modelNumber: String?
    public var presentationURL: URL?

    public init(
        friendlyName: String? = nil,
        manufacturer: String? = nil,
        modelName: String? = nil,
        modelNumber: String? = nil,
        presentationURL: URL? = nil
    ) {
        self.friendlyName = friendlyName
        self.manufacturer = manufacturer
        self.modelName = modelName
        self.modelNumber = modelNumber
        self.presentationURL = presentationURL
    }

    /// "Samsung UE55TU7100" style label built from manufacturer, model name and number.
    public var model: String? {
        var parts: [String] = []
        if let manufacturer { parts.append(manufacturer) }
        if let modelName {
            if let manufacturer, modelName.lowercased().hasPrefix(manufacturer.lowercased()) {
                parts = [modelName]
            } else {
                parts.append(modelName)
            }
        }
        if let modelNumber, !parts.joined(separator: " ").lowercased().contains(modelNumber.lowercased()) {
            parts.append(modelNumber)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Parses the root device of a UPnP description document. `base` resolves a
    /// relative `presentationURL` (UPnP allows both forms).
    public static func parse(_ data: Data, base: URL?) -> UPnPDescription? {
        let delegate = DescriptionParser()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        _ = parser.parse()

        let base = delegate.urlBase.flatMap { URL(string: $0) } ?? base
        var description = UPnPDescription(
            friendlyName: delegate.fields["friendlyName"],
            manufacturer: delegate.fields["manufacturer"],
            modelName: delegate.fields["modelName"],
            modelNumber: delegate.fields["modelNumber"]
        )
        if let raw = delegate.fields["presentationURL"] {
            description.presentationURL = URL(string: raw, relativeTo: base)?.absoluteURL
        }
        if description.friendlyName == nil, description.manufacturer == nil, description.modelName == nil {
            return nil
        }
        return description
    }
}

private final class DescriptionParser: NSObject, XMLParserDelegate {
    private static let wanted: Set<String> = [
        "friendlyName", "manufacturer", "modelName", "modelNumber", "presentationURL"
    ]

    var fields: [String: String] = [:]
    var urlBase: String?
    private var deviceDepth = 0
    private var current: String?
    private var buffer = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "device" {
            deviceDepth += 1
        }
        // Only the root device: embedded devices repeat these fields with less useful values.
        if (deviceDepth == 1 && Self.wanted.contains(elementName)) || (deviceDepth == 0 && elementName == "URLBase") {
            current = elementName
            buffer = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if current != nil { buffer += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == current {
            let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                if elementName == "URLBase" {
                    urlBase = value
                } else if fields[elementName] == nil {
                    fields[elementName] = value
                }
            }
            current = nil
            buffer = ""
        }
        if elementName == "device" {
            deviceDepth -= 1
        }
    }
}

public struct UPnPDevice: Sendable, Hashable {
    public var ip: IPv4Address
    public var info: UPnPDescription
    public var server: String?
}

public enum SSDPDiscovery: Sendable {
    static let group = IPv4Address(octets: 239, 255, 255, 250)

    /// Multicasts M-SEARCH on the interface that owns `localIP` and collects replies.
    public static func search(localIP: IPv4Address?, timeout: TimeInterval) -> [SSDPResponse] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { close(fd) }

        var nosig: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosig, socklen_t(MemoryLayout.size(ofValue: nosig)))
        var ttl: UInt8 = 2
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout.size(ofValue: ttl)))
        if let localIP {
            var iface = localIP.sinAddr
            setsockopt(fd, IPPROTO_IP, IP_MULTICAST_IF, &iface, socklen_t(MemoryLayout<in_addr>.size))
        }
        let flags = fcntl(fd, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(1900).bigEndian
        addr.sin_addr = group.sinAddr

        for target in ["ssdp:all", "upnp:rootdevice", "ssdp:all"] {
            let message = """
            M-SEARCH * HTTP/1.1\r
            HOST: 239.255.255.250:1900\r
            MAN: "ssdp:discover"\r
            MX: 1\r
            ST: \(target)\r
            USER-AGENT: macOS UPnP/1.1 GrokIPScanner/\(GrokIPCore.version)\r
            \r

            """
            let bytes = Array(message.utf8)
            _ = bytes.withUnsafeBytes { buffer in
                withUnsafePointer(to: &addr) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        sendto(fd, buffer.baseAddress, buffer.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }

        var responses: [SSDPResponse] = []
        var seen = Set<String>()
        var recvBuf = [UInt8](repeating: 0, count: 4096)
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let remainingMs = max(Int32(deadline.timeIntervalSinceNow * 1000), 0)
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let pr = poll(&pfd, 1, remainingMs)
            if pr <= 0 { break }

            while true {
                var src = sockaddr_in()
                var srcLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                let n = withUnsafeMutablePointer(to: &src) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        recvfrom(fd, &recvBuf, recvBuf.count, 0, sa, &srcLen)
                    }
                }
                if n <= 0 { break }
                let ip = IPv4Address(raw: UInt32(bigEndian: src.sin_addr.s_addr))
                let text = String(decoding: recvBuf.prefix(Int(n)), as: UTF8.self)
                guard let response = SSDPResponse.parse(text, from: ip) else { continue }
                let key = "\(ip.string)|\(response.location?.absoluteString ?? "")|\(response.usn ?? "")"
                if seen.insert(key).inserted {
                    responses.append(response)
                }
            }
        }
        return responses
    }

    /// Fetches each device's description XML (one per IP, root device preferred).
    public static func describe(_ responses: [SSDPResponse], timeout: TimeInterval) async -> [IPv4Address: UPnPDevice] {
        var locations: [IPv4Address: [SSDPResponse]] = [:]
        for response in responses {
            guard let url = response.location, url.scheme == "http" || url.scheme == "https" else { continue }
            // Ignore descriptions hosted somewhere other than the replying box.
            guard url.host == response.ip.string else { continue }
            locations[response.ip, default: []].append(response)
        }
        guard !locations.isEmpty else { return [:] }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.waitsForConnectivity = false
        // No redirects: a LAN box must not be able to bounce this fetch elsewhere.
        let session = URLSession(configuration: config, delegate: RejectRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let gate = Gate(16)

        return await withTaskGroup(of: UPnPDevice?.self, returning: [IPv4Address: UPnPDevice].self) { group in
            for (ip, replies) in locations {
                // Root device first; the rest are embedded services with the same box behind them.
                let ordered = replies.sorted { lhs, rhs in
                    let l = lhs.searchTarget == "upnp:rootdevice"
                    let r = rhs.searchTarget == "upnp:rootdevice"
                    return l && !r
                }
                var urls: [URL] = []
                for reply in ordered {
                    if let url = reply.location, !urls.contains(url) { urls.append(url) }
                }
                let server = ordered.compactMap(\.server).first
                group.addTask {
                    await gate.acquire()
                    defer { Task { await gate.release() } }
                    for url in urls.prefix(3) {
                        guard let fetched = try? await session.data(from: url),
                              let http = fetched.1 as? HTTPURLResponse, http.statusCode == 200,
                              let info = UPnPDescription.parse(fetched.0, base: url) else { continue }
                        return UPnPDevice(ip: ip, info: info, server: server)
                    }
                    return nil
                }
            }
            var result: [IPv4Address: UPnPDevice] = [:]
            for await device in group {
                if let device { result[device.ip] = device }
            }
            return result
        }
    }
}

private final class RejectRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
