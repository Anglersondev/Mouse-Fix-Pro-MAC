import AppKit
import MouseFixShared
import SwiftUI
import UniformTypeIdentifiers

struct ButtonsPage: View {
    @EnvironmentObject var store: ConfigStore

    var body: some View {
        PageHeader(title: L("Botões", "Buttons"),
                   subtitle: L("Escolha o que cada botão do mouse faz. O que ficar em “Padrão do sistema” continua funcionando como antes.", "Choose what each mouse button does. Anything left on “System default” keeps working as before."))
        DetectCard()
        ForEach(store.config.triggers, id: \.self) { trigger in
            TriggerCard(trigger: trigger, profile: nil)
        }
    }
}

struct DetectCard: View {
    @EnvironmentObject var core: HelperLink
    @EnvironmentObject var store: ConfigStore
    @State private var detected: Trigger?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: core.learning ? "dot.radiowaves.left.and.right" : "computermouse")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(core.learning ? Color.accentColor : Color.secondary)
            Text(core.learning ? L("Aperte agora o botão do mouse…", "Press the mouse button now…") : L("Configurar outro botão", "Set up another button"))
                .font(.headline)
            Text(core.learning
                 ? L("Vale qualquer botão: rodinha, laterais ou botões que o mouse manda como tecla.", "Any button works: wheel, side buttons or buttons your mouse sends as keys.")
                 : L("Clique em Detectar e aperte o botão do mouse que você quer configurar.", "Click Detect and press the mouse button you want to set up."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let detected, !core.learning {
                Label(L("\(detected.title) pronto para configurar", "\(detected.title) is ready to set up"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            Button(core.learning ? L("Cancelar", "Cancel") : L("Detectar botão", "Detect button")) {
                if core.learning {
                    core.cancelLearning()
                } else {
                    detected = nil
                    core.startLearning { trigger in
                        store.addTrigger(trigger)
                        detected = trigger
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!core.running)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .foregroundStyle(core.learning ? Color.accentColor : Color.secondary.opacity(0.4)))
    }
}

struct TriggerCard: View {
    @EnvironmentObject var store: ConfigStore
    let trigger: Trigger
    let profile: String?
    @State private var showDrag = false

    var body: some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: trigger.symbol)
                    .font(.title3)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.accentColor.opacity(0.15)))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(trigger.title).font(.headline)
                    Text(trigger.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if profile == nil {
                    Button(role: .destructive) {
                        store.removeTrigger(trigger)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help(L("Remover este botão", "Remove this button"))
                }
            }
            Divider()
            ForEach(ClickKind.basic) { kind in
                SettingRow(title: kind.title, symbol: kind.symbol) {
                    ActionMenu(trigger: trigger, kind: kind, profile: profile)
                }
            }
            DisclosureGroup(isExpanded: $showDrag) {
                VStack(spacing: 10) {
                    ForEach(ClickKind.drags) { kind in
                        SettingRow(title: kind.title, symbol: kind.symbol) {
                            ActionMenu(trigger: trigger, kind: kind, profile: profile)
                        }
                    }
                    HStack {
                        Spacer()
                        Button(L("Usar gestos de Mission Control e mesas", "Use Mission Control and desktop gestures")) { applyDragPreset() }
                            .buttonStyle(.link)
                    }
                }
                .padding(.top, 8)
            } label: {
                Label(L("Segurar e arrastar", "Hold and drag"), systemImage: "hand.draw")
            }
        }
        .onAppear {
            showDrag = ClickKind.drags.contains { store.action(trigger, $0, profile: profile) != nil }
        }
    }

    /// Igual aos gestos de quatro dedos do trackpad.
    private func applyDragPreset() {
        store.setAction(.missionControl, trigger, .dragUp, profile: profile)
        store.setAction(.appExpose, trigger, .dragDown, profile: profile)
        store.setAction(.spaceRight, trigger, .dragLeft, profile: profile)
        store.setAction(.spaceLeft, trigger, .dragRight, profile: profile)
    }
}

struct ActionMenu: View {
    @EnvironmentObject var store: ConfigStore
    let trigger: Trigger
    let kind: ClickKind
    let profile: String?
    @State private var recording = false

    private var current: Action? { store.action(trigger, kind, profile: profile) }
    private var defaultTitle: String { profile == nil ? L("Padrão do sistema", "System default") : L("Igual ao geral", "Same as general") }

    var body: some View {
        Menu {
            Button(defaultTitle) { set(nil) }
            ForEach(Array(Action.groups.enumerated()), id: \.offset) { _, group in
                Section(group.0) {
                    ForEach(group.1, id: \.self) { action in
                        Button {
                            set(action)
                        } label: {
                            Label(action.title, systemImage: action.symbol)
                        }
                    }
                }
            }
            Section(L("Personalizado", "Custom")) {
                Button(L("Gravar atalho de teclado…", "Record keyboard shortcut…")) { recording = true }
                Button(L("Abrir um app…", "Open an app…")) { pickApp() }
            }
        } label: {
            Label(current?.title ?? defaultTitle, systemImage: current?.symbol ?? "circle.dashed")
        }
        .fixedSize()
        .frame(width: 240, alignment: .trailing)
        .sheet(isPresented: $recording) {
            ShortcutRecorder { combo in
                if let combo { set(.shortcut(combo)) }
                recording = false
            }
        }
    }

    private func set(_ action: Action?) {
        store.setAction(action, trigger, kind, profile: profile)
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = L("Escolher", "Choose")
        if panel.runModal() == .OK, let url = panel.url {
            set(.openApp(path: url.path))
        }
    }
}

struct ShortcutRecorder: View {
    let done: (KeyCombo?) -> Void
    @State private var monitor: Any?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "keyboard")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.accentColor)
            Text(L("Aperte o atalho", "Press the shortcut")).font(.title3.bold())
            Text(L("Por exemplo ⌘⇧4. Esc cancela.", "For example ⌘⇧4. Esc cancels."))
                .foregroundStyle(.secondary)
            Button(L("Cancelar", "Cancel")) { done(nil) }
        }
        .padding(32)
        .frame(width: 320)
        .onAppear {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 {
                    done(nil)
                    return nil
                }
                let all = event.cgEvent?.flags ?? []
                let flags = all.intersection([.maskCommand, .maskShift, .maskControl, .maskAlternate])
                let key = event.charactersIgnoringModifiers?.uppercased() ?? "?"
                done(KeyCombo(keyCode: event.keyCode, modifiers: flags.rawValue, display: KeyNames.symbols(for: flags) + key))
                return nil
            }
        }
        .onDisappear {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
