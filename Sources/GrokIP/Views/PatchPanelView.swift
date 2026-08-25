#if canImport(GrokIPCore)
import GrokIPCore
#endif
import SwiftUI

struct PatchPanelView: View {
    var range: ScanRange?
    var live: Set<UInt32>
    var selected: UInt32?
    var scanning: Bool
    var elapsed: TimeInterval
    var onSelect: (IPv4Address) -> Void

    private let columns = 32
    private let rows = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PATCH")
                    .font(Typeface.mono(10, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .tracking(1.4)
                Spacer()
                Text(range?.description ?? "—")
                    .font(Typeface.mono(11))
                    .foregroundStyle(Palette.keystoneDim)
            }

            GeometryReader { geo in
                let gap: CGFloat = 3
                let cellW = max((geo.size.width - gap * CGFloat(columns - 1)) / CGFloat(columns), 4)
                let cellH = max((geo.size.height - gap * CGFloat(rows - 1)) / CGFloat(rows), 4)
                let sweep = scanning ? Int((elapsed * 18).truncatingRemainder(dividingBy: 256)) : -1

                VStack(spacing: gap) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: gap) {
                            ForEach(0..<columns, id: \.self) { col in
                                let index = row * columns + col
                                cell(index: index, sweep: sweep)
                                    .frame(width: cellW, height: cellH)
                            }
                        }
                    }
                }
            }
            .frame(height: 88)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Palette.well)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Palette.hairline, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func cell(index: Int, sweep: Int) -> some View {
        let address = address(for: index)
        let isLive = address.map { live.contains($0.raw) } ?? false
        let isSelected = address?.raw == selected
        let inSweep = scanning && index == sweep
        let unused = address == nil

        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(fillColor(isLive: isLive, inSweep: inSweep, unused: unused, isSelected: isSelected))
            .overlay(
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .stroke(isSelected ? Palette.keystone : Color.clear, lineWidth: 1)
            )
            .shadow(color: isLive ? Palette.linkLED.opacity(0.35) : .clear, radius: isLive ? 2 : 0)
            .help(address?.string ?? "")
            .onTapGesture {
                if let address { onSelect(address) }
            }
    }

    private func fillColor(isLive: Bool, inSweep: Bool, unused: Bool, isSelected: Bool) -> Color {
        if unused { return Palette.chassis.opacity(0.5) }
        if isLive { return Palette.linkLED }
        if inSweep { return Palette.activity }
        if isSelected { return Palette.pairOrange.opacity(0.7) }
        return Palette.panel
    }

    private func address(for index: Int) -> IPv4Address? {
        guard let range, range.isOctetGrid else {
            guard let range else { return nil }
            let hosts = range.hostCount
            guard index < hosts else { return nil }
            return IPv4Address(raw: range.start.raw + UInt32(index))
        }
        let base = range.start.raw & 0xFFFF_FF00
        let ip = IPv4Address(raw: base + UInt32(index))
        return range.contains(ip) ? ip : nil
    }
}
