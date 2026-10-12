import AppKit
#if canImport(GrokIPCore)
import GrokIPCore
#endif
import SwiftUI

struct ContentView: View {
    @Environment(ScanSession.self) private var session

    var body: some View {
        @Bindable var session = session
        VStack(spacing: 0) {
            ScanHeaderView(session: session)
            VStack(spacing: 12) {
                if session.showsPermissionBanner {
                    PermissionBannerView(session: session)
                }
                PatchPanelView(
                    range: ScanRange.parse(session.rangeText),
                    live: session.liveIPs,
                    selected: session.selectedDevice?.ip.raw,
                    scanning: session.isScanning,
                    elapsed: session.elapsed,
                    onSelect: { ip in
                        session.selection = ip.string
                    }
                )
                HSplitView {
                    DeviceListView(session: session)
                        .frame(minWidth: 640)
                    if let device = session.selectedDevice {
                        DeviceDetailView(
                            device: device,
                            onOpen: { session.openLogin(device) },
                            onCopy: { session.copy($0) },
                            onWake: { session.wake(device) }
                        )
                        .frame(minWidth: 260, idealWidth: 300)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            StatusBarView(session: session)
        }
        .background(Palette.chassis)
        .onAppear { session.reloadInterfaces() }
        .focusable()
        .onCopyCommand {
            if let device = session.selectedDevice {
                return [NSItemProvider(object: device.ip.string as NSString)]
            }
            return []
        }
    }
}
