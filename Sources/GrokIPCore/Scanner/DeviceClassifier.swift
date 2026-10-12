import Foundation

public enum DeviceClassifier: Sendable {
    public static func classify(_ device: Device) -> DeviceKind {
        if device.isLocal { return .thisMac }
        if device.isGateway { return .gateway }

        let haystack = blob(device)

        if matches(haystack, [
            "laserjet", "deskjet", "officejet", "envy", "pagewide", "ecosys", "bizhub",
            "imagerunner", "brother", "epson", "kyocera", "xerox", "ricoh", "konica",
            "pantum", "cups", "jetdirect", "ipp", "printer", "print server"
        ]) || hasPort(device, [515, 631, 9100]) || hasService(device, ["IPP", "JetDirect", "LPD"]) {
            return .printer
        }

        if matches(haystack, [
            "yealink", "grandstream", "polycom", "poly ", "mitel", "fanvil", "snom",
            "gigaset", "sip-t", "ip phone", "ipphone", "handset", "cisco spa",
            "linksys spa", "voip", "sip phone"
        ]) || hasPort(device, [5060]) {
            return .ipPhone
        }

        if matches(haystack, [
            "hikvision", "dahua", "reolink", "amcrest", "onvif", "ip camera",
            "ipcam", "webcam", "axis communications"
        ]) || hasPort(device, [554]) {
            return .camera
        }

        if matches(haystack, [
            "synology", "qnap", "truenas", "diskstation", "unraid", "openmediavault",
            "true nas", "freenas"
        ]) {
            return .nas
        }

        if matches(haystack, ["apple", "macbook", "imac", "iphone", "ipad", "airport", "airplay"])
            || hasPort(device, [62078]) {
            return .apple
        }

        if matches(haystack, [
            "mikrotik", "ubiquiti", "unifi", "cisco", "meraki", "aruba", "netgear",
            "tp-link", "tplink", "d-link", "dlink", "zyxel", "fortinet", "sophos",
            "openwrt", "juniper", "omada", "edgeos", "unifi"
        ]) {
            return .networkGear
        }

        if hasPort(device, [445, 139, 3389]) || hasService(device, ["SMB", "RDP", "NetBIOS"]) {
            return .computer
        }

        return .unknown
    }

    private static func blob(_ device: Device) -> String {
        var parts: [String] = []
        if let hostname = device.hostname { parts.append(hostname) }
        if let vendor = device.vendor { parts.append(vendor) }
        if let model = device.model { parts.append(model) }
        if let title = device.webTitle { parts.append(title) }
        parts.append(contentsOf: device.webPages.compactMap(\.title))
        parts.append(contentsOf: device.webPages.compactMap(\.server))
        parts.append(contentsOf: device.services.map(\.name))
        return parts.joined(separator: " ").lowercased()
    }

    private static func matches(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    private static func hasPort(_ device: Device, _ ports: [UInt16]) -> Bool {
        let open = Set(device.services.map(\.port))
        return ports.contains(where: { open.contains($0) })
    }

    private static func hasService(_ device: Device, _ names: [String]) -> Bool {
        let have = Set(device.services.map { $0.name.lowercased() })
        return names.contains { have.contains($0.lowercased()) }
    }
}
