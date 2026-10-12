import Foundation
#if canImport(Darwin)
import Darwin
#endif

@main
struct RunTests {
    static func main() {
        var failed = 0
        var ran = 0

        func check(_ name: String, _ body: () throws -> Bool) {
            ran += 1
            do {
                if try body() {
                    print("ok   \(name)")
                } else {
                    print("FAIL \(name)")
                    failed += 1
                }
            } catch {
                print("FAIL \(name): \(error)")
                failed += 1
            }
        }

        check("parse dotted quad") {
            let ip = IPv4Address("192.168.1.20")
            return ip?.string == "192.168.1.20" && ip?.raw == 0xC0A8_0114
        }
        check("reject junk IPs") {
            IPv4Address("192.168.1") == nil && IPv4Address("192.168.1.256") == nil && IPv4Address("hello") == nil
        }
        check("sort IPs numerically") {
            IPv4Address("192.168.1.9")! < IPv4Address("192.168.1.10")!
        }
        check("cidr /24 skips network and broadcast") {
            let range = ScanRange.parse("192.168.1.0/24")
            return range?.hostCount == 254
                && range?.start.string == "192.168.1.1"
                && range?.end.string == "192.168.1.254"
                && range?.description == "192.168.1.0/24"
        }
        check("cidr from host address") {
            let range = ScanRange.parse("10.0.0.5/24")
            return range?.start.string == "10.0.0.1"
                && range?.contains(IPv4Address("10.0.0.5")!) == true
                && range?.contains(IPv4Address("10.0.1.1")!) == false
        }
        check("slash 32 and 31") {
            ScanRange.parse("10.0.0.8/32")?.hostCount == 1 && ScanRange.parse("10.0.0.8/31")?.hostCount == 2
        }
        check("dash ranges") {
            let a = ScanRange.parse("192.168.1.10-192.168.1.12")
            let b = ScanRange.parse("192.168.1.10-12")
            return a?.hostCount == 3 && b?.hosts.map(\.string) == ["192.168.1.10", "192.168.1.11", "192.168.1.12"]
        }
        check("prefix from mask") {
            ScanRange.prefixLength(mask: 0xFFFF_FF00) == 24
                && ScanRange.prefixLength(mask: 0xFFFF_FF80) == 25
                && ScanRange.prefixLength(mask: 0xFFFF_FE01) == nil
        }
        check("mac parse formats") {
            let a = MACAddress.parse("00:00:0c:11:22:33")
            let b = MACAddress.parse("00-00-0C-11-22-33")
            let c = MACAddress.parse("00000c112233")
            return a?.canonical == "00:00:0c:11:22:33" && a == b && b == c
        }
        check("mac flags") {
            MACAddress.parse("01:00:5e:00:00:fb")!.isMulticast
                && MACAddress.parse("02:00:00:00:00:01")!.isLocallyAdministered
        }
        check("oui cisco and randomized") {
            let oui = OUILookup.bundled()
            guard !oui.isEmpty else { return false }
            let cisco = MACAddress.parse("00:00:0c:aa:bb:cc")!
            let random = MACAddress.parse("02:00:00:00:00:01")!
            return oui.vendor(for: cisco)?.contains("Cisco") == true
                && oui.vendor(for: random) == "Randomized MAC"
        }
        check("arp parser") {
            let sample = """
            ? (192.168.1.1) at 14:eb:b6:aa:bb:cc on en0 ifscope [ethernet]
            ? (192.168.1.12) at (incomplete) on en0 ifscope [ethernet]
            ? (192.168.1.20) at a4:83:e7:01:02:03 on en1 ifscope [ethernet]
            ? (224.0.0.251) at 1:0:5e:0:0:fb on en0 ifscope permanent [ethernet]
            """
            let table = ARPTable.parseCommandOutput(sample, interfaceName: "en0")
            return table[IPv4Address("192.168.1.1")!]?.canonical == "14:eb:b6:aa:bb:cc"
                && table[IPv4Address("192.168.1.12")!] == nil
                && table[IPv4Address("192.168.1.20")!] == nil
                && table[IPv4Address("224.0.0.251")!] == nil
        }
        check("html title and login") {
            let html = """
            <html><head><title>
              HP LaserJet Pro &amp; MFP
            </title></head>
            <body><form><input type="password" name="password"></form></body></html>
            """
            return HTMLProbeParser.title(from: html) == "HP LaserJet Pro & MFP"
                && HTMLProbeParser.hasPasswordField(html)
                && HTMLProbeParser.looksLikeLogin(status: 200, headers: [:], html: html)
                && HTMLProbeParser.looksLikeLogin(status: 401, headers: [:], html: "")
                && HTMLProbeParser.looksLikeLogin(status: 200, headers: ["WWW-Authenticate": "Basic"], html: "")
        }
        check("classifier") {
            var printer = Device(ip: IPv4Address("10.0.0.20")!, webTitle: "HP LaserJet Pro M428")
            printer.services = [NetworkService(name: "JetDirect", port: 9100)]
            var phone = Device(ip: IPv4Address("10.0.0.30")!, vendor: "Yealink Network Technology")
            phone.services = [NetworkService(name: "SIP", port: 5060)]
            var pc = Device(ip: IPv4Address("10.0.0.40")!)
            pc.services = [NetworkService(name: "SMB", port: 445)]
            let gw = Device(ip: IPv4Address("10.0.0.1")!, isGateway: true)
            let me = Device(ip: IPv4Address("10.0.0.50")!, isLocal: true)
            return DeviceClassifier.classify(printer) == .printer
                && DeviceClassifier.classify(phone) == .ipPhone
                && DeviceClassifier.classify(pc) == .computer
                && DeviceClassifier.classify(gw) == .gateway
                && DeviceClassifier.classify(me) == .thisMac
        }
        check("csv escape") {
            CSV.escape(["192.168.1.1", "Office, printer", "He said \"hi\""])
                == "192.168.1.1,\"Office, printer\",\"He said \"\"hi\"\"\""
        }
        check("icmp checksum") {
            var packet = ICMPSweep.echoPacket(identifier: 0x1234, sequence: 1)
            guard ICMPChecksum.compute(packet) == 0 else { return false }
            packet[2] = 0
            packet[3] = 0
            return ICMPChecksum.compute(packet) != 0
        }
        check("netbios encode") {
            let encoded = NetBIOS.encodeName("*")
            return encoded.first == 0x20 && encoded.count == 34 && encoded[1] == ((0x2A >> 4) & 0x0F) + 0x41
        }
        check("device merge hostname and login") {
            var a = Device(ip: IPv4Address("10.0.0.8")!, hostname: "10.0.0.8")
            var b = Device(ip: IPv4Address("10.0.0.8")!, hostname: "reception-printer.local")
            b.webPages = [
                WebProbeResult(
                    url: URL(string: "http://10.0.0.8/")!,
                    statusCode: 200,
                    title: "HP Color LaserJet",
                    isLogin: true,
                    isTLS: false
                )
            ]
            a.merge(b)
            return a.hostname == "reception-printer.local"
                && a.loginLabel == "Log in"
                && a.primaryLogin?.url.absoluteString == "http://10.0.0.8/"
        }

        check("ssdp response parse") {
            let reply = "HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\nLOCATION: http://192.168.1.40:49152/description.xml\r\nSERVER: Linux/4.9 UPnP/1.0 Sonos/80.1\r\nST: upnp:rootdevice\r\nUSN: uuid:RINCON_1::upnp:rootdevice\r\n\r\n"
            let ip = IPv4Address("192.168.1.40")!
            let parsed = SSDPResponse.parse(reply, from: ip)
            return parsed?.location?.absoluteString == "http://192.168.1.40:49152/description.xml"
                && parsed?.server == "Linux/4.9 UPnP/1.0 Sonos/80.1"
                && parsed?.searchTarget == "upnp:rootdevice"
                && SSDPResponse.parse("M-SEARCH * HTTP/1.1\r\n\r\n", from: ip) == nil
        }
        check("upnp description parse") {
            let xml = """
            <?xml version="1.0"?>
            <root xmlns="urn:schemas-upnp-org:device-1-0">
              <specVersion><major>1</major><minor>0</minor></specVersion>
              <device>
                <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
                <friendlyName>Living Room TV</friendlyName>
                <manufacturer>Samsung Electronics</manufacturer>
                <modelName>UE55TU7100</modelName>
                <modelNumber>AllShare1.0</modelNumber>
                <presentationURL>/index.html</presentationURL>
                <deviceList>
                  <device><friendlyName>Embedded</friendlyName><manufacturer>Other</manufacturer></device>
                </deviceList>
              </device>
            </root>
            """
            let base = URL(string: "http://192.168.1.50:7676/dmr")!
            let info = UPnPDescription.parse(Data(xml.utf8), base: base)
            return info?.friendlyName == "Living Room TV"
                && info?.manufacturer == "Samsung Electronics"
                && info?.model == "Samsung Electronics UE55TU7100 AllShare1.0"
                && info?.presentationURL?.absoluteString == "http://192.168.1.50:7676/index.html"
        }
        check("upnp model label dedupes manufacturer") {
            UPnPDescription(manufacturer: "Synology", modelName: "Synology DS220+", modelNumber: "DS220+").model
                == "Synology DS220+"
        }
        check("wake-on-lan magic packet") {
            let mac = MACAddress.parse("aa:bb:cc:dd:ee:ff")!
            let packet = WakeOnLAN.magicPacket(for: mac)
            return packet.count == 102
                && packet.prefix(6).allSatisfy { $0 == 0xFF }
                && Array(packet[6..<12]) == mac.bytes
                && Array(packet[96..<102]) == mac.bytes
        }
        check("bonjour txt model") {
            let hit = BonjourHit(
                name: "Office Mac",
                type: "_device-info._tcp.",
                hostname: nil,
                ip: nil,
                port: 0,
                txt: ["model": "MacBookPro18,3"]
            )
            return hit.model == "MacBookPro18,3"
        }
        check("interface broadcast") {
            let iface = NetworkInterfaceInfo(
                name: "en0",
                localizedName: "Wi-Fi",
                ip: IPv4Address("192.168.1.23")!,
                netmask: IPv4Address("255.255.255.0")!,
                prefix: 24,
                mac: nil,
                isUp: true
            )
            return iface.broadcast.string == "192.168.1.255"
        }
        check("csv has model column") {
            let device = Device(ip: IPv4Address("10.0.0.9")!, model: "Synology DS220+")
            return Device.csvHeader().count == device.csvFields().count
                && device.csvFields()[4] == "Synology DS220+"
        }

        print("\(ran - failed)/\(ran) passed")
        if failed > 0 {
            exit(1)
        }
    }
}
