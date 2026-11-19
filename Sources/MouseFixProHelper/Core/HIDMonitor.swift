import AppKit
import MouseFixShared
import CoreGraphics
import Foundation
import IOKit.hid

/// Lê os valores HID dos mouses conectados, numa fila serial própria.
///
/// É isto que resolve mouses como o UGREEN vertical: quando o botão lateral chega como tecla de
/// mídia ou atalho de teclado, o macOS não gera clique de mouse nenhum, então um event tap sozinho
/// não consegue distinguir o botão do mouse de uma tecla de verdade. Aqui a gente vê de qual
/// dispositivo veio o sinal, avisa o motor de botões e procura um evento Quartz correspondente.
final class HIDMonitor {
    struct Device: Identifiable, Hashable {
        let id: UInt
        let name: String
        let transport: String
        let vendorID: Int
        let productID: Int
    }

    /// Chamado na main thread: (gatilho, apertado, modificadores que o mouse mandou junto).
    var onTrigger: ((Trigger, Bool, CGEventFlags) -> Void)?
    /// Linhas de diagnóstico, na main thread. Só chamado com o diagnóstico ligado.
    var onRaw: ((String) -> Void)?
    var onDevicesChanged: (([Device]) -> Void)?
    var onTriggerCancelled: ((Trigger) -> Void)?

    // Protegidos por `lock` (lidos pelo event tap na main thread).
    private let lock = NSLock()
    private var mapped: Set<Trigger> = []
    private var learning = false
    private var diagnostics = false
    private var correlation = HIDCorrelation()

    // Propriedade exclusiva da fila HID.
    private let queue = DispatchQueue(label: "MouseFixPro.HID", qos: .userInitiated)
    private var available = false
    private var cancelling = false
    private var devices: [UInt: Device] = [:]
    private var modifiers: [UInt: CGEventFlags] = [:]
    private var held: [UInt: Set<Trigger>] = [:]
    private var manager: IOHIDManager?

