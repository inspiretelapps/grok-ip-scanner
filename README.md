# Grok IP Scanner

A free macOS LAN scanner in the spirit of Advanced IP Scanner. Hit **Scan** and get every host that answers: IP address, MAC address, hostname, and a **Log in** link when a printer, IP phone, or other box is serving a web UI.

macOS 14+ · Apple Silicon

## Download

**[Download Grok IP Scanner for Mac](https://github.com/inspiretelapps/grok-ip-scanner/releases/latest)**

1. Grab `Grok-IP-Scanner-macos.zip` from the [latest release](https://github.com/inspiretelapps/grok-ip-scanner/releases/latest).
2. Unzip it and drag **Grok IP Scanner** into `/Applications`.
3. First open: right-click the app → **Open** (it is ad-hoc signed, so Gatekeeper will warn once).
4. When macOS asks for **Local Network** access, allow it — the scan cannot see other devices without that.

## Usage

1. Pick the interface (Wi-Fi or Ethernet). The range fills in for you (`192.168.1.0/24` or similar).
2. Click **Scan** (⌘R).
3. Read IP, hostname, MAC, and vendor in the table.
4. Click **Log in** or **Open** on a printer, handset, camera, or NAS to open its web UI in your browser. Double-click a row for the same action.
5. **Export CSV** (⇧⌘E) if you want the list elsewhere.

Stop a running scan with **Stop** or ⌘.

## What it finds

| Field | Source |
| --- | --- |
| IP | ICMP, ARP, TCP, and Bonjour |
| MAC + vendor | ARP table and IEEE OUI |
| Hostname | Reverse DNS, Bonjour / mDNS, NetBIOS |
| Login page | HTTP/HTTPS on common ports (80, 443, 631, 8080, 8443, …) |

MAC addresses are only available for devices on the same Layer-2 network as this Mac.

Some phones and printers ignore ping. Grok IP Scanner also primes ARP, checks common TCP ports, and browses Bonjour so those still show up. It does not guess passwords.

Ranges wider than a `/20` are rejected (a full `/16` is tens of thousands of hosts).

## Build from source

Requires macOS 14+ and Swift 6 (Xcode or Command Line Tools).

```bash
git clone https://github.com/inspiretelapps/grok-ip-scanner.git
cd grok-ip-scanner
./build.sh
open dist/GrokIP.app
```

`./build.sh` runs the unit tests, compiles the app, and writes `dist/GrokIP.app`.

## License

MIT. IBM Plex fonts are bundled under the SIL Open Font License (`Sources/GrokIP/Resources/Fonts/OFL.txt`). MAC vendor data comes from [nmap's mac-prefixes](https://github.com/nmap/nmap).
