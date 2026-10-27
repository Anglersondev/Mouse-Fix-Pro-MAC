import CoreGraphics
import Foundation

/// Fino invólucro sobre CGEventTap. O handler devolve o evento (talvez alterado) ou nil para engoli-lo.
final class EventTap {
    typealias Handler = (CGEventType, CGEvent) -> CGEvent?

    private let mask: CGEventMask
    private let listenOnly: Bool
    private let handler: Handler
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var wantEnabled = true

    init(types: [UInt32], listenOnly: Bool = false, handler: @escaping Handler) {
        mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1)) }
        self.listenOnly = listenOnly
        self.handler = handler
    }

    var isRunning: Bool { port != nil }

    /// Cria o tap. Falha sem permissão de Acessibilidade.
    @discardableResult
    func start(enabled: Bool = true) -> Bool {
        if port != nil { return true }
        let info = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: listenOnly ? .listenOnly : .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, info in
                let tap = Unmanaged<EventTap>.fromOpaque(info!).takeUnretainedValue()
                return tap.handle(type, event)
            },
            userInfo: info)
        else { return false }
        self.port = port
        wantEnabled = enabled
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: enabled)
        return true
    }

    func stop() {
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        port = nil
        source = nil
    }

    func setEnabled(_ on: Bool) {
        wantEnabled = on
        if let port, CGEvent.tapIsEnabled(tap: port) != on { CGEvent.tapEnable(tap: port, enable: on) }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port, wantEnabled { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == ActionRunner.marker {
            return Unmanaged.passUnretained(event)
        }
        guard let out = handler(type, event) else { return nil }
        return Unmanaged.passUnretained(out)
    }
}
