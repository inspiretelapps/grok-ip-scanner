import Foundation

public struct ScanConfig: Sendable {
    public var range: ScanRange
    public var interfaceName: String?
    public var localIP: IPv4Address?
    public var localMAC: MACAddress?
    public var gatewayIP: IPv4Address?
    public var icmpTimeout: TimeInterval
    public var tcpTimeout: TimeInterval
    public var httpTimeout: TimeInterval
    public var dnsTimeout: TimeInterval
    public var tcpPorts: [UInt16]
    public var maxHosts: Int

    public init(
        range: ScanRange,
        interfaceName: String? = nil,
        localIP: IPv4Address? = nil,
        localMAC: MACAddress? = nil,
        gatewayIP: IPv4Address? = nil,
        icmpTimeout: TimeInterval = 0.7,
        tcpTimeout: TimeInterval = 0.28,
        httpTimeout: TimeInterval = 1.6,
        dnsTimeout: TimeInterval = 0.7,
        tcpPorts: [UInt16] = PortCatalog.servicePorts,
        maxHosts: Int = 4094
    ) {
        self.range = range
        self.interfaceName = interfaceName
        self.localIP = localIP
        self.localMAC = localMAC
        self.gatewayIP = gatewayIP
        self.icmpTimeout = icmpTimeout
        self.tcpTimeout = tcpTimeout
        self.httpTimeout = httpTimeout
        self.dnsTimeout = dnsTimeout
        self.tcpPorts = tcpPorts
        self.maxHosts = maxHosts
    }
}

public enum ScanEvent: Sendable {
    case started(totalHosts: Int, range: ScanRange)
    case progress(phase: String, completed: Int, total: Int)
    case hostFound(Device)
    case hostUpdated(Device)
    case finished(found: Int, elapsed: TimeInterval)
    case failed(String)
}
