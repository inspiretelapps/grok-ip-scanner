#if canImport(GrokIPCore)
import GrokIPCore
#endif
import SwiftUI

struct DeviceDetailView: View {
    var device: Device
    var onOpen: () -> Void
    var onCopy: (String) -> Void
    var onWake: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: device.kind.symbolName)
                        .font(.system(size: 18))
                        .foregroundStyle(Palette.activity)
                        .frame(width: 28, height: 28)
                        .background(Palette.well)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.displayName)
                            .font(Typeface.sans(16, weight: .semibold))
                            .foregroundStyle(Palette.text)
                            .textSelection(.enabled)
                        Text(device.kind.rawValue)
                            .font(Typeface.mono(11))
                            .foregroundStyle(Palette.muted)
                    }
                }

                fact("IP", device.ip.string, copyable: true)
                fact("Hostname", device.hostname ?? "Not resolved")
                fact("MAC", device.mac?.canonical ?? "Not on this subnet yet", copyable: device.mac != nil)
                fact("Vendor", device.vendor ?? "Unknown")
                if let model = device.model {
                    fact("Model", model)
                }
                if let rtt = device.rttMilliseconds {
                    fact("Ping", String(format: "%.1f ms", rtt))
                }
                if let onWake, device.mac != nil, !device.isLocal {
                    Button("Wake (Wake-on-LAN)") { onWake() }
                        .buttonStyle(KeystoneButtonStyle())
                        .help("Send a magic packet to this MAC address")
                }

                if !device.services.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        label("Open ports")
                        FlowChips(items: device.services.map { "\($0.name) \($0.port)" })
                    }
                }

                if let page = device.primaryLogin {
                    VStack(alignment: .leading, spacing: 8) {
                        label("Login page")
                        Text(page.title ?? device.webTitle ?? "Web interface")
                            .font(Typeface.sans(13))
                            .foregroundStyle(Palette.text)
                        Text(page.url.absoluteString)
                            .font(Typeface.mono(11))
                            .foregroundStyle(Palette.login)
                            .textSelection(.enabled)
                        Button(device.loginLabel) { onOpen() }
                            .buttonStyle(KeystoneButtonStyle(emphasis: true))
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        label("Login page")
                        Text("No web interface answered on the usual ports.")
                            .font(Typeface.sans(12))
                            .foregroundStyle(Palette.muted)
                    }
                }
            }
            .padding(16)
        }
        .background(Palette.panel)
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Typeface.mono(10, weight: .medium))
            .foregroundStyle(Palette.muted)
            .tracking(1.1)
    }

    private func fact(_ title: String, _ value: String, copyable: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            label(title)
            HStack {
                Text(value)
                    .font(Typeface.mono(12.5))
                    .foregroundStyle(Palette.text)
                    .textSelection(.enabled)
                if copyable {
                    Button("Copy") { onCopy(value) }
                        .buttonStyle(.plain)
                        .font(Typeface.sans(11, weight: .medium))
                        .foregroundStyle(Palette.login)
                }
            }
        }
    }
}

struct FlowChips: View {
    var items: [String]

    var body: some View {
        FlexibleChipWrap(items: items)
    }
}

private struct FlexibleChipWrap: View {
    var items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { item in
                        ServiceChip(text: item)
                    }
                }
            }
        }
    }

    private var rows: [[String]] {
        var result: [[String]] = []
        var current: [String] = []
        var width = 0
        for item in items {
            let add = item.count + 4
            if width + add > 28, !current.isEmpty {
                result.append(current)
                current = [item]
                width = add
            } else {
                current.append(item)
                width += add
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
