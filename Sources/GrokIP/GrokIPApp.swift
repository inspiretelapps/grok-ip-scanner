import AppKit
import SwiftUI

@main
enum GrokIPMain {
    static func main() {
        AppFonts.register()
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = AppDelegate.shared
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let shared = AppDelegate()

    private let session = ScanSession()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()

        let root = ContentView()
            .environment(session)
            .preferredColorScheme(.dark)
            .frame(minWidth: 960, minHeight: 580)

        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Grok IP Scanner"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(red: 0.071, green: 0.102, blue: 0.141, alpha: 1)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.setContentSize(NSSize(width: 1180, height: 760))
        window.minSize = NSSize(width: 960, height: 580)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Grok IP Scanner", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Grok IP Scanner", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let scan = fileMenu.addItem(withTitle: "Scan Network", action: #selector(scanNetwork), keyEquivalent: "r")
        scan.target = self
        let stop = fileMenu.addItem(withTitle: "Stop Scan", action: #selector(stopScan), keyEquivalent: ".")
        stop.target = self
        fileMenu.addItem(.separator())
        let export = fileMenu.addItem(withTitle: "Export CSV…", action: #selector(exportCSV), keyEquivalent: "e")
        export.keyEquivalentModifierMask = [.command, .shift]
        export.target = self
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func scanNetwork() {
        session.scan()
    }

    @objc private func stopScan() {
        session.stop()
    }

    @objc private func exportCSV() {
        session.exportCSV()
    }
}
