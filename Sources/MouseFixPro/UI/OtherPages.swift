import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct ScrollPage: View {
    @EnvironmentObject var store: ConfigStore

    var body: some View {
        PageHeader(title: "Rolagem",
                   subtitle: "Vale só para a rodinha do mouse. O trackpad e o Magic Mouse continuam como estão.")
        Card {
            SettingRow(title: "Rolagem suave", detail: "Desliza como no trackpad em vez de pular de linha em linha.", symbol: "wind") {
                Toggle("", isOn: $store.config.scroll.smooth).toggleStyle(.switch).labelsHidden()
            }
            Divider()
            SettingRow(title: "Inverter direção", detail: "Rodinha para baixo sobe a página.", symbol: "arrow.up.arrow.down") {
                Toggle("", isOn: $store.config.scroll.reverse).toggleStyle(.switch).labelsHidden()
            }
            Divider()
            SettingRow(title: "Velocidade", detail: String(format: "%.2g×", store.config.scroll.speed), symbol: "speedometer") {
                HStack {
                    Image(systemName: "tortoise").foregroundStyle(.secondary)
                    Slider(value: $store.config.scroll.speed, in: 0.5 ... 3, step: 0.25)
                        .frame(width: 200)
                    Image(systemName: "hare").foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct AppsPage: View {
    @EnvironmentObject var store: ConfigStore
    @State private var selected: String?

    var body: some View {
        PageHeader(title: "Por app",
                   subtitle: "Botões diferentes em apps específicos. O que você não mudar aqui segue a configuração geral.")
        Card {
            if store.config.profiles.isEmpty {
                Text("Nenhum app ainda. Exemplo: no Photoshop, o botão lateral pode virar ⌘Z.")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.config.profiles) { profile in
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: profile.path))
                        .resizable()
                        .frame(width: 26, height: 26)
                    Text(profile.name)
                    Spacer()
                    if selected == profile.id {
                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                    }
                    Button(role: .destructive) {
                        store.config.profiles.removeAll { $0.id == profile.id }
                        if selected == profile.id { selected = nil }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
                .contentShape(Rectangle())
                .onTapGesture { selected = profile.id }
                Divider()
            }
            Button {
                addApp()
            } label: {
                Label("Adicionar app…", systemImage: "plus")
            }
        }
        if let selected, let profile = store.config.profiles.first(where: { $0.id == selected }) {
            Text("Botões no \(profile.name)")
                .font(.title2.bold())
                .padding(.top, 8)
            ForEach(store.config.triggers, id: \.self) { trigger in
                TriggerCard(trigger: trigger, profile: profile.bundleID)
            }
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Adicionar"
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        if !store.config.profiles.contains(where: { $0.bundleID == id }) {
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            store.config.profiles.append(AppProfile(bundleID: id, name: name, path: url.path))
        }
        selected = id
    }
}

struct DiagnosticsPage: View {
    @EnvironmentObject var core: MouseCore

    var body: some View {
        PageHeader(title: "O que o mouse envia",
                   subtitle: "Aperte os botões do mouse e veja como cada um chega ao Mac.")
        Card {
            Text("Mouses conectados").font(.headline)
            if core.devices.isEmpty {
                Text(Permissions.inputMonitoring
                     ? "Nenhum mouse encontrado."
                     : "Libere o Monitoramento de Entrada para ver os mouses.")
                    .foregroundStyle(.secondary)
            }
            ForEach(core.devices) { device in
                SettingRow(title: device.name, symbol: "computermouse") {
                    Text("\(device.transport) · \(String(format: "%04X:%04X", device.vendorID, device.productID))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        Card {
            HStack {
                Text("Sinais recebidos").font(.headline)
                Spacer()
                Button("Copiar") {
                    let text = core.log.map(\.text).joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                Button("Limpar") { core.clearLog() }
            }
            if core.log.isEmpty {
                Text("Aperte um botão do mouse…").foregroundStyle(.secondary)
            }
            ForEach(core.log.reversed()) { line in
                Text(line.text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        Card {
            Label("Como ler", systemImage: "lightbulb").font(.headline)
            Text("**HID** é o que o mouse mandou de verdade. **macOS** é o que o sistema fez com isso.\n\nSe o botão lateral aparece como **clique de mouse**, qualquer configuração funciona direto. Se ele aparece só como **tecla**, **tecla de mídia** ou **gesto**, seu mouse finge ser teclado. Sem problema: use Detectar botão na aba Botões e o Mouse Fix Pro cuida do resto.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .onAppear { core.diagnosticsOn = true }
        .onDisappear { core.diagnosticsOn = false }
    }
}

struct GeneralPage: View {
    @EnvironmentObject var store: ConfigStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var memory = MouseCore.memoryFootprintMB()
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        PageHeader(title: "Geral")
        Card {
            SettingRow(title: "Ativar Mouse Fix Pro", detail: "Desligado, o mouse volta a funcionar como antes.", symbol: "power") {
                Toggle("", isOn: $store.config.enabled).toggleStyle(.switch).labelsHidden()
            }
            Divider()
            SettingRow(title: "Abrir ao ligar o Mac", symbol: "sunrise") {
                Toggle("", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                    .toggleStyle(.switch).labelsHidden()
            }
            Divider()
            SettingRow(title: "Ícone na barra de menus", detail: "No topo da tela, ao lado do relógio.", symbol: "menubar.rectangle") {
                Toggle("", isOn: $store.config.showMenuBarIcon).toggleStyle(.switch).labelsHidden()
            }
            Divider()
            SettingRow(title: "Ícone no Dock", detail: "Na barra de apps fixados, embaixo.", symbol: "dock.rectangle") {
                Toggle("", isOn: $store.config.showDockIcon).toggleStyle(.switch).labelsHidden()
            }
            if !store.config.showMenuBarIcon && !store.config.showDockIcon {
                Label("Com os dois ocultos, o app continua funcionando. Para voltar aqui, abra o Mouse Fix Pro de novo pelo Spotlight ou pela pasta Aplicativos.",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        Card {
            SettingRow(title: "Memória em uso agora",
                       detail: "Com esta janela fechada, a interface sai da memória e o app usa ainda menos.",
                       symbol: "memorychip") {
                Text(String(format: "%.1f MB", memory)).monospacedDigit()
            }
        }
        .onReceive(timer) { _ in memory = MouseCore.memoryFootprintMB() }
        HStack {
            Spacer()
            Button("Sair do Mouse Fix Pro") { NSApp.terminate(nil) }
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSSound.beep()
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
