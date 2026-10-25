import AppKit
import Combine

/// Liga as peças: event taps, monitor HID, motor de botões e rolagem.
///
/// Três taps, cada um ligado só quando precisa:
/// - `buttonTap`: botões extras e rodinha. Sempre ligado.
/// - `keyTap`: teclado, teclas de mídia e gestos. Só quando algum botão do mouse chega como
///   tecla/mídia (ou no modo de detecção), para não passar cada tecla digitada pelo app à toa.
/// - `motionTap`: movimento do ponteiro. Só enquanto um botão com gesto de arrastar está apertado.
final class MouseCore: ObservableObject {
    static let shared = MouseCore()

    struct LogLine: Identifiable {
        let id = UUID()
        let time = Date()
        let text: String
    }

    let store = ConfigStore()
    let hid = HIDMonitor()
    let scroll = ScrollEngine()
    let buttons: ButtonEngine

    @Published private(set) var running = false
    @Published private(set) var learning = false
    @Published private(set) var devices: [HIDMonitor.Device] = []
    @Published private(set) var log: [LogLine] = []

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
        hid.onRaw = { [unowned self] text in self.append(text) }
        hid.onDevicesChanged = { [unowned self] list in self.devices = list }

        buttons.onLearningChange = { [unowned self] on in
            self.learning = on
            self.hid.setLearning(on)
            self.updateKeyTap()
        }
        buttons.onDragTrackingChange = { [unowned self] on in self.motionTap.setEnabled(on) }

        store.onChange = { [unowned self] in self.applyConfig() }
    }

    // MARK: Ciclo de vida

    func start() {
        FrontApp.startObserving()
        hid.start()
        startTapsIfPossible()
        applyConfig()
    }

    /// Chamado periodicamente enquanto a janela de ajustes está aberta, para reagir a permissões novas.
    func refreshPermissions() {
        startTapsIfPossible()
        let im = Permissions.inputMonitoring
        if im && !hadInputMonitoring { hid.restart() }
        hadInputMonitoring = im
        objectWillChange.send()
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
        hid.setMapped(config.enabled ? store.mappedHIDTriggers : [])
        if !config.enabled { buttons.reset() }
        updateKeyTap()
    }

    private func updateKeyTap() {
        let needed = learning || diagnosticsOn || (store.config.enabled && !store.mappedHIDTriggers.isEmpty)
        keyTap.setEnabled(needed)
    }

    // MARK: Detecção de botão

    func startLearning(_ done: @escaping (Trigger) -> Void) {
        buttons.learnHandler = done
    }

    func cancelLearning() {
        buttons.learnHandler = nil
    }

    // MARK: Handlers dos taps (main thread)

    private func handleButtonTap(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        let active = store.config.enabled || buttons.isLearning
        switch type {
        case .otherMouseDown, .otherMouseUp:
            let n = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            if diagnosticsOn {
                append("macOS  clique de mouse \(type == .otherMouseDown ? "↓" : "↑")  botão \(n + 1)  → \(Trigger.button(n).title)")
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
            append("macOS  \(text)\(suppress ? "  (vinha do mouse: bloqueado)" : "")")
        }
        return suppress ? nil : event
    }

    private static func describe(_ type: CGEventType, _ event: CGEvent) -> String? {
        switch type.rawValue {
        case CGEventType.keyDown.rawValue, CGEventType.keyUp.rawValue:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let mods = KeyNames.symbols(for: event.flags)
            let chars = NSEvent(cgEvent: event)?.charactersIgnoringModifiers ?? ""
            return "tecla \(type == .keyDown ? "↓" : "↑")  \(mods)\(chars.uppercased())  (keycode \(code))"
        case 14:
            guard let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return nil }
            let key = (ns.data1 & 0xFFFF_0000) >> 16
            let down = (ns.data1 & 0xFF00) >> 8 == 0x0A
            return "tecla de mídia \(down ? "↓" : "↑")  código \(key)"
        case 31:
            return "gesto de swipe (alguns mouses mandam Voltar/Avançar assim)"
        default:
            return nil
        }
    }

    private func append(_ text: String) {
        log.append(LogLine(text: text))
        if log.count > 80 { log.removeFirst(log.count - 80) }
    }

    func clearLog() { log.removeAll() }

    /// Memória física usada pelo app, em MB (o mesmo número que o Monitor de Atividade mostra).
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
