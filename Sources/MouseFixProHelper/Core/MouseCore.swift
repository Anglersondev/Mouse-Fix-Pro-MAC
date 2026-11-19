import AppKit
import MouseFixShared

/// Liga as peças: event taps, monitor HID, motor de botões, rolagem e ponteiro.
///
/// Cada tap fica ligado somente quando necessário:
/// - `buttonTap`: botões extras.
/// - `scrollTap`: rodinha, somente quando uma opção de rolagem está ativa.
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
    private var learningTimeout: DispatchWorkItem?
    private(set) var devices: [HIDMonitor.Device] = []

    var diagnosticsOn = false {
        didSet {
            hid.setDiagnostics(diagnosticsOn)
            if !diagnosticsOn {
                diagnosticFlush?.cancel()
                diagnosticFlush = nil
                diagnosticLines.removeAll(keepingCapacity: true)
            }
            updateKeyTap()
        }
    }

    private var buttonTap: EventTap!
    private var scrollTap: EventTap!
    private var keyTap: EventTap!
    private var motionTap: EventTap!
    private var accessibility = false
    private var inputMonitoring = false
    private var commandObserver: NSObjectProtocol?
    private var settingsExitObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var diagnosticLines: [String] = []
    private var diagnosticFlush: DispatchWorkItem?

    private init() {
        buttons = ButtonEngine(store: store)

        buttonTap = EventTap(types: [
            CGEventType.otherMouseDown.rawValue, CGEventType.otherMouseUp.rawValue,
            CGEventType.otherMouseDragged.rawValue,
        ]) { [unowned self] type, event in self.handleButtonTap(type, event) }

        scrollTap = EventTap(types: [CGEventType.scrollWheel.rawValue]) { [unowned self] _, event in
            self.scroll.handle(event)
        }

        keyTap = EventTap(types: [
            CGEventType.keyDown.rawValue, CGEventType.keyUp.rawValue,
            14, 31, // tecla de mídia e swipe
        ]) { [unowned self] type, event in self.handleKeyTap(type, event) }

        motionTap = EventTap(types: [
            CGEventType.mouseMoved.rawValue, CGEventType.leftMouseDragged.rawValue, CGEventType.rightMouseDragged.rawValue,
        ], listenOnly: true) { [unowned self] _, event in
            self.buttons.move(dx: event.getDoubleValueField(.mouseEventDeltaX), dy: event.getDoubleValueField(.mouseEventDeltaY))
            return event
        }

        hid.onTrigger = { [unowned self] trigger, pressed, modifiers in
            if pressed {
                guard self.store.config.enabled || self.learning else { return }
                _ = self.buttons.press(trigger, modifiers: modifiers)
            } else {
                _ = self.buttons.release(trigger)
            }
        }
        hid.onTriggerCancelled = { [unowned self] in self.buttons.cancel($0) }
        hid.onRaw = { [unowned self] text in self.log(text) }
        hid.onDevicesChanged = { [unowned self] list in
            // Mouse novo ou reconectado (ex.: Bluetooth depois de dormir): o macOS volta a velocidade padrão.
            let previous = Set(self.devices.map(\.id))
            if list.contains(where: { !previous.contains($0.id) }) { self.pointer.reapplySoon() }
            self.devices = list
            self.postStatus()
        }

        buttons.onLearningChange = { [unowned self] on in
            self.learning = on
            if !on {
                self.learningTimeout?.cancel()
                self.learningTimeout = nil
            }
            self.hid.setLearning(on)
            self.updateKeyTap()
            self.postStatus()
        }
        buttons.onDragTrackingChange = { [unowned self] on in
            if on && self.accessibility { self.motionTap.start() }
            self.motionTap.setEnabled(on)
        }

        store.onChange = { [unowned self] in self.applyConfig() }
        pointer.onReport = { [unowned self] in self.postStatus() }
    }

    // MARK: Ciclo de vida

    func start() {
        FrontApp.startObserving { [unowned self] in self.updateKeyTap() }
        refreshPermissions()
        applyConfig()
        settingsExitObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [unowned self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == IPC.appBundleID,
                  NSRunningApplication.runningApplications(withBundleIdentifier: IPC.appBundleID).isEmpty
            else { return }
            self.buttons.learnHandler = nil
            self.diagnosticsOn = false
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshPermissions() }
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
            learningTimeout?.cancel()
            let timeout = DispatchWorkItem { [weak self] in self?.buttons.learnHandler = nil }
            learningTimeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
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
        accessibility = Permissions.accessibility
        let monitoring = Permissions.inputMonitoring
        if monitoring != inputMonitoring {
            inputMonitoring = monitoring
            hid.setAvailable(monitoring)
        }
        if accessibility {
            running = buttonTap.start()
        } else {
            buttonTap.stop()
            motionTap.stop()
            buttons.reset()
            buttons.clearNativePresses()
            running = false
        }
        updateScrollTap()
        updateKeyTap()
        postStatus()
    }

    private func postStatus() {
        var s = IPC.Status()
        s.running = running
        s.accessibility = accessibility
        s.inputMonitoring = inputMonitoring
        s.learning = learning
        s.memoryMB = Self.memoryFootprintMB()
        s.pointerReport = pointer.report
        s.devices = devices.map { "\($0.name)|\($0.transport)|\(String(format: "%04X:%04X", $0.vendorID, $0.productID))" }
        IPC.post(.status, s.userInfo)
    }

    private func applyConfig() {
        let config = store.config
        scroll.update(config.scroll)
        var pointerSettings = config.pointer
        if !config.enabled { pointerSettings.custom = false }
        pointer.update(pointerSettings)
        if !config.enabled { buttons.reset() }
        updateScrollTap()
        updateKeyTap()
    }

    private func updateScrollTap() {
        let settings = store.config.scroll
        if accessibility && store.config.enabled && (settings.smooth || settings.reverse || settings.speed != 1) {
            scrollTap.start()
        } else {
            scrollTap.stop()
            scroll.reset()
        }
    }

    private func updateKeyTap() {
        let mapped = accessibility && store.config.enabled ? store.hidTriggers(for: FrontApp.bundleID) : []
        hid.setMapped(mapped)
        if accessibility && (diagnosticsOn || (inputMonitoring && (learning || !mapped.isEmpty))) {
            keyTap.start()
            keyTap.setEnabled(true)
        } else {
            keyTap.setEnabled(false)
            if !accessibility { keyTap.stop() }
        }
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
            if type == .otherMouseDown && !active { return event }
            let swallow = type == .otherMouseDown ? buttons.press(.button(n)) : buttons.release(.button(n))
            return swallow ? nil : event
        case .otherMouseDragged:
            let n = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            if buttons.tracking {
                buttons.move(dx: event.getDoubleValueField(.mouseEventDeltaX), dy: event.getDoubleValueField(.mouseEventDeltaY))
            }
            return buttons.isHeld(.button(n)) ? nil : event
        default:
            return event
        }
    }

    private func handleKeyTap(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        let suppress = inputMonitoring && hid.shouldSuppress(type, event)
        if diagnosticsOn, let text = Self.describe(type, event) {
            log("macOS  \(text)\(suppress ? L("  (vinha do mouse: bloqueado)", "  (came from the mouse: blocked)") : "")")
        }
        return suppress ? nil : event
    }

    private static func describe(_ type: CGEventType, _ event: CGEvent) -> String? {
        switch type.rawValue {
        case 14:
            guard let media = HIDMonitor.mediaKey(event) else { return nil }
            return L("tecla de mídia", "media key") + " \(media.pressed ? "↓" : "↑")  " + L("código", "code") + " \(media.code)"
        case 31:
            return L("gesto de swipe (alguns mouses mandam Voltar/Avançar assim)", "swipe gesture (some mice send Back/Forward this way)")
        default:
            return nil
        }
    }

    private func log(_ text: String) {
        guard diagnosticsOn else { return }
        if diagnosticLines.count == 80 { diagnosticLines.removeFirst() }
        diagnosticLines.append(text)
        guard diagnosticFlush == nil else { return }
        let flush = DispatchWorkItem { [weak self] in
            guard let self else { return }
            IPC.post(.log, ["lines": self.diagnosticLines])
            self.diagnosticLines.removeAll(keepingCapacity: true)
            self.diagnosticFlush = nil
        }
        diagnosticFlush = flush
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50), execute: flush)
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
