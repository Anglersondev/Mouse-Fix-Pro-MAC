import AppKit
import MouseFixShared

/// O Mouse Fix Pro Helper: faz todo o trabalho, sem janela e sem SwiftUI.
/// Só tem o ícone opcional na barra de menus.
final class HelperDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let core = MouseCore.shared
    private var statusItem: NSStatusItem?
    private var showingIcon: Bool?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Só uma cópia do Helper por vez (ex.: login + abrir pelo app de ajustes).
        let mine = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: IPC.helperBundleID)
            .filter { $0.processIdentifier != mine }
        if !others.isEmpty {
            NSApp.terminate(nil)
            return
        }

        core.start()
        updateStatusItem()
        let previous = core.store.onChange
        core.store.onChange = { [weak self] in
            previous?()
            self?.updateStatusItem()
        }

        // Sem permissão ainda: abre os ajustes, que mostram o passo a passo.
        if !Permissions.accessibility {
            openSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        core.pointer.restore()
    }

    // MARK: Barra de menus

    private func updateStatusItem() {
        let show = core.store.config.showMenuBarIcon
        guard show != showingIcon else { return }
        showingIcon = show
        if !show {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: "Mouse Fix Pro")
        image?.isTemplate = true
        item.button?.image = image
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let enabled = NSMenuItem(title: "Ativado", action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.target = self
        enabled.state = core.store.config.enabled ? .on : .off
        menu.addItem(enabled)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Ajustes…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Sair do Mouse Fix Pro", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func toggleEnabled() {
        core.store.config.enabled.toggle()
    }

    @objc private func openSettings() {
        let app = IPC.appURL(fromHelper: Bundle.main.bundleURL)
        NSWorkspace.shared.openApplication(at: app, configuration: .init())
    }
}
