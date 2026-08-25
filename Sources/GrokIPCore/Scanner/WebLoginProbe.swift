import Foundation

final class TrustAllDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let method = challenge.protectionSpace.authenticationMethod
        if method == NSURLAuthenticationMethodServerTrust, let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        if method == NSURLAuthenticationMethodHTTPBasic || method == NSURLAuthenticationMethodHTTPDigest {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}

public final class WebLoginProbe: @unchecked Sendable {
    private let session: URLSession
    private let delegate: TrustAllDelegate

    public init(timeout: TimeInterval = 1.6) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.waitsForConnectivity = false
        config.httpMaximumConnectionsPerHost = 2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        delegate = TrustAllDelegate()
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    deinit {
        session.invalidateAndCancel()
    }

    public func probe(ip: IPv4Address, port: UInt16, tls: Bool) async -> WebProbeResult? {
        guard let url = PortCatalog.url(ip: ip, port: port, tls: tls) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: session.configuration.timeoutIntervalForRequest)
        request.httpMethod = "GET"
        request.setValue("text/html,application/xhtml+xml,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("Grok-IP-Scanner/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("close", forHTTPHeaderField: "Connection")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            if http.statusCode == 400 && data.isEmpty { return nil }
            let html = String(data: data.prefix(64 * 1024), encoding: .utf8)
                ?? String(data: data.prefix(64 * 1024), encoding: .isoLatin1)
                ?? ""
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                if let key = key as? String, let value = value as? String {
                    headers[key] = value
                }
            }
            let title = HTMLProbeParser.title(from: html)
            let server = headers.first { $0.key.lowercased() == "server" }?.value
            let isLogin = HTMLProbeParser.looksLikeLogin(status: http.statusCode, headers: headers, html: html)
            let finalURL = http.url ?? url
            return WebProbeResult(
                url: finalURL,
                statusCode: http.statusCode,
                title: title,
                server: server,
                isLogin: isLogin,
                isTLS: tls || finalURL.scheme == "https"
            )
        } catch {
            return nil
        }
    }
}
