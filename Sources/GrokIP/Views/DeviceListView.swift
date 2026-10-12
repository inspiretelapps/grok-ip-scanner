import AppKit
#if canImport(GrokIPCore)
import GrokIPCore
#endif
import SwiftUI

struct DeviceListView: View {
    @Bindable var session: ScanSession

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Palette.hairline).frame(height: 1)
            if session.filteredDevices.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(session.filteredDevices) { device in
                            DeviceRowView(
                                device: device,
                                selected: session.selection == device.id,
                                isNew: session.isNew(device)
                            )
                            .onTapGesture { session.selection = device.id }
                            .onTapGesture(count: 2) { session.openLogin(device) }
                            .contextMenu { rowMenu(device) }
                        }
                    }
                }
            }
        }
        .background(Palette.chassis)
    }

    private var header: some View {
        HStack(spacing: 0) {
            headerButton(.ip, width: 150, alignment: .leading)
            headerButton(.hostname, width: nil, alignment: .leading)
            headerButton(.mac, width: 158, alignment: .leading)
            headerButton(.vendor, width: 150, alignment: .leading)
            headerButton(.kind, width: 110, alignment: .leading)
            Text("Login")
                .font(Typeface.mono(10, weight: .medium))
                .foregroundStyle(Palette.muted)
                .tracking(0.8)
                .frame(width: 100, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Palette.panel)
    }

    private func headerButton(_ key: ScanSession.SortKey, width: CGFloat?, alignment: Alignment) -> some View {
        Button {
            session.toggleSort(key)
        } label: {
            HStack(spacing: 4) {
                Text(key.rawValue.uppercased())
                    .font(Typeface.mono(10, weight: .medium))
                    .tracking(0.8)
                if session.sortKey == key {
                    Image(systemName: session.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .foregroundStyle(session.sortKey == key ? Palette.keystone : Palette.muted)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
            .frame(width: width, alignment: alignment)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<8, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(i == 3 || i == 5 ? Palette.linkLED : Palette.panel)
                        .frame(width: 18, height: 12)
                }
            }
            Text(session.phase == .idle ? "Scan this LAN" : "No devices match that filter")
                .font(Typeface.sans(16, weight: .medium))
                .foregroundStyle(Palette.text)
            Text(session.phase == .idle
                 ? "Grok IP Scanner will list every host that answers — IP, MAC, hostname, and a login page when the box has a web UI."
                 : "Clear the filter to see the rest of the scan.")
                .font(Typeface.sans(12))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if session.phase == .idle {
                Button("Scan") { session.scan() }
                    .buttonStyle(KeystoneButtonStyle(emphasis: true))
                    .padding(.top, 4)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func rowMenu(_ device: Device) -> some View {
        Button("Copy IP") { session.copy(device.ip.string) }
        if let mac = device.mac {
            Button("Copy MAC") { session.copy(mac.canonical) }
        }
        if let host = device.hostname {
            Button("Copy hostname") { session.copy(host) }
        }
        if device.mac != nil, !device.isLocal {
            Divider()
            Button("Wake (Wake-on-LAN)") { session.wake(device) }
        }
        if device.primaryLogin != nil {
            Divider()
            Button(device.loginLabel) { session.openLogin(device) }
        }
    }
}

struct DeviceRowView: View {
    var device: Device
    var selected: Bool
    var isNew: Bool = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(led)
                    .frame(width: 7, height: 7)
                    .shadow(color: led.opacity(0.8), radius: 3)
                Text(device.ip.string)
                    .font(Typeface.mono(12.5))
                    .foregroundStyle(Palette.text)
                if isNew {
                    Text("NEW")
                        .font(Typeface.mono(9, weight: .medium))
                        .foregroundStyle(Palette.chassis)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 2).fill(Palette.activity))
                        .help("First time this MAC address has been seen on a scan")
                }
            }
            .frame(width: 150, alignment: .leading)

            Text(device.hostname ?? "—")
                .font(Typeface.sans(12.5))
                .foregroundStyle(device.hostname == nil ? Palette.muted : Palette.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(device.mac?.canonical ?? "—")
                .font(Typeface.mono(12))
                .foregroundStyle(device.mac == nil ? Palette.muted : Palette.text)
                .frame(width: 158, alignment: .leading)

            Text(device.vendor ?? "—")
                .font(Typeface.sans(12))
                .foregroundStyle(device.vendor == nil ? Palette.muted : Palette.text)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)

            HStack(spacing: 5) {
                Image(systemName: device.kind.symbolName)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.linkLED)
                Text(device.kind.rawValue)
                    .font(Typeface.sans(12))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
            }
            .frame(width: 110, alignment: .leading)

            loginControl
                .frame(width: 100, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(selected ? Palette.rowSelected : (hovering ? Palette.rowHover : Palette.chassis))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.hairline.opacity(0.45)).frame(height: 1)
        }
        .onHover { hovering = $0 }
    }

    private var led: Color {
        if device.isLocal { return Palette.activity }
        if device.isGateway { return Palette.pairOrange }
        return Palette.linkLED
    }

    @ViewBuilder
    private var loginControl: some View {
        if let page = device.primaryLogin {
            Button(device.loginLabel) {
                NSWorkspace.shared.open(page.url)
            }
            .buttonStyle(.plain)
            .font(Typeface.sans(12, weight: .medium))
            .foregroundStyle(Palette.login)
            .help(page.url.absoluteString)
        } else {
            Text("—")
                .font(Typeface.mono(12))
                .foregroundStyle(Palette.muted)
        }
    }
}
