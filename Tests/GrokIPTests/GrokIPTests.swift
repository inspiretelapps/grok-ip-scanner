import Testing
@testable import GrokIPCore

struct IPv4Tests {
    @Test func parsesDottedQuad() {
        let ip = IPv4Address("192.168.1.20")
        #expect(ip?.string == "192.168.1.20")
        #expect(ip?.raw == 0xC0A8_0114)
    }

    @Test func rejectsJunk() {
        #expect(IPv4Address("192.168.1") == nil)
        #expect(IPv4Address("192.168.1.256") == nil)
        #expect(IPv4Address("hello") == nil)
    }

    @Test func sortsNumerically() {
        let a = IPv4Address("192.168.1.9")!
        let b = IPv4Address("192.168.1.10")!
        #expect(a < b)
    }

    @Test func cidrSlash24SkipsNetworkAndBroadcast() {
        let range = ScanRange.parse("192.168.1.0/24")
        #expect(range?.hostCount == 254)
        #expect(range?.start.string == "192.168.1.1")
        #expect(range?.end.string == "192.168.1.254")
        #expect(range?.description == "192.168.1.0/24")
    }

    @Test func cidrFromHostAddress() {
        let range = ScanRange.parse("10.0.0.5/24")
        #expect(range?.start.string == "10.0.0.1")
        #expect(range?.contains(IPv4Address("10.0.0.5")!) == true)
        #expect(range?.contains(IPv4Address("10.0.1.1")!) == false)
    }

    @Test func slash32AndSlash31() {
        #expect(ScanRange.parse("10.0.0.8/32")?.hostCount == 1)
        #expect(ScanRange.parse("10.0.0.8/31")?.hostCount == 2)
    }

    @Test func dashRangeAndLastOctet() {
        let a = ScanRange.parse("192.168.1.10-192.168.1.12")
        #expect(a?.hostCount == 3)
        let b = ScanRange.parse("192.168.1.10-12")
        #expect(b?.hosts.map(\.string) == ["192.168.1.10", "192.168.1.11", "192.168.1.12"])
    }

    @Test func prefixFromMask() {
        #expect(ScanRange.prefixLength(mask: 0xFFFF_FF00) == 24)
        #expect(ScanRange.prefixLength(mask: 0xFFFF_FF80) == 25)
        #expect(ScanRange.prefixLength(mask: 0xFFFF_FE01) == nil)
    }
}

struct MACTests {
    @Test func parsesFormats() {
        let a = MACAddress.parse("00:00:0c:11:22:33")
        let b = MACAddress.parse("00-00-0C-11-22-33")
        let c = MACAddress.parse("00000c112233")
        #expect(a?.canonical == "00:00:0c:11:22:33")
        #expect(a == b)
        #expect(b == c)
    }

    @Test func flags() {
        let multicast = MACAddress.parse("01:00:5e:00:00:fb")!
        #expect(multicast.isMulticast)
        let laa = MACAddress.parse("02:00:00:00:00:01")!
        #expect(laa.isLocallyAdministered)
    }
}

struct OUITests {
    @Test func looksUpCiscoAndRandomized() {
        let oui = OUILookup.bundled()
        #expect(!oui.isEmpty)
        let cisco = MACAddress.parse("00:00:0c:aa:bb:cc")!
        #expect(oui.vendor(for: cisco)?.contains("Cisco") == true)
        let random = MACAddress.parse("02:00:00:00:00:01")!
        #expect(oui.vendor(for: random) == "Randomized MAC")
    }
}

struct ARPParserTests {
    @Test func parsesArpDashAn() {
        let sample = """
        ? (192.168.1.1) at 14:eb:b6:aa:bb:cc on en0 ifscope [ethernet]
        ? (192.168.1.12) at (incomplete) on en0 ifscope [ethernet]
        ? (192.168.1.20) at a4:83:e7:01:02:03 on en1 ifscope [ethernet]
        ? (224.0.0.251) at 1:0:5e:0:0:fb on en0 ifscope permanent [ethernet]
        """
        let table = ARPTable.parseCommandOutput(sample, interfaceName: "en0")
        #expect(table[IPv4Address("192.168.1.1")!]?.canonical == "14:eb:b6:aa:bb:cc")
        #expect(table[IPv4Address("192.168.1.12")!] == nil)
        #expect(table[IPv4Address("192.168.1.20")!] == nil)
        #expect(table[IPv4Address("224.0.0.251")!] == nil)
    }
}

struct HTMLParserTests {
    @Test func extractsTitleAndLogin() {
        let html = """
        <html><head><title>
          HP LaserJet Pro &amp; MFP
        </title></head>
        <body><form><input type="password" name="password"></form></body></html>
        """
        #expect(HTMLProbeParser.title(from: html) == "HP LaserJet Pro & MFP")
        #expect(HTMLProbeParser.hasPasswordField(html))
        #expect(HTMLProbeParser.looksLikeLogin(status: 200, headers: [:], html: html))
        #expect(HTMLProbeParser.looksLikeLogin(status: 401, headers: [:], html: ""))
        #expect(HTMLProbeParser.looksLikeLogin(status: 200, headers: ["WWW-Authenticate": "Basic"], html: ""))
    }
}

struct ClassifierTests {
    @Test func classifiesPrinterPhoneComputerAndGateway() {
        var printer = Device(ip: IPv4Address("10.0.0.20")!, webTitle: "HP LaserJet Pro M428")
        printer.services = [NetworkService(name: "JetDirect", port: 9100)]
        #expect(DeviceClassifier.classify(printer) == .printer)

        var phone = Device(ip: IPv4Address("10.0.0.30")!, vendor: "Yealink Network Technology")
        phone.services = [NetworkService(name: "SIP", port: 5060)]
        #expect(DeviceClassifier.classify(phone) == .ipPhone)

        var pc = Device(ip: IPv4Address("10.0.0.40")!)
        pc.services = [NetworkService(name: "SMB", port: 445)]
        #expect(DeviceClassifier.classify(pc) == .computer)

        let gw = Device(ip: IPv4Address("10.0.0.1")!, isGateway: true)
        #expect(DeviceClassifier.classify(gw) == .gateway)

        let me = Device(ip: IPv4Address("10.0.0.50")!, isLocal: true)
        #expect(DeviceClassifier.classify(me) == .thisMac)
    }
}

struct CSVTests {
    @Test func escapesCommasAndQuotes() {
        let line = CSV.escape(["192.168.1.1", "Office, printer", "He said \"hi\""])
        #expect(line == "192.168.1.1,\"Office, printer\",\"He said \"\"hi\"\"\"")
    }
}

struct ICMPChecksumTests {
    @Test func validPacketChecksumsToZero() {
        var packet = ICMPSweep.echoPacket(identifier: 0x1234, sequence: 1)
        #expect(ICMPChecksum.compute(packet) == 0)
        packet[2] = 0
        packet[3] = 0
        let sum = ICMPChecksum.compute(packet)
        #expect(sum != 0)
    }
}

struct NetBIOSTests {
    @Test func encodesStarName() {
        let encoded = NetBIOS.encodeName("*")
        #expect(encoded.first == 0x20)
        #expect(encoded.count == 34)
        #expect(encoded[1] == ((0x2A >> 4) & 0x0F) + 0x41)
    }
}

struct DeviceMergeTests {
    @Test func prefersBonjourHostnameAndLoginPage() {
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
        #expect(a.hostname == "reception-printer.local")
        #expect(a.loginLabel == "Log in")
        #expect(a.primaryLogin?.url.absoluteString == "http://10.0.0.8/")
    }
}
