import AppKit
import MouseFixShared
import SwiftUI
import UniformTypeIdentifiers

struct ButtonsPage: View {
    @EnvironmentObject var store: ConfigStore

    var body: some View {
        PageHeader(title: "Botões",
                   subtitle: "Escolha o que cada botão do mouse faz. O que ficar em “Padrão do sistema” continua funcionando como antes.")
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
            Text(core.learning ? "Aperte agora o botão do mouse…" : "Configurar outro botão")
                .font(.headline)
            Text(core.learning
                 ? "Vale qualquer botão: rodinha, laterais ou botões que o mouse manda como tecla."
                 : "Clique em Detectar e aperte o botão do mouse que você quer configurar.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let detected, !core.learning {
                Label("\(detected.title) pronto para configurar", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            Button(core.learning ? "Cancelar" : "Detectar botão") {
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
                    .help("Remover este botão")
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
                        Button("Usar gestos de Mission Control e mesas") { applyDragPreset() }
                            .buttonStyle(.link)
                    }
                }
                .padding(.top, 8)
            } label: {
                Label("Segurar e arrastar", systemImage: "hand.draw")
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
    private var defaultTitle: String { profile == nil ? "Padrão do sistema" : "Igual ao geral" }

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
            Section("Personalizado") {
                Button("Gravar atalho de teclado…") { recording = true }
                Button("Abrir um app…") { pickApp() }
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
        panel.prompt = "Escolher"
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
            Text("Aperte o atalho").font(.title3.bold())
            Text("Por exemplo ⌘⇧4. Esc cancela.")
                .foregroundStyle(.secondary)
            Button("Cancelar") { done(nil) }
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
