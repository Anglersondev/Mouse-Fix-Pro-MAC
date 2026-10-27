import MouseFixShared
import AppKit

/// Executa ações. Todo evento sintético leva `marker`, para o nosso próprio event tap ignorá-lo.
enum ActionRunner {
    static let marker: Int64 = 0x4D46_4C49 // "MFLI"

    static func perform(_ action: Action) {
        switch action {
        case .none: break
        case .missionControl: dock("com.apple.expose.awake", fallbackArg: nil)
        case .appExpose: dock("com.apple.expose.front.awake", fallbackArg: "2")
        case .showDesktop: dock("com.apple.showdesktop.awake", fallbackArg: "1")
        case .launchpad: openFirstApp(["/System/Applications/Apps.app", "/System/Applications/Launchpad.app"])
        case .spaceLeft: key(123, [.maskControl, .maskSecondaryFn, .maskNumericPad])
        case .spaceRight: key(124, [.maskControl, .maskSecondaryFn, .maskNumericPad])
        case .back: mouseClick(button: 3)
        case .forward: mouseClick(button: 4)
        case .middleClick: mouseClick(button: 2)
        case .playPause: mediaKey(16)
        case .nextTrack: mediaKey(17)
        case .previousTrack: mediaKey(18)
        case .volumeUp: mediaKey(0)
        case .volumeDown: mediaKey(1)
        case .mute: mediaKey(7)
        case .lookUp: key(2, [.maskControl, .maskCommand])
        case .screenshot: key(23, [.maskCommand, .maskShift])
        case .lockScreen: key(12, [.maskControl, .maskCommand])
        case .closeTab: key(13, .maskCommand)
        case .newTab: key(17, .maskCommand)
        case .reopenTab: key(17, [.maskCommand, .maskShift])
        case .zoomIn: key(24, .maskCommand)
        case .zoomOut: key(27, .maskCommand)
        case .shortcut(let combo): key(CGKeyCode(combo.keyCode), CGEventFlags(rawValue: combo.modifiers))
        case .openApp(let path): NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init())
        }
    }

    /// Reproduz o comportamento original de um gatilho que foi interceptado mas não tem ação para esse uso.
    static func passthrough(_ trigger: Trigger, modifiers: CGEventFlags) {
        switch trigger {
        case .button(let n): mouseClick(button: n)
        case .hid(Trigger.consumerPage, 0x224): perform(.back)
        case .hid(Trigger.consumerPage, 0x225): perform(.forward)
        case .hid(Trigger.keyboardPage, let usage):
            if let code = KeyNames.keyCode(forUsage: usage) { key(code, modifiers) }
        case .hid: break
        }
    }

    // MARK: Eventos sintéticos

    private static func mark(_ e: CGEvent) -> CGEvent {
        e.setIntegerValueField(.eventSourceUserData, value: marker)
        return e
    }

    static func key(_ code: CGKeyCode, _ flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down) else { continue }
            e.flags = flags
            mark(e).post(tap: .cghidEventTap)
        }
    }

    static func mouseClick(button: Int) {
        let location = CGEvent(source: nil)?.location ?? .zero
        let src = CGEventSource(stateID: .hidSystemState)
        let mb = CGMouseButton(rawValue: UInt32(button)) ?? .center
        for type in [CGEventType.otherMouseDown, .otherMouseUp] {
            guard let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: location, mouseButton: mb) else { continue }
            e.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
            mark(e).post(tap: .cghidEventTap)
        }
    }

    /// Teclas de mídia (NX_KEYTYPE_*), enviadas como o teclado da Apple faz.
    static func mediaKey(_ keyType: Int) {
        for down in [true, false] {
            let state = down ? 0xA00 : 0xB00
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state)),
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: 8, data1: (keyType << 16) | state, data2: -1)
            if let cg = event?.cgEvent { mark(cg).post(tap: .cghidEventTap) }
        }
    }

    // MARK: Dock / Mission Control

    private typealias CoreDockSendNotification = @convention(c) (CFString, Int32) -> Void

    /// Função interna do macOS usada pelo próprio Dock; muito mais rápida do que abrir um app.
    private static let coreDock: CoreDockSendNotification? = {
        guard let handle = dlopen(nil, RTLD_NOW), let sym = dlsym(handle, "CoreDockSendNotification") else { return nil }
        return unsafeBitCast(sym, to: CoreDockSendNotification.self)
    }()

    private static func dock(_ notification: String, fallbackArg: String?) {
        if let coreDock {
            coreDock(notification as CFString, 0)
            return
        }
        let mc = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
        let cfg = NSWorkspace.OpenConfiguration()
        if let fallbackArg { cfg.arguments = [fallbackArg] }
        NSWorkspace.shared.openApplication(at: mc, configuration: cfg)
    }

    private static func openFirstApp(_ paths: [String]) {
        guard let path = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return }
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init())
    }
}
