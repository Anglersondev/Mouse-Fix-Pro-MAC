import AppKit

/// Transforma apertos e solturas em clique, clique duplo, segurar e arrastar, e dispara as ações.
/// Roda inteiro na main thread.
final class ButtonEngine {
    private struct Press {
        var actions: [ClickKind: Action]
        var modifiers: CGEventFlags
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        var consumed = false
        var holdTimer: DispatchWorkItem?
        var hasDrag: Bool { ClickKind.drags.contains { actions[$0] != nil } }
    }

    private let store: ConfigStore
    private var presses: [Trigger: Press] = [:]
    private var pendingClick: [Trigger: DispatchWorkItem] = [:]
    /// Gatilhos apertados sem ação neste app: o comportamento original volta na soltura.
    private var passthroughOnRelease: [Trigger: CGEventFlags] = [:]
    private var learnedAndHeld: Set<Trigger> = []

    /// Quando definido, o próximo botão apertado vai para cá em vez de disparar ação.
    var learnHandler: ((Trigger) -> Void)? {
        didSet { onLearningChange?(learnHandler != nil) }
    }
    var onLearningChange: ((Bool) -> Void)?
    /// Liga/desliga o rastreamento de movimento (só fica ativo enquanto um botão com gesto de arrastar está apertado).
    var onDragTrackingChange: ((Bool) -> Void)?

    private let holdDelay: TimeInterval = 0.35
    private let dragThreshold: CGFloat = 60
    private var doubleClickWindow: TimeInterval { min(NSEvent.doubleClickInterval, 0.3) }

    init(store: ConfigStore) {
        self.store = store
    }

    var isLearning: Bool { learnHandler != nil }

    /// Retorna true se o evento original deve ser engolido.
    func press(_ trigger: Trigger, modifiers: CGEventFlags = []) -> Bool {
        if let learn = learnHandler {
            learnHandler = nil
            learnedAndHeld.insert(trigger)
            learn(trigger)
            return true
        }
        let actions = store.actions(for: trigger, app: FrontApp.bundleID)
        guard !actions.isEmpty else {
            // Gatilho HID mapeado em outro app: o monitor já engoliu o evento, então devolvemos o original.
            if trigger.isHID { passthroughOnRelease[trigger] = modifiers }
            return false
        }
        var p = Press(actions: actions, modifiers: modifiers)
        if actions[.hold] != nil {
            let item = DispatchWorkItem { [weak self] in self?.fireHold(trigger) }
            p.holdTimer = item
            DispatchQueue.main.asyncAfter(deadline: .now() + holdDelay, execute: item)
        }
        presses[trigger] = p
        updateDragTracking()
        return true
    }

    /// Retorna true se o evento original deve ser engolido.
    func release(_ trigger: Trigger) -> Bool {
        if learnedAndHeld.remove(trigger) != nil { return true }
        if let mods = passthroughOnRelease.removeValue(forKey: trigger) {
            ActionRunner.passthrough(trigger, modifiers: mods)
            return false
        }
        guard let p = presses.removeValue(forKey: trigger) else { return false }
        p.holdTimer?.cancel()
        updateDragTracking()
        if p.consumed { return true }

        if let double = p.actions[.doubleClick] {
            if let pending = pendingClick.removeValue(forKey: trigger) {
                pending.cancel()
                ActionRunner.perform(double)
            } else {
                let item = DispatchWorkItem { [weak self] in
                    self?.pendingClick[trigger] = nil
                    self?.click(trigger, p)
                }
                pendingClick[trigger] = item
                DispatchQueue.main.asyncAfter(deadline: .now() + doubleClickWindow, execute: item)
            }
        } else {
            click(trigger, p)
        }
        return true
    }

    func isHeld(_ trigger: Trigger) -> Bool { presses[trigger] != nil }

    /// Movimento do ponteiro enquanto algum botão está apertado.
    func move(dx: CGFloat, dy: CGFloat) {
        for (trigger, var p) in presses where !p.consumed && p.hasDrag {
            p.dx += dx
            p.dy += dy
            if hypot(p.dx, p.dy) >= dragThreshold {
                let kind: ClickKind = abs(p.dx) > abs(p.dy)
                    ? (p.dx > 0 ? .dragRight : .dragLeft)
                    : (p.dy > 0 ? .dragDown : .dragUp)
                if let action = p.actions[kind] {
                    p.consumed = true
                    p.holdTimer?.cancel()
                    ActionRunner.perform(action)
                } else {
                    p.dx = 0
                    p.dy = 0
                }
            }
            presses[trigger] = p
        }
        updateDragTracking()
    }

    private func click(_ trigger: Trigger, _ p: Press) {
        if let action = p.actions[.click] {
            ActionRunner.perform(action)
        } else {
            ActionRunner.passthrough(trigger, modifiers: p.modifiers)
        }
    }

    private func fireHold(_ trigger: Trigger) {
        guard var p = presses[trigger], !p.consumed, let action = p.actions[.hold] else { return }
        p.consumed = true
        presses[trigger] = p
        ActionRunner.perform(action)
        updateDragTracking()
    }

    private var tracking = false
    private func updateDragTracking() {
        let want = presses.values.contains { !$0.consumed && $0.hasDrag }
        if want != tracking {
            tracking = want
            onDragTrackingChange?(want)
        }
    }

    /// Solta tudo (ex.: quando o app é desativado).
    func reset() {
        presses.values.forEach { $0.holdTimer?.cancel() }
        pendingClick.values.forEach { $0.cancel() }
        presses = [:]
        pendingClick = [:]
        passthroughOnRelease = [:]
        learnedAndHeld = []
        updateDragTracking()
    }
}

/// App da frente, mantido em cache por notificação para não consultar o sistema a cada clique.
enum FrontApp {
    private(set) static var bundleID: String? = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    private static var observer: NSObjectProtocol?

    static func startObserving() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            bundleID = app?.bundleIdentifier
        }
    }
}
