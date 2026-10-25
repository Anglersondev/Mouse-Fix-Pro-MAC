import AppKit
import MouseFixShared

/// Liga as peças: event taps, monitor HID, motor de botões, rolagem e ponteiro.
///
/// Três taps, cada um ligado só quando precisa:
/// - `buttonTap`: botões extras e rodinha. Sempre ligado.
/// - `keyTap`: teclado, teclas de mídia e gestos. Só quando algum botão do mouse chega como
///   tecla/mídia (ou no modo de detecção), para não passar cada tecla digitada pelo app à toa.
/// - `motionTap`: movimento do ponteiro. Só enquanto um botão com gesto de arrastar está apertado.
final class MouseCore {
    static let shared = MouseCore()

    let store = ConfigStore()
    let hid = HIDMonitor()
    let scroll = ScrollEngine()
    let pointer = PointerManager()
    let buttons: ButtonEngine

    private(set) var running = false
    private(set) var learning = false
    private(set) var devices: [HIDMonitor.Device] = []

    var diagnosticsOn = false {
        didSet {
            hid.setDiagnostics(diagnosticsOn)
            updateKeyTap()
        }
    }

    private var buttonTap: EventTap!
    private var keyTap: EventTap!
    private var motionTap: EventTap!
    private var hadInputMonitoring = Permissions.inputMonitoring
    private var commandObserver: NSObjectProtocol?

    private init() {
        buttons = ButtonEngine(store: store)

        buttonTap = EventTap(types: [
            CGEventType.otherMouseDown.rawValue, CGEventType.otherMouseUp.rawValue,
            CGEventType.otherMouseDragged.rawValue, CGEventType.scrollWheel.rawValue,
        ]) { [unowned self] type, event in self.handleButtonTap(type, event) }

        keyTap = EventTap(types: [
            CGEventType.keyDown.rawValue, CGEventType.keyUp.rawValue,
            14, 29, 30, 31, 32, // tecla de sistema/mídia e gestos
        ]) { [unowned self] type, event in self.handleKeyTap(type, event) }

        motionTap = EventTap(types: [
            CGEventType.mouseMoved.rawValue, CGEventType.leftMouseDragged.rawValue, CGEventType.rightMouseDragged.rawValue,
        ], listenOnly: true) { [unowned self] _, event in
            self.buttons.move(dx: event.getDoubleValueField(.mouseEventDeltaX), dy: event.getDoubleValueField(.mouseEventDeltaY))
            return event
        }

        hid.onTrigger = { [unowned self] trigger, pressed, modifiers in
            if pressed {
                _ = self.buttons.press(trigger, modifiers: modifiers)
            } else {
                _ = self.buttons.release(trigger)
            }
        }
        hid.onRaw = { [unowned self] text in self.log(text) }
        hid.onDevicesChanged = { [unowned self] list in
            // Mouse novo ou reconectado (ex.: Bluetooth depois de dormir): o macOS volta a velocidade padrão.
            if list.count > self.devices.count { self.pointer.reapplySoon() }
            self.devices = list
            self.postStatus()
        }

        buttons.onLearningChange = { [unowned self] on in
            self.learning = on
            self.hid.setLearning(on)
            self.updateKeyTap()
            self.postStatus()
        }
        buttons.onDragTrackingChange = { [unowned self] on in self.motionTap.setEnabled(on) }

        store.onChange = { [unowned self] in self.applyConfig() }
        pointer.onReport = { [unowned self] in self.postStatus() }
    }

    // MARK: Ciclo de vida

    func start() {
        FrontApp.startObserving()
        hid.start()
        startTapsIfPossible()
        applyConfig()
        commandObserver = IPC.observe(.command) { [unowned self] info in
            guard let raw = info["cmd"] as? String, let cmd = IPC.Command(rawValue: raw) else { return }
            self.handle(cmd)
        }
        postStatus()
    }

    private func handle(_ cmd: IPC.Command) {
        switch cmd {
        case .status:
            refreshPermissions()
        case .learnStart:
            buttons.learnHandler = { trigger in
                if let data = try? JSONEncoder().encode(trigger), let json = String(data: data, encoding: .utf8) {
                    IPC.post(.learned, ["trigger": json])
                }
            }
        case .learnStop:
            buttons.learnHandler = nil
        case .diagnosticsOn:
            diagnosticsOn = true
        case .diagnosticsOff:
            diagnosticsOn = false
        case .requestAccessibility:
            Permissions.requestAccessibility()
        case .requestInputMonitoring:
            Permissions.requestInputMonitoring()
        case .quit:
            NSApp.terminate(nil)
        }
    }

