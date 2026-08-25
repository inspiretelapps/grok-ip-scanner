import Darwin
import Foundation

public enum HostnameResolver: Sendable {
    public static func reverse(ip: IPv4Address, timeout: TimeInterval) -> String? {
        let box = Box()
        let lock = NSLock()
        let work = DispatchWorkItem {
            let name = lookup(ip)
            lock.lock()
            box.value = name
            lock.unlock()
        }
        DispatchQueue.global(qos: .userInitiated).async(execute: work)
        let result = work.wait(timeout: .now() + timeout)
        if result == .timedOut {
            return nil
        }
        lock.lock()
        defer { lock.unlock() }
        return clean(box.value)
    }

    private static func lookup(_ ip: IPv4Address) -> String? {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr = ip.sinAddr
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let rc = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                getnameinfo(sa, socklen_t(MemoryLayout<sockaddr_in>.size), &host, socklen_t(host.count), nil, 0, NI_NAMEREQD)
            }
        }
        guard rc == 0 else { return nil }
        return host.withUnsafeBufferPointer { buffer in
            let length = buffer.firstIndex(of: 0) ?? buffer.count
            return String(decoding: buffer.prefix(length).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
    }

    public static func clean(_ value: String?) -> String? {
        guard var value, !value.isEmpty else { return nil }
        if value.hasSuffix(".") { value.removeLast() }
        if value.lowercased().hasSuffix(".in-addr.arpa") { return nil }
        if IPv4Address(value) != nil { return nil }
        return value
    }

    private final class Box: @unchecked Sendable {
        var value: String?
    }
}
