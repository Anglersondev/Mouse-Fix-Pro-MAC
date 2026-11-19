import AppKit
import ApplicationServices
import IOKit.hid

enum Permissions {
    /// Necessária para interceptar cliques e gerar eventos.
    static var accessibility: Bool { AXIsProcessTrusted() }

    /// Necessária para ler o sinal cru de mouses que se apresentam também como teclado.
    static var inputMonitoring: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        open("Privacy_Accessibility")
    }

    static func requestInputMonitoring() {
        if !inputMonitoring {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        open("Privacy_ListenEvent")
    }

    private static func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(pane)"),
           NSWorkspace.shared.open(url) { return }
        if let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(fallback)
        }
    }
}
