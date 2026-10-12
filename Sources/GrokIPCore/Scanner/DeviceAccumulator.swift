import Foundation

final class DeviceAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var devices: [IPv4Address: Device] = [:]
    private let continuation: AsyncStream<ScanEvent>.Continuation

    init(continuation: AsyncStream<ScanEvent>.Continuation) {
        self.continuation = continuation
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return devices.count
    }

    func snapshot(_ ip: IPv4Address) -> Device? {
        lock.lock()
        defer { lock.unlock() }
        return devices[ip]
    }

    @discardableResult
    func upsert(_ incoming: Device) -> Device {
        lock.lock()
        let isNew = devices[incoming.ip] == nil
        var merged = devices[incoming.ip] ?? incoming
        if !isNew {
            merged.merge(incoming)
        } else {
            merged.kind = DeviceClassifier.classify(merged)
        }
        devices[incoming.ip] = merged
        lock.unlock()
        continuation.yield(isNew ? .hostFound(merged) : .hostUpdated(merged))
        return merged
    }

    func ingestBonjour(_ hit: BonjourHit, range: ScanRange) {
        guard let ip = hit.ip, range.contains(ip) else { return }
        var device = Device(ip: ip, hostname: hit.hostname ?? hit.name, model: hit.model, sources: [.bonjour])
        if hit.port > 0, hit.port < 65_536 {
            device.services = [
                NetworkService(name: hit.serviceName, port: UInt16(hit.port), url: hit.webURL)
            ]
        }
        if let url = hit.webURL {
            device.webPages = [
                WebProbeResult(
                    url: url,
                    statusCode: 200,
                    title: hit.name,
                    isLogin: false,
                    isTLS: url.scheme == "https"
                )
            ]
            device.webTitle = hit.name
        }
        upsert(device)
    }
}
