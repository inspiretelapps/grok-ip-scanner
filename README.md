# Grok IP Scanner

A free macOS LAN scanner in the spirit of Advanced IP Scanner. Hit **Scan** and get every host that answers: IP address, MAC address, hostname, and a **Log in** link when a printer, IP phone, or other box is serving a web UI.

macOS 14+ · Apple Silicon

## Download

**[Download Grok IP Scanner for Mac](https://github.com/inspiretelapps/grok-ip-scanner/releases/latest)**

1. Grab `Grok-IP-Scanner-macos.zip` from the [latest release](https://github.com/inspiretelapps/grok-ip-scanner/releases/latest).
2. Unzip it and drag **Grok IP Scanner** into `/Applications`.
3. First open: right-click the app → **Open** (it is ad-hoc signed, so Gatekeeper will warn once).
4. When macOS asks to let Grok IP Scanner **find devices on local networks**, click **Allow**. Without it the scan only shows bare IP addresses (see below).

## Usage

1. Pick the interface (Wi-Fi or Ethernet). The range fills in for you (`192.168.1.0/24` or similar).
2. Click **Scan** (⌘R).
3. Read IP, hostname, MAC, and vendor in the table; select a row to see its model and open ports. After the first scan sets a baseline, devices with a MAC address never seen before get a **NEW** badge.
4. Click **Log in** or **Open** on a printer, handset, camera, or NAS to open its web UI in your browser. Double-click a row for the same action.
5. Right-click a device (or use the detail pane) to **Wake** it with Wake-on-LAN.
6. **Export CSV** (⇧⌘E) if you want the list elsewhere.

Stop a running scan with **Stop** or ⌘.

## What it finds

| Field | Source |
| --- | --- |
| IP | ICMP, ARP, TCP, Bonjour, and UPnP / SSDP |
| MAC + vendor | ARP table and IEEE OUI |
| Hostname | Reverse DNS, Bonjour / mDNS, NetBIOS, UPnP friendly name |
| Model | Bonjour TXT records (`model`, `am`, `md`, `ty`) and UPnP device descriptions |
| Login page | HTTP/HTTPS on common ports (80, 443, 631, 8080, 8443, …) and UPnP presentation URLs |

MAC addresses are only available for devices on the same Layer-2 network as this Mac.

Some phones and printers ignore ping. Grok IP Scanner also primes ARP, checks common TCP ports, and browses Bonjour so those still show up. It does not guess passwords.

Ranges wider than a `/20` are rejected (a full `/16` is tens of thousands of hosts).

## Only IPs, no MAC addresses? (or "it only works with sudo")

That is macOS **Local Network privacy** (macOS 15 Sequoia and later). Until Grok IP Scanner has the Local Network permission, macOS drops its pings and port checks and hides the ARP table from it, so a scan only turns up IP addresses that Bonjour reported, with no MAC, vendor, or login page. Programs running as root and command-line tools started from Terminal are exempt, which is why `sudo` seemed to fix it. You don't need sudo.

The app now detects this and shows a banner with an **Open Settings** button. To fix it by hand:

1. Open **System Settings › Privacy & Security › Local Network**.
2. Turn on **Grok IP Scanner**, then scan again.

If the switch is already on but the banner keeps coming back, macOS has lost track of the app. That usually happens for one of two reasons:

- **Several copies of the app.** Keep a single copy in `/Applications` and delete older builds and downloads (including any `dist/GrokIP.app` from earlier versions of the build script).
- **Ad-hoc signing.** macOS remembers the permission by code signature, and an ad-hoc signature changes on every build. `./build.sh` now signs with a real identity when it finds one. A free Apple ID is enough: Xcode › Settings › Accounts › add your Apple ID › Manage Certificates › **+ › Apple Development**. Then rebuild. To pick a specific certificate, set `GROKIP_SIGN_IDENTITY="Apple Development: you@example.com (XXXXXXXXXX)"`.

Last resort (macOS 15.5+): an administrator can exempt the whole subnet for every app, then restart:

```bash
sudo defaults write com.apple.network.local-network AllowedWiFiLocalNetworkAddresses -array "192.168.1.0/24"
sudo defaults write com.apple.network.local-network AllowedEthernetLocalNetworkAddresses -array "192.168.1.0/24"
```

## Build from source

Requires macOS 14+ and Swift 6 (Xcode or Command Line Tools).

```bash
git clone https://github.com/inspiretelapps/grok-ip-scanner.git
cd grok-ip-scanner
./build.sh
open "dist/Grok IP Scanner.app"
```

`./build.sh` runs the unit tests, compiles the app, signs it (see above), and writes `dist/Grok IP Scanner.app` plus `dist/Grok-IP-Scanner-macos.zip`. GitHub Actions runs the same script on every push.

## License

MIT. IBM Plex fonts are bundled under the SIL Open Font License (`Sources/GrokIP/Resources/Fonts/OFL.txt`). MAC vendor data comes from [nmap's mac-prefixes](https://github.com/nmap/nmap).
