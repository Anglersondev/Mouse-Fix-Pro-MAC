import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let core = MouseCore.shared
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var cancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        core.start()
        updateStatusItem()
        cancellable = core.store.$config
            .map(\.showMenuBarIcon)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }

        if !Permissions.allGranted || !core.store.config.showMenuBarIcon {
            showSettings()
        }
    }

    /// Abrir o app de novo (Finder, Spotlight) mostra os ajustes, útil quando o ícone da barra está oculto.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    // MARK: Barra de menus

    private func updateStatusItem() {
        guard core.store.config.showMenuBarIcon else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: "MouseFix Lite")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleEnabled() {
        core.store.config.enabled.toggle()
    }

    @objc func showSettings() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView().environmentObject(core).environmentObject(core.store))
            let w = NSWindow(contentViewController: hosting)
            w.title = "MouseFix Lite"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.setContentSize(NSSize(width: 820, height: 600))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let enabled = NSMenuItem(title: "Ativado", action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.target = self
        enabled.state = core.store.config.enabled ? .on : .off
        menu.addItem(enabled)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Ajustes…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Sair do MouseFix Lite", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }
}
