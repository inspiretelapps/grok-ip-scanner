import SwiftUI

/// Shown when macOS Local Network privacy is blocking the scan. Explains the fix
/// in place of the old "run it with sudo" workaround.
struct PermissionBannerView: View {
    var session: ScanSession

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 18))
                .foregroundStyle(Palette.activity)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Typeface.sans(13, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Text(message)
                    .font(Typeface.sans(12))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button("Open Settings") { session.permission.openSettings() }
                .buttonStyle(KeystoneButtonStyle(emphasis: true))
            Button("Check again") {
                session.permission.recheck()
                session.macsLikelyHidden = false
            }
            .buttonStyle(KeystoneButtonStyle())
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Palette.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Palette.activity.opacity(0.6), lineWidth: 1)
                )
        )
    }

    private var title: String {
        if session.permission.status == .denied {
            return "Grok IP Scanner needs Local Network access"
        }
        return "macOS hid the MAC addresses from this scan"
    }

    private var message: String {
        "Without it macOS blocks pings and port checks and hides the ARP table, so you only see IP addresses. "
            + "Open System Settings › Privacy & Security › Local Network, switch on Grok IP Scanner, then scan again. "
            + "If macOS is showing a prompt, click Allow. No sudo needed."
    }
}
