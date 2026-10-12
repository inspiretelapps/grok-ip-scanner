import Foundation

public actor ScanEngine {
    public func scan(config: ScanConfig, oui: OUILookup) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            let task = Task {
                await self.run(config: config, oui: oui, continuation: continuation)
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func run(
        config: ScanConfig,
        oui: OUILookup,
        continuation: AsyncStream<ScanEvent>.Continuation
    ) async {
        let started = Date()
        let hosts = config.range.hosts
        guard !hosts.isEmpty else {
            continuation.yield(.failed("The range does not contain any hosts."))
            continuation.finish()
            return
        }
        if hosts.count > config.maxHosts {
            continuation.yield(.failed("Range is \(hosts.count) hosts; keep it at \(config.maxHosts) or smaller (a /20 or tighter)."))
            continuation.finish()
            return
        }

        continuation.yield(.started(totalHosts: hosts.count, range: config.range))
        continuation.yield(.progress(phase: "Priming the subnet", completed: 0, total: hosts.count))

        let acc = DeviceAccumulator(continuation: continuation)

        if let localIP = config.localIP, config.range.contains(localIP) {
            var local = Device(ip: localIP, mac: config.localMAC, isLocal: true, sources: [.local])
            local.hostname = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
            local.vendor = local.mac.flatMap { oui.vendor(for: $0) }
            local.kind = .thisMac
            acc.upsert(local)
        }
        if let gateway = config.gatewayIP, config.range.contains(gateway) {
            var gw = Device(ip: gateway, isGateway: true, sources: [.local])
            gw.kind = .gateway
            acc.upsert(gw)
        }

        let bonjour = BonjourDiscovery()
        let range = config.range
        bonjour.start { hit in
            acc.ingestBonjour(hit, range: range)
        }

        func finishEarly() {
            bonjour.stop()
            continuation.yield(.finished(found: acc.count, elapsed: Date().timeIntervalSince(started)))
            continuation.finish()
        }

        let hostsCopy = hosts
        await Task.detached(priority: .userInitiated) {
            UDPBurst.send(hosts: hostsCopy)
        }.value

        try? await Task.sleep(for: .milliseconds(80))
        if Task.isCancelled {
            finishEarly()
            return
        }

        // UPnP/SSDP runs alongside the sweep: TVs, speakers, routers and NAS boxes
        // announce a friendly name and model here even when they ignore ping.
        let ssdpLocalIP = config.localIP
        let ssdpTimeout = config.ssdpTimeout
        async let ssdpTask: [SSDPResponse] = Task.detached(priority: .userInitiated) {
            SSDPDiscovery.search(localIP: ssdpLocalIP, timeout: ssdpTimeout)
        }.value

        continuation.yield(.progress(phase: "Pinging hosts", completed: 0, total: hosts.count))
        let icmpTimeout = config.icmpTimeout
        async let icmpTask: [IPv4Address: Double] = Task.detached(priority: .userInitiated) {
            ICMPSweep.sweep(hosts: hostsCopy, timeout: icmpTimeout)
        }.value

        try? await Task.sleep(for: .milliseconds(220))
        var arp = await Task.detached(priority: .userInitiated) {
            ARPTable.load(interfaceName: config.interfaceName)
        }.value

        let icmp = await icmpTask
        arp.merge(
            await Task.detached(priority: .userInitiated) {
                ARPTable.load(interfaceName: config.interfaceName)
            }.value,
            uniquingKeysWith: { _, new in new }
        )

        var live = Set<IPv4Address>()
        live.formUnion(icmp.keys.filter { config.range.contains($0) })
        for (ip, _) in arp where config.range.contains(ip) {
            live.insert(ip)
        }
        if let localIP = config.localIP, config.range.contains(localIP) { live.insert(localIP) }
        if let gateway = config.gatewayIP, config.range.contains(gateway) { live.insert(gateway) }

        for ip in live.sorted() {
            var device = acc.snapshot(ip) ?? Device(ip: ip)
            if let mac = arp[ip] ?? (ip == config.localIP ? config.localMAC : nil) {
                device.mac = mac
                device.vendor = oui.vendor(for: mac)
                device.sources.insert(.arp)
            }
            if let rtt = icmp[ip] {
                device.rttMilliseconds = rtt
                device.sources.insert(.icmp)
            }
            if ip == config.localIP { device.isLocal = true }
            if ip == config.gatewayIP { device.isGateway = true }
            acc.upsert(device)
        }

        if Task.isCancelled {
            finishEarly()
            return
        }

        let dark = hosts.filter { !live.contains($0) }
        continuation.yield(.progress(phase: "Looking for quiet hosts", completed: live.count, total: hosts.count))
        if !dark.isEmpty {
            let tcpTimeout = min(config.tcpTimeout, 0.2)
            let darkScan = await TCPProbe.scan(
                hosts: dark,
                ports: [80, 443, 22, 445, 9100, 62078],
                timeout: tcpTimeout,
                concurrency: 128
            )
            for (ip, ports) in darkScan where ports.values.contains(where: TCPProbe.isLive) {
                live.insert(ip)
                var device = acc.snapshot(ip) ?? Device(ip: ip, sources: [.tcp])
                device.sources.insert(.tcp)
                acc.upsert(device)
            }
            arp.merge(
                await Task.detached(priority: .userInitiated) {
                    ARPTable.load(interfaceName: config.interfaceName)
                }.value,
                uniquingKeysWith: { _, new in new }
            )
            for ip in live {
                if let mac = arp[ip], acc.snapshot(ip)?.mac == nil {
                    var device = acc.snapshot(ip) ?? Device(ip: ip)
                    device.mac = mac
                    device.vendor = oui.vendor(for: mac)
                    device.sources.insert(.arp)
                    acc.upsert(device)
                }
            }
        }

        let ssdpResponses = await ssdpTask
        let upnp = await SSDPDiscovery.describe(
            ssdpResponses.filter { config.range.contains($0.ip) },
            timeout: config.httpTimeout
        )
        let ssdpIPs = Set(ssdpResponses.map(\.ip)).filter { config.range.contains($0) }
        for ip in ssdpIPs.sorted() {
            live.insert(ip)
            var device = acc.snapshot(ip) ?? Device(ip: ip)
            device.sources.insert(.ssdp)
            if let info = upnp[ip]?.info {
                if let name = info.friendlyName, device.hostname == nil {
                    device.hostname = name
                }
                if device.model == nil {
                    device.model = info.model
                }
                if let url = info.presentationURL,
                   url.scheme == "http" || url.scheme == "https",
                   url.host == ip.string,
                   !device.webPages.contains(where: { $0.url == url }) {
                    device.webPages.append(
                        WebProbeResult(
                            url: url,
                            statusCode: 200,
                            title: info.friendlyName,
                            server: upnp[ip]?.server,
                            isLogin: false,
                            isTLS: url.scheme == "https"
                        )
                    )
                }
            }
            if device.mac == nil, let mac = arp[ip] {
                device.mac = mac
                device.vendor = oui.vendor(for: mac)
                device.sources.insert(.arp)
            }
            acc.upsert(device)
        }

        let targets = live.sorted()
        continuation.yield(.progress(phase: "Reading names and login pages", completed: 0, total: max(targets.count, 1)))

        let web = WebLoginProbe(timeout: config.httpTimeout)
        let enrichGate = Gate(24)
        let dnsTimeout = config.dnsTimeout
        let tcpTimeout = config.tcpTimeout
        let servicePorts = config.tcpPorts
        let localIP = config.localIP
        let localMAC = config.localMAC
        let gatewayIP = config.gatewayIP
        let arpSnapshot = arp
        let icmpSnapshot = icmp

        await withTaskGroup(of: Device.self) { group in
            for ip in targets {
                let existing = acc.snapshot(ip)
                let mac = arpSnapshot[ip]
                let rtt = icmpSnapshot[ip]
                group.addTask {
                    await enrichGate.acquire()
                    defer { Task { await enrichGate.release() } }
                    return await ScanEngine.enrich(
                        ip: ip,
                        existing: existing,
                        arp: mac,
                        localMAC: ip == localIP ? localMAC : nil,
                        isLocal: ip == localIP,
                        isGateway: ip == gatewayIP,
                        icmp: rtt,
                        oui: oui,
                        web: web,
                        dnsTimeout: dnsTimeout,
                        tcpTimeout: tcpTimeout,
                        ports: servicePorts
                    )
                }
            }
            var completed = 0
            for await device in group {
                acc.upsert(device)
                completed += 1
                continuation.yield(
                    .progress(phase: "Reading names and login pages", completed: completed, total: targets.count)
                )
                if Task.isCancelled {
                    group.cancelAll()
                }
            }
        }

        if !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(900))

            // Last ARP read: the port and web probes above made the kernel resolve
            // hosts that were silent earlier, so pick up their MACs (and any host
            // that only ever answered ARP).
            let lateARP = await Task.detached(priority: .userInitiated) {
                ARPTable.load(interfaceName: config.interfaceName)
            }.value
            for (ip, mac) in lateARP where config.range.contains(ip) {
                let existing = acc.snapshot(ip)
                guard existing?.mac == nil else { continue }
                var device = existing ?? Device(ip: ip)
                device.mac = mac
                device.vendor = oui.vendor(for: mac)
                device.sources.insert(.arp)
                acc.upsert(device)
            }
        }
        bonjour.stop()
        continuation.yield(.finished(found: acc.count, elapsed: Date().timeIntervalSince(started)))
        continuation.finish()
    }

    private static func enrich(
        ip: IPv4Address,
        existing: Device?,
        arp: MACAddress?,
        localMAC: MACAddress?,
        isLocal: Bool,
        isGateway: Bool,
        icmp: Double?,
        oui: OUILookup,
        web: WebLoginProbe,
        dnsTimeout: TimeInterval,
        tcpTimeout: TimeInterval,
        ports: [UInt16]
    ) async -> Device {
        var device = existing ?? Device(ip: ip)
        device.isLocal = device.isLocal || isLocal
        device.isGateway = device.isGateway || isGateway
        if device.rttMilliseconds == nil { device.rttMilliseconds = icmp }
        if device.mac == nil { device.mac = arp ?? localMAC }
        if let mac = device.mac, device.vendor == nil {
            device.vendor = oui.vendor(for: mac)
        }

        async let dnsName = Task.detached(priority: .userInitiated) {
            HostnameResolver.reverse(ip: ip, timeout: dnsTimeout)
        }.value
        async let netbiosName = Task.detached(priority: .userInitiated) {
            NetBIOS.query(ip: ip)
        }.value
        async let portMap = TCPProbe.scan(
            hosts: [ip],
            ports: ports,
            timeout: tcpTimeout,
            concurrency: ports.count
        )

        if let name = await dnsName {
            device.hostname = HostnameResolver.clean(name) ?? device.hostname
        }
        if let name = await netbiosName {
            device.sources.insert(.netbios)
            if device.hostname == nil {
                device.hostname = name
            }
        }

        let scanned = await portMap[ip] ?? [:]
        var openPorts: [UInt16] = []
        for (port, result) in scanned where result == .open {
            openPorts.append(port)
            let name = PortCatalog.serviceName(for: port)
            let tls = port == 443 || port == 8443 || port == 10443
            let url = (name == "HTTP" || name == "HTTPS" || name == "IPP")
                ? PortCatalog.url(ip: ip, port: port, tls: tls)
                : nil
            if !device.services.contains(where: { $0.port == port }) {
                device.services.append(NetworkService(name: name, port: port, url: url))
            }
            device.sources.insert(.tcp)
        }
        device.services.sort { $0.port < $1.port }

        var webPorts = PortCatalog.webCandidates.filter { openPorts.contains($0.port) }
        if webPorts.isEmpty, Self.likelyHasWebUI(device) {
            webPorts = [(80, false), (443, true)]
        }
        if !webPorts.isEmpty {
            var pages: [WebProbeResult] = []
            await withTaskGroup(of: WebProbeResult?.self) { group in
                for candidate in webPorts {
                    group.addTask {
                        await web.probe(ip: ip, port: candidate.port, tls: candidate.tls)
                    }
                }
                for await page in group {
                    if let page { pages.append(page) }
                }
            }
            if !pages.isEmpty {
                for page in pages {
                    if !device.webPages.contains(where: { $0.url == page.url }) {
                        device.webPages.append(page)
                    }
                }
                if device.webTitle == nil {
                    device.webTitle = pages.first(where: { $0.title != nil })?.title
                }
            }
        }

        device.kind = DeviceClassifier.classify(device)
        return device
    }

    private static func likelyHasWebUI(_ device: Device) -> Bool {
        let blob = ((device.vendor ?? "") + " " + (device.hostname ?? "")).lowercased()
        let needles = [
            "yealink", "grandstream", "polycom", "hp", "brother", "epson", "xerox",
            "ruijie", "cisco", "ubiquiti", "tp-link", "netis", "synology", "qnap"
        ]
        return needles.contains { blob.contains($0) }
            || device.kind == .printer
            || device.kind == .ipPhone
            || device.kind == .networkGear
    }
}
