import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let core = MouseCore.shared
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        core.start()
        let config = core.store.$config.receive(on: RunLoop.main)
        config.map(\.showMenuBarIcon).removeDuplicates()
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)
        config.map(\.showDockIcon).removeDuplicates()
            .sink { [weak self] _ in self?.updateDockIcon() }
            .store(in: &cancellables)

        if !Permissions.allGranted || !core.store.config.showMenuBarIcon {
            showSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        core.pointer.restore()
    }

    /// Abrir o app de novo (Finder, Spotlight, Dock) mostra os ajustes, útil quando os ícones estão ocultos.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    // MARK: Dock e barra de menus

    private func updateDockIcon() {
        let policy: NSApplication.ActivationPolicy = core.store.config.showDockIcon ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        // Trocar a política esconde a janela; traz de volta se ela estava aberta.
        if let window, window.isVisible {
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func updateStatusItem() {
        guard core.store.config.showMenuBarIcon else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: "Mouse Fix Pro")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleEnabled() {
        core.store.config.enabled.toggle()
    }

    // MARK: Janela

    @objc func showSettings() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView().environmentObject(core).environmentObject(core.store))
            let w = NSWindow(contentViewController: hosting)
            w.title = "Mouse Fix Pro"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.setContentSize(NSSize(width: 820, height: 600))
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Fechar a janela descarta toda a interface; só o núcleo continua rodando, com memória mínima.
    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        core.cancelLearning()
        core.diagnosticsOn = false
        core.clearLog()
        DispatchQueue.main.async { [weak self] in
            closing.contentViewController = nil
            closing.delegate = nil
            self?.window = nil
            URLCache.shared.removeAllCachedResponses()
            malloc_zone_pressure_relief(nil, 0)
        }
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
        menu.addItem(NSMenuItem(title: "Sair do Mouse Fix Pro", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }
}