    /// Reage a permissões novas (o app de ajustes pergunta enquanto está aberto).
    func refreshPermissions() {
        startTapsIfPossible()
        let im = Permissions.inputMonitoring
        if im && !hadInputMonitoring { hid.restart() }
        hadInputMonitoring = im
        postStatus()
    }

    private func postStatus() {
        var s = IPC.Status()
        s.running = running
        s.accessibility = Permissions.accessibility
        s.inputMonitoring = Permissions.inputMonitoring
        s.learning = learning
        s.memoryMB = Self.memoryFootprintMB()
        s.pointerReport = pointer.report
        s.devices = devices.map { "\($0.name)|\($0.transport)|\(String(format: "%04X:%04X", $0.vendorID, $0.productID))" }
        IPC.post(.status, s.userInfo)
    }

    private func startTapsIfPossible() {
        guard !buttonTap.isRunning, Permissions.accessibility else { return }
        buttonTap.start()
        keyTap.start(enabled: false)
        motionTap.start(enabled: false)
        running = buttonTap.isRunning
        applyConfig()
    }

    private func applyConfig() {
        let config = store.config
        scroll.settings = config.scroll
        var pointerSettings = config.pointer
        if !config.enabled { pointerSettings.custom = false }
        pointer.update(pointerSettings)
        hid.setMapped(config.enabled ? store.mappedHIDTriggers : [])
        if !config.enabled { buttons.reset() }
        updateKeyTap()
    }

    private func updateKeyTap() {
        let needed = learning || diagnosticsOn || (store.config.enabled && !store.mappedHIDTriggers.isEmpty)
        keyTap.setEnabled(needed)
    }

    // MARK: Handlers dos taps (main thread)

    private func handleButtonTap(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        let active = store.config.enabled || buttons.isLearning
        switch type {
        case .otherMouseDown, .otherMouseUp:
            let n = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            if diagnosticsOn {
                log(L("macOS  clique de mouse", "macOS  mouse click") + " \(type == .otherMouseDown ? "↓" : "↑")  " + L("botão", "button") + " \(n + 1)  → \(Trigger.button(n).title)")
            }
            guard active else { return event }
            let swallow = type == .otherMouseDown ? buttons.press(.button(n)) : buttons.release(.button(n))
            return swallow ? nil : event
        case .otherMouseDragged:
            guard active else { return event }
            let n = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            buttons.move(dx: event.getDoubleValueField(.mouseEventDeltaX), dy: event.getDoubleValueField(.mouseEventDeltaY))
            return buttons.isHeld(.button(n)) ? nil : event
        case .scrollWheel:
            guard store.config.enabled else { return event }
            return scroll.handle(event)
        default:
            return event
        }
    }

    private func handleKeyTap(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        let suppress = hid.shouldSuppress(type, event)
        if diagnosticsOn, let text = Self.describe(type, event) {
            log("macOS  \(text)\(suppress ? L("  (vinha do mouse: bloqueado)", "  (came from the mouse: blocked)") : "")")
        }
        return suppress ? nil : event
    }

    private static func describe(_ type: CGEventType, _ event: CGEvent) -> String? {
        switch type.rawValue {
        case CGEventType.keyDown.rawValue, CGEventType.keyUp.rawValue:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let mods = KeyNames.symbols(for: event.flags)
            let chars = NSEvent(cgEvent: event)?.charactersIgnoringModifiers ?? ""
            return L("tecla", "key") + " \(type == .keyDown ? "↓" : "↑")  \(mods)\(chars.uppercased())  (keycode \(code))"
        case 14:
            guard let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return nil }
            let key = (ns.data1 & 0xFFFF_0000) >> 16
            let down = (ns.data1 & 0xFF00) >> 8 == 0x0A
            return L("tecla de mídia", "media key") + " \(down ? "↓" : "↑")  " + L("código", "code") + " \(key)"
        case 31:
            return L("gesto de swipe (alguns mouses mandam Voltar/Avançar assim)", "swipe gesture (some mice send Back/Forward this way)")
        default:
            return nil
        }
    }

    private func log(_ text: String) {
        IPC.post(.log, ["line": text])
    }

    /// Memória física usada pelo Helper, em MB (o mesmo número que o Monitor de Atividade mostra).
    static func memoryFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }
}
