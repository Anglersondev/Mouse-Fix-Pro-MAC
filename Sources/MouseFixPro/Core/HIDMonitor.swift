import CoreGraphics
import Foundation
import IOKit.hid

/// Lê os relatórios HID crus dos mouses conectados, numa thread própria.
///
/// É isto que resolve mouses como o UGREEN vertical: quando o botão lateral chega como tecla de
/// mídia ou atalho de teclado, o macOS não gera clique de mouse nenhum, então um event tap sozinho
/// não consegue distinguir o botão do mouse de uma tecla de verdade. Aqui a gente vê de qual
/// dispositivo veio o sinal, avisa o motor de botões e marca uma janela de tempo em que o evento
/// de teclado/mídia/gesto gerado pelo macOS deve ser engolido.
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

    private(set) var openResult: IOReturn = kIOReturnSuccess

    // Protegidos por `lock` (lidos pelo event tap na main thread).
    private let lock = NSLock()
    private var mapped: Set<Trigger> = []
    private var mappedKeyCodes: Set<Int64> = []
    private var hasConsumerMapping = false
    private var learning = false
    private var diagnostics = false
    private var down: Set<Trigger> = []
    private var lastRelease: TimeInterval = 0

    // Só usados na thread HID.
    private var modifiers: CGEventFlags = []
    private var devices: [UInt: Device] = [:]
    private var ignored: Set<UInt> = []
    private var manager: IOHIDManager?
    private var runLoop: CFRunLoop?
    private var thread: Thread?

    /// Quanto tempo depois de soltar o botão ainda engolimos o evento traduzido pelo macOS.
    private let releaseGrace: TimeInterval = 0.12

    // MARK: Ciclo de vida

    func start() {
        guard thread == nil else { return }
        let t = Thread { [weak self] in self?.run() }
        t.name = "MouseFixPro.HID"
        t.qualityOfService = .userInteractive
        thread = t
        t.start()
    }

    func restart() {
        if let runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [weak self] in
                if let m = self?.manager { IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone)) }
                CFRunLoopStop(CFRunLoopGetCurrent())
            }
            CFRunLoopWakeUp(runLoop)
        }
        thread = nil
        runLoop = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.start() }
    }

    private func run() {
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [[String: Int]] = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Pointer],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(m, matching as CFArray)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(m, { ctx, _, _, device in
            Unmanaged<HIDMonitor>.fromOpaque(ctx!).takeUnretainedValue().added(device)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(m, { ctx, _, _, device in
            Unmanaged<HIDMonitor>.fromOpaque(ctx!).takeUnretainedValue().removed(device)
        }, ctx)
        IOHIDManagerRegisterInputValueCallback(m, { ctx, _, _, value in
            Unmanaged<HIDMonitor>.fromOpaque(ctx!).takeUnretainedValue().input(value)
        }, ctx)

        let rl = CFRunLoopGetCurrent()!
        IOHIDManagerScheduleWithRunLoop(m, rl, CFRunLoopMode.defaultMode.rawValue)
        openResult = IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = m
        runLoop = rl
        CFRunLoopRun()
        IOHIDManagerUnscheduleFromRunLoop(m, rl, CFRunLoopMode.defaultMode.rawValue)
    }

    // MARK: Estado compartilhado com a main thread

    func setMapped(_ triggers: Set<Trigger>) {
        var codes: Set<Int64> = []
        var consumer = false
        for case let .hid(page, usage) in triggers {
            if page == Trigger.keyboardPage, let code = KeyNames.keyCode(forUsage: usage) { codes.insert(Int64(code)) }
            if page == Trigger.consumerPage { consumer = true }
        }
        lock.lock()
        mapped = triggers
        mappedKeyCodes = codes
        hasConsumerMapping = consumer
        lock.unlock()
    }

    func setLearning(_ on: Bool) {
        lock.lock(); learning = on; lock.unlock()
    }

    func setDiagnostics(_ on: Bool) {
        lock.lock(); diagnostics = on; lock.unlock()
    }

    /// Decide se um evento de teclado, mídia ou gesto foi gerado pelo botão do mouse e deve sumir.
    /// Chamado pelo event tap na main thread.
    func shouldSuppress(_ type: CGEventType, _ event: CGEvent) -> Bool {
        lock.lock()
        let anything = learning || !mapped.isEmpty
        let canWait: Bool
        switch type.rawValue {
        case CGEventType.keyDown.rawValue, CGEventType.keyUp.rawValue:
            canWait = learning || mappedKeyCodes.contains(event.getIntegerValueField(.keyboardEventKeycode))
        case 14: // NSSystemDefined: teclas de mídia
            canWait = learning || hasConsumerMapping
        case 31: // NSEventTypeSwipe: alguns mouses mandam Voltar/Avançar como gesto
            canWait = anything
        default:
            canWait = false
        }
        lock.unlock()
        guard anything else { return false }
        if isActive() { return true }
        guard canWait else { return false }
        // O relatório HID e o evento traduzido correm por caminhos diferentes; espera um pouco o HID.
        for _ in 0 ..< 12 {
            usleep(1000)
            if isActive() { return true }
        }
        return false
    }

    private func isActive() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !down.isEmpty || ProcessInfo.processInfo.systemUptime - lastRelease < releaseGrace
    }

    // MARK: Callbacks HID (thread HID)

    private func prop(_ d: IOHIDDevice, _ key: String) -> Any? {
        IOHIDDeviceGetProperty(d, key as CFString)
    }

    private func added(_ device: IOHIDDevice) {
        let id = CFHash(device)
        if (prop(device, "Built-In") as? Bool) == true {
            ignored.insert(id)
            return
        }
        devices[id] = Device(
            id: id,
            name: prop(device, kIOHIDProductKey) as? String ?? "Mouse sem nome",
            transport: prop(device, kIOHIDTransportKey) as? String ?? "?",
            vendorID: prop(device, kIOHIDVendorIDKey) as? Int ?? 0,
            productID: prop(device, kIOHIDProductIDKey) as? Int ?? 0)
        publishDevices()
    }

    private func removed(_ device: IOHIDDevice) {
        let id = CFHash(device)
        ignored.remove(id)
        devices[id] = nil
        publishDevices()
    }

    private func publishDevices() {
        let list = devices.values.sorted { $0.name < $1.name }
        DispatchQueue.main.async { [weak self] in self?.onDevicesChanged?(list) }
    }

    private func input(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        if ignored.contains(CFHash(device)) { return }

        let page = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let v = IOHIDValueGetIntegerValue(value)
        let pressed = v != 0

        switch page {
        case UInt32(kHIDPage_GenericDesktop):
            return // movimento e roda
        case UInt32(kHIDPage_Button):
            raw(device, String(format: "HID  botão %u %@  (página 0x09, o macOS entrega como clique)", usage, pressed ? "↓" : "↑"))
            return
        case Trigger.keyboardPage:
            if let flag = KeyNames.modifierFlag(forUsage: usage) {
                if pressed { modifiers.insert(flag) } else { modifiers.remove(flag) }
                raw(device, "HID  modificador \(KeyNames.symbols(for: flag)) \(pressed ? "↓" : "↑")  (página 0x07)")
                return
            }
            if usage < 4 || usage > 0xFFFF { return }
        case Trigger.consumerPage:
            if usage == 0x238 { return } // AC Pan (roda horizontal)
        default:
            raw(device, String(format: "HID  página 0x%04X uso 0x%04X valor %ld  (sinal do fabricante)", page, usage, v))
            return
        }

        let trigger = Trigger.hid(page: page, usage: usage)
        raw(device, String(format: "HID  página 0x%04X uso 0x%04X %@  → %@", page, usage, pressed ? "↓" : "↑", trigger.title))

        lock.lock()
        var notify = false
        if pressed {
            if learning || mapped.contains(trigger) {
                notify = down.insert(trigger).inserted
            }
        } else if down.remove(trigger) != nil {
            lastRelease = ProcessInfo.processInfo.systemUptime
            notify = true
        }
        lock.unlock()

        guard notify else { return }
        let mods = modifiers
        DispatchQueue.main.async { [weak self] in self?.onTrigger?(trigger, pressed, mods) }
    }

    private func raw(_ device: IOHIDDevice, _ text: String) {
        lock.lock()
        let on = diagnostics
        lock.unlock()
        guard on else { return }
        let name = prop(device, kIOHIDProductKey) as? String ?? "mouse"
        DispatchQueue.main.async { [weak self] in self?.onRaw?("[\(name)] \(text)") }
    }
}
