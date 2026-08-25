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

        print("\(ran - failed)/\(ran) passed")
        if failed > 0 {
            exit(1)
        }
    }
}
