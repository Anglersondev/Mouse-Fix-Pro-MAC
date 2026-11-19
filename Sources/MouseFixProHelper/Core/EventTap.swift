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

    /// Cria o tap. Falha sem permissão de Acessibilidade.
    @discardableResult
    func start() -> Bool {
        if let port, CFMachPortIsValid(port) {
            setEnabled(true)
            if CGEvent.tapIsEnabled(tap: port) { return true }
        }
        stop()
        let info = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: listenOnly ? .listenOnly : .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<EventTap>.fromOpaque(info).takeUnretainedValue()
                return tap.handle(type, event)
            },
            userInfo: info)
        else { return false }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            return false
        }
        self.port = port
        self.source = source
        wantEnabled = true
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return CGEvent.tapIsEnabled(tap: port)
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port { CFMachPortInvalidate(port) }
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
        return out === event ? Unmanaged.passUnretained(out) : Unmanaged.passRetained(out)
    }
}
