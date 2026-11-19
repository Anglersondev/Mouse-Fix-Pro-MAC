import AppKit
import ApplicationServices
import IOKit.hid
import MouseFixShared

enum Permissions {
    /// Necessária para interceptar cliques e gerar eventos.
    static var accessibility: Bool { AXIsProcessTrusted() }

    /// Necessária para ler o sinal cru de mouses que se apresentam também como teclado.
    static var inputMonitoring: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    static func requestAccessibility() {
        guard !PermissionSettings.usesDeviceControlPanel else {
            openDeviceControl()
            return
        }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        open("Privacy_Accessibility")
    }

    static func requestInputMonitoring() {
        guard !PermissionSettings.usesDeviceControlPanel else {
            openDeviceControl()
            return
        }
        if !inputMonitoring {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        open("Privacy_ListenEvent")
    }

    static func openDeviceControl() {
        // Mesmo identificador de navegação, com outro nome na interface do macOS.
        open("Privacy_Accessibility")
    }

    private static func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(pane)"),
           NSWorkspace.shared.open(url) { return }
        if let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(fallback)
        }
    }
}
