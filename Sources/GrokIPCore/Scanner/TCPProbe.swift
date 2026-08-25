import Darwin
import Foundation

public enum TCPProbe: Sendable {
    public enum Result: Sendable, Equatable {
        case open
        case refused
        case timeout
        case error
    }

    public static func connect(ip: IPv4Address, port: UInt16, timeout: TimeInterval) -> Result {
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { return .error }
        defer { close(fd) }

        var nosig: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosig, socklen_t(MemoryLayout.size(ofValue: nosig)))
        let flags = fcntl(fd, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = ip.sinAddr

        let rc = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if rc == 0 { return .open }
        if errno != EINPROGRESS && errno != EWOULDBLOCK {
            return errno == ECONNREFUSED ? .refused : .error
        }

        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let pr = poll(&pfd, 1, Int32(max(timeout * 1000, 1)))
        if pr == 0 { return .timeout }
        if pr < 0 { return .error }

        var err: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len)
        if err == 0 { return .open }
        if err == ECONNREFUSED { return .refused }
        if err == ETIMEDOUT { return .timeout }
        return .error
    }

    public static func isLive(_ result: Result) -> Bool {
        result == .open || result == .refused
    }

    public static func scan(
        hosts: [IPv4Address],
        ports: [UInt16],
        timeout: TimeInterval,
        concurrency: Int = 96
    ) async -> [IPv4Address: [UInt16: Result]] {
        guard !hosts.isEmpty, !ports.isEmpty else { return [:] }
        let gate = Gate(concurrency)
        return await withTaskGroup(of: (IPv4Address, UInt16, Result).self, returning: [IPv4Address: [UInt16: Result]].self) { group in
            for host in hosts {
                for port in ports {
                    group.addTask {
                        await gate.acquire()
                        defer { Task { await gate.release() } }
                        if Task.isCancelled { return (host, port, .timeout) }
                        let result = connect(ip: host, port: port, timeout: timeout)
                        return (host, port, result)
                    }
                }
            }
            var map: [IPv4Address: [UInt16: Result]] = [:]
            for await (host, port, result) in group {
                map[host, default: [:]][port] = result
            }
            return map
        }
    }
}
