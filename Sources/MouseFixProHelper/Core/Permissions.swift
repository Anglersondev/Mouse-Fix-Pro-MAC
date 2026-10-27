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

    static var allGranted: Bool { accessibility && inputMonitoring }

    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        open("Privacy_Accessibility")
    }

    static func requestInputMonitoring() {
        if !IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) {
            open("Privacy_ListenEvent")
        }
    }

    private static func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
