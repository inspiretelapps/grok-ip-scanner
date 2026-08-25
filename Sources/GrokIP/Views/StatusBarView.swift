import SwiftUI

struct StatusBarView: View {
    var session: ScanSession

    var body: some View {
        HStack(spacing: 16) {
            statusDot
            Text(statusText)
                .font(Typeface.mono(11))
                .foregroundStyle(Palette.muted)
            Spacer()
            metric("\(session.devices.count)", "live")
            metric("\(session.loginCount)", "login pages")
            metric(time, "elapsed")
            Button("Export CSV") { session.exportCSV() }
                .buttonStyle(.plain)
                .font(Typeface.sans(11, weight: .medium))
                .foregroundStyle(session.devices.isEmpty ? Palette.muted : Palette.login)
                .disabled(session.devices.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Palette.panel)
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.hairline).frame(height: 1)
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 7, height: 7)
    }

    private var dotColor: Color {
        switch session.phase {
        case .scanning: Palette.activity
        case .complete: Palette.live
        case .failed: Palette.stop
        case .idle: Palette.hairline
        }
    }

    private var statusText: String {
        if let error = session.errorMessage, session.phase == .failed {
            return error
        }
        if session.isScanning {
            return "\(session.progressPhase)  \(session.completed)/\(max(session.total, 1))"
        }
        if session.phase == .complete {
            return "Scan complete"
        }
        return "Ready"
    }

    private var time: String {
        if session.elapsed < 10 {
            return String(format: "%.1fs", session.elapsed)
        }
        return String(format: "%.0fs", session.elapsed)
    }

    private func metric(_ value: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(value)
                .font(Typeface.mono(11, weight: .medium))
                .foregroundStyle(Palette.keystone)
            Text(label)
                .font(Typeface.sans(11))
                .foregroundStyle(Palette.muted)
        }
    }
}