    private static let nanosecondsPerTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom)
    }()

    func setAvailable(_ on: Bool) {
        queue.async { [self] in
            available = on
            if on {
                start()
            } else if let manager, !cancelling {
                cancelling = true
                IOHIDManagerCancel(manager)
            }
        }
    }

    private func start() {
        guard available, manager == nil else { return }
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [[String: Int]] = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Pointer],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(m, matching as CFArray)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(m, { ctx, result, _, device in
            guard result == kIOReturnSuccess, let ctx else { return }
            Unmanaged<HIDMonitor>.fromOpaque(ctx).takeUnretainedValue().added(device)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(m, { ctx, _, _, device in
            guard let ctx else { return }
            Unmanaged<HIDMonitor>.fromOpaque(ctx).takeUnretainedValue().removed(device)
        }, ctx)
        IOHIDManagerRegisterInputValueCallback(m, { ctx, result, _, value in
            guard result == kIOReturnSuccess, let ctx else { return }
            Unmanaged<HIDMonitor>.fromOpaque(ctx).takeUnretainedValue().input(value)
        }, ctx)

        IOHIDManagerSetDispatchQueue(m, queue)
        IOHIDManagerSetCancelHandler(m) { [self] in
            guard let manager else { return }
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            self.manager = nil
            cancelling = false
            let cancelled = Set(held.values.flatMap { $0 })
            held.removeAll()
            modifiers.removeAll()
            devices.removeAll()
            lock.lock()
            correlation = HIDCorrelation()
            lock.unlock()
            publishDevices()
            publishCancelled(cancelled)
            start()
        }
        manager = m
        IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerActivate(m)
    }

    // MARK: Estado compartilhado com a main thread

    func setMapped(_ triggers: Set<Trigger>) {
        lock.lock()
        mapped = triggers
        lock.unlock()
    }

    func setLearning(_ on: Bool) {
        lock.lock(); learning = on; lock.unlock()
    }

    func setDiagnostics(_ on: Bool) {
        lock.lock(); diagnostics = on; lock.unlock()
    }

    /// O evento passa intacto se não houver um sinal HID correspondente já observado.
    func shouldSuppress(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let signal: HIDCorrelation.Signal
        let pressed: Bool
        switch type {
        case .keyDown, .keyUp:
            signal = .key(event.getIntegerValueField(.keyboardEventKeycode))
            pressed = type == .keyDown
        default:
            switch type.rawValue {
            case 14:
                guard let media = Self.mediaKey(event) else { return false }
                signal = .media(media.code)
                pressed = media.pressed
            case 31:
                signal = .swipe
                pressed = true
            default:
                return false
            }
        }
        lock.lock()
        defer { lock.unlock() }
        return correlation.consume(signal, pressed: pressed, time: event.timestamp)
    }

    static func mediaKey(_ event: CGEvent) -> (code: Int, pressed: Bool)? {
        guard let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return nil }
        let state = (ns.data1 & 0xFF00) >> 8
        guard state == 0x0A || state == 0x0B else { return nil }
        return ((ns.data1 & 0xFFFF_0000) >> 16, state == 0x0A)
    }

    // MARK: Callbacks HID

    private func prop(_ d: IOHIDDevice, _ key: String) -> Any? {
        IOHIDDeviceGetProperty(d, key as CFString)
    }

    private func added(_ device: IOHIDDevice) {
        let id = CFHash(device)
        guard (prop(device, "Built-In") as? Bool) != true else { return }
        devices[id] = Device(
            id: id,
            name: prop(device, kIOHIDProductKey) as? String ?? L("Mouse sem nome", "Unnamed mouse"),
            transport: prop(device, kIOHIDTransportKey) as? String ?? "?",
            vendorID: prop(device, kIOHIDVendorIDKey) as? Int ?? 0,
            productID: prop(device, kIOHIDProductIDKey) as? Int ?? 0)
        publishDevices()
    }

    private func removed(_ device: IOHIDDevice) {
        let id = CFHash(device)
        guard devices.removeValue(forKey: id) != nil else { return }
        modifiers[id] = nil
        if let triggers = held.removeValue(forKey: id) {
            publishCancelled(triggers.filter { trigger in !held.values.contains { $0.contains(trigger) } })
        }
        publishDevices()
    }

    private func publishCancelled(_ triggers: Set<Trigger>) {
        guard !triggers.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            for trigger in triggers { self?.onTriggerCancelled?(trigger) }
        }
    }

    private func publishDevices() {
        let list = devices.values.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
        DispatchQueue.main.async { [weak self] in self?.onDevicesChanged?(list) }
    }

    private func input(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let page = IOHIDElementGetUsagePage(element)
        if page == UInt32(kHIDPage_GenericDesktop) { return } // movimento e roda
        let id = CFHash(IOHIDElementGetDevice(element))
        guard let device = devices[id] else { return }
        let usage = IOHIDElementGetUsage(element)
        let v = IOHIDValueGetIntegerValue(value)
        let pressed = v != 0

        switch page {
        case UInt32(kHIDPage_Button):
            raw(device, String(format: L("HID  botão %u %@  (página 0x09, o macOS entrega como clique)", "HID  button %u %@  (page 0x09, macOS delivers it as a click)"), usage, pressed ? "↓" : "↑"))
            return
        case Trigger.keyboardPage:
            if let flag = KeyNames.modifierFlag(forUsage: usage) {
                if pressed {
                    modifiers[id, default: []].insert(flag)
                } else {
                    modifiers[id]?.remove(flag)
                }
                raw(device, L("HID  modificador", "HID  modifier") + " \(KeyNames.symbols(for: flag)) \(pressed ? "↓" : "↑")  (" + L("página", "page") + " 0x07)")
                return
            }
            if usage < 4 || usage > 0xFFFF { return }
        case Trigger.consumerPage:
            if usage == 0x238 { return } // AC Pan (roda horizontal)
        default:
            raw(device, String(format: L("HID  página 0x%04X uso 0x%04X valor %ld  (sinal do fabricante)", "HID  page 0x%04X usage 0x%04X value %ld  (manufacturer signal)"), page, usage, v))
            return
        }

        let trigger = Trigger.hid(page: page, usage: usage)
        raw(device, String(format: L("HID  página 0x%04X uso 0x%04X %@  → %@", "HID  page 0x%04X usage 0x%04X %@  → %@"), page, usage, pressed ? "↓" : "↑", trigger.title))

        let wasHeld = held[id]?.contains(trigger) ?? false
        guard pressed != wasHeld else { return }

        lock.lock()
        if pressed && !learning && !mapped.contains(trigger) {
            lock.unlock()
            return
        }
        let time = UInt64(Double(IOHIDValueGetTimeStamp(value)) * Self.nanosecondsPerTick)
        correlation.record(trigger, pressed: pressed, time: time)
        lock.unlock()

        if pressed {
            let alreadyHeld = held.values.contains { $0.contains(trigger) }
            held[id, default: []].insert(trigger)
            guard !alreadyHeld else { return }
        } else {
            held[id]?.remove(trigger)
            if held[id]?.isEmpty == true { held[id] = nil }
            guard !held.values.contains(where: { $0.contains(trigger) }) else { return }
        }

        let mods = modifiers[id] ?? []
        DispatchQueue.main.async { [weak self] in self?.onTrigger?(trigger, pressed, mods) }
    }

    private func raw(_ device: Device, _ text: @autoclosure () -> String) {
        lock.lock()
        let on = diagnostics
        lock.unlock()
        guard on else { return }
        let line = "[\(device.name)] \(text())"
        DispatchQueue.main.async { [weak self] in self?.onRaw?(line) }
    }
}
