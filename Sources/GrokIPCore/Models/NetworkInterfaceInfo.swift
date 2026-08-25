public struct NetworkInterfaceInfo: Identifiable, Sendable, Hashable {
    public var name: String
    public var localizedName: String
    public var ip: IPv4Address
    public var netmask: IPv4Address
    public var prefix: Int
    public var mac: MACAddress?
    public var isUp: Bool

    public var id: String { name }

    public var cidr: ScanRange {
        ScanRange.cidr(address: ip, prefix: prefix) ?? ScanRange(start: ip, end: ip, prefix: 32)
    }

    public var menuLabel: String {
        "\(localizedName)  \(ip.string)/\(prefix)"
    }

    public init(
        name: String,
        localizedName: String,
        ip: IPv4Address,
        netmask: IPv4Address,
        prefix: Int,
        mac: MACAddress?,
        isUp: Bool
    ) {
        self.name = name
        self.localizedName = localizedName
        self.ip = ip
        self.netmask = netmask
        self.prefix = prefix
        self.mac = mac
        self.isUp = isUp
    }
}

public struct InterfaceSnapshot: Sendable {
    public var interfaces: [NetworkInterfaceInfo]
    public var gatewayIP: IPv4Address?
    public var gatewayInterface: String?

    public init(
        interfaces: [NetworkInterfaceInfo],
        gatewayIP: IPv4Address?,
        gatewayInterface: String?
    ) {
        self.interfaces = interfaces
        self.gatewayIP = gatewayIP
        self.gatewayInterface = gatewayInterface
    }

    public var preferred: NetworkInterfaceInfo? {
        if let gatewayInterface, let match = interfaces.first(where: { $0.name == gatewayInterface }) {
            return match
        }
        return interfaces.first
    }
}
