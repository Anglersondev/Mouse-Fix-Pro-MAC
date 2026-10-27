import AppKit
import Combine
import MouseFixShared
import ServiceManagement
import SwiftUI

/// O app de ajustes. Só existe enquanto a janela está aberta: fechou, ele sai da memória
/// e o Mouse Fix Pro Helper continua fazendo o trabalho.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ConfigStore()
    private let link = HelperLink()
    private var window: NSWindow?
    private var cancellables: Set<AnyCancellable> = []
    private var launchedAtLogin = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // O evento de abertura só existe durante o lançamento; diz se foi o macOS abrindo no login.
        let event = NSAppleEventManager.shared().currentAppleEvent
        launchedAtLogin = event?.eventID == AEEventID(kAEOpenApplication)
            && event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
        // Não reabrir a janela sozinha depois de reiniciar o Mac.
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateLoginItem()
        if store.config.enabled { link.launchHelper() }

        // Ao ligar o Mac só o Helper deve rodar, escondido. A janela fica para quando você abrir o app.
        if launchedAtLogin {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }
            return
        }

        store.$config.map(\.showDockIcon).removeDuplicates().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateDockIcon() }
            .store(in: &cancellables)
        store.$config.map(\.enabled).removeDuplicates().dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] on in if on { self?.link.launchHelper() } }
            .store(in: &cancellables)
        showSettings()
        link.startPolling()
    }

    /// Versões de teste antigas registravam a janela de ajustes para abrir no login.
    /// Agora quem abre no login é só o Helper, sem janela.
    private func migrateLoginItem() {
        guard SMAppService.mainApp.status == .enabled else { return }
        try? SMAppService.mainApp.unregister()
        try? link.setLaunchAtLogin(true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        link.cancelLearning()
        link.diagnosticsOn = false
    }

    private func updateDockIcon() {
        let policy: NSApplication.ActivationPolicy = store.config.showDockIcon ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        // Trocar a política pode esconder a janela; traz de volta.
        DispatchQueue.main.async { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }

    private func showSettings() {
        if window == nil {
            let root = SettingsView().environmentObject(link).environmentObject(store)
            let w = NSWindow(contentViewController: NSHostingController(rootView: root))
            w.title = "Mouse Fix Pro"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.isRestorable = false
            w.setContentSize(NSSize(width: 820, height: 600))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
