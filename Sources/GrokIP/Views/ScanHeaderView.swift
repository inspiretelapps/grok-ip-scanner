import SwiftUI

struct ScanHeaderView: View {
    @Bindable var session: ScanSession

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(session.isScanning ? Palette.activity : Palette.linkLED)
                    .frame(width: 9, height: 9)
                    .shadow(color: (session.isScanning ? Palette.activity : Palette.linkLED).opacity(0.7), radius: 4)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Grok IP Scanner")
                        .font(Typeface.sans(16, weight: .semibold))
                        .foregroundStyle(Palette.keystone)
                    Text("LAN scanner for macOS")
                        .font(Typeface.mono(10))
                        .foregroundStyle(Palette.muted)
                }
            }
            .padding(.leading, 62)

            Spacer(minLength: 12)

            Picker("Interface", selection: Binding(
                get: { session.selectedInterfaceID },
                set: { session.applyInterface($0) }
            )) {
                ForEach(session.snapshot.interfaces) { iface in
                    Text(iface.menuLabel).tag(Optional(iface.id))
                }
            }
            .labelsHidden()
            .frame(minWidth: 220, maxWidth: 280)
            .disabled(session.isScanning)

            TextField("192.168.1.0/24", text: $session.rangeText)
                .textFieldStyle(.plain)
                .font(Typeface.mono(13))
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(minWidth: 170, maxWidth: 220)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Palette.well)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(Palette.hairline, lineWidth: 1)
                        )
                )
                .disabled(session.isScanning)
                .onSubmit { session.scan() }

            if session.isScanning {
                Button("Stop") { session.stop() }
                    .buttonStyle(KeystoneButtonStyle(destructive: true))
                    .keyboardShortcut(".", modifiers: .command)
            } else {
                Button("Scan") { session.scan() }
                    .buttonStyle(KeystoneButtonStyle(emphasis: true))
                    .keyboardShortcut("r", modifiers: .command)
            }

            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundStyle(Palette.muted)
                    .font(.system(size: 11))
                TextField("Filter", text: $session.filterText)
                    .textFieldStyle(.plain)
                    .font(Typeface.sans(12))
                    .foregroundStyle(Palette.text)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(width: 180)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Palette.well)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(Palette.hairline, lineWidth: 1)
                    )
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}
