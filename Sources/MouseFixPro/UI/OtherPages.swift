import AppKit
import ServiceManagement
import MouseFixShared
import SwiftUI
import UniformTypeIdentifiers

struct ScrollPage: View {
    @EnvironmentObject var store: ConfigStore

    var body: some View {
        PageHeader(title: L("Rolagem", "Scrolling"),
                   subtitle: L("Vale só para a rodinha do mouse. O trackpad e o Magic Mouse continuam como estão.", "Applies only to the mouse wheel. Trackpad and Magic Mouse stay as they are."))
        Card {
            SettingRow(title: L("Rolagem suave", "Smooth scrolling"), detail: L("Desliza como no trackpad em vez de pular de linha em linha.", "Glides like a trackpad instead of jumping line by line."), symbol: "wind") {
                Toggle("", isOn: $store.config.scroll.smooth).toggleStyle(.switch).labelsHidden()
            }
            Divider()
            SettingRow(title: L("Inverter direção", "Reverse direction"), detail: L("Rodinha para baixo sobe a página.", "Wheel down scrolls the page up."), symbol: "arrow.up.arrow.down") {
                Toggle("", isOn: $store.config.scroll.reverse).toggleStyle(.switch).labelsHidden()
            }
            Divider()
            SettingRow(title: L("Velocidade", "Speed"), detail: String(format: "%.2g×", store.config.scroll.speed), symbol: "speedometer") {
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
        PageHeader(title: L("Por app", "Per app"),
                   subtitle: L("Botões diferentes em apps específicos. O que você não mudar aqui segue a configuração geral.", "Different buttons in specific apps. Anything you don't change here follows the general settings."))
        Card {
            if store.config.profiles.isEmpty {
                Text(L("Nenhum app ainda. Exemplo: no Photoshop, o botão lateral pode virar ⌘Z.", "No apps yet. Example: in Photoshop, a side button could become ⌘Z."))
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
                Label(L("Adicionar app…", "Add app…"), systemImage: "plus")
            }
        }
        if let selected, let profile = store.config.profiles.first(where: { $0.id == selected }) {
            Text(L("Botões no \(profile.name)", "Buttons in \(profile.name)"))
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
        panel.prompt = L("Adicionar", "Add")
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
    @EnvironmentObject var core: HelperLink

    var body: some View {
        PageHeader(title: L("O que o mouse envia", "What the mouse sends"),
                   subtitle: L("Aperte os botões do mouse e veja como cada um chega ao Mac.", "Press your mouse buttons and see how each one reaches the Mac."))
        Card {
            Text(L("Mouses conectados", "Connected mice")).font(.headline)
            if core.devices.isEmpty {
                Text(core.status.inputMonitoring
                     ? L("Nenhum mouse encontrado.", "No mouse found.")
                     : L("Libere o Monitoramento de Entrada para ver os mouses.", "Allow Input Monitoring to see your mice."))
                    .foregroundStyle(.secondary)
            }
            ForEach(core.devices) { device in
                SettingRow(title: device.name, symbol: "computermouse") {
                    Text("\(device.transport) · \(device.ids)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        Card {
            HStack {
                Text(L("Sinais recebidos", "Received signals")).font(.headline)
                Spacer()
                Button(L("Copiar", "Copy")) {
                    let text = core.log.map(\.text).joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                Button(L("Limpar", "Clear")) { core.clearLog() }
            }
            if core.log.isEmpty {
                Text(L("Aperte um botão do mouse…", "Press a mouse button…")).foregroundStyle(.secondary)
            }
            ForEach(core.log.reversed()) { line in
                Text(line.text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        Card {
            Label(L("Como ler", "How to read this"), systemImage: "lightbulb").font(.headline)
            Text(LocalizedStringKey(L("**HID** é o que o mouse mandou de verdade. **macOS** é o que o sistema fez com isso.\n\nSe o botão lateral aparece como **clique de mouse**, qualquer configuração funciona direto. Se ele aparece só como **tecla**, **tecla de mídia** ou **gesto**, seu mouse finge ser teclado. Sem problema: use Detectar botão na aba Botões e o Mouse Fix Pro cuida do resto.", "**HID** is what the mouse actually sent. **macOS** is what the system did with it.\n\nIf the side button shows up as a **mouse click**, any setting works right away. If it only shows up as a **key**, **media key** or **gesture**, your mouse is pretending to be a keyboard. No problem: use Detect button in the Buttons tab and Mouse Fix Pro handles the rest.")))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .onAppear { core.diagnosticsOn = true }
        .onDisappear { core.diagnosticsOn = false }
    }
}

struct GeneralPage: View {
    @EnvironmentObject var core: HelperLink
    @EnvironmentObject var store: ConfigStore

    var body: some View {
        PageHeader(title: L("Geral", "General"))
        Card {
            SettingRow(title: L("Ativar Mouse Fix Pro", "Enable Mouse Fix Pro"), detail: L("Desligado, o mouse volta a funcionar como antes.", "When off, your mouse works as it did before."), symbol: "power") {
                Toggle("", isOn: $store.config.enabled).toggleStyle(.switch).labelsHidden()
            }
            Divider()
            SettingRow(title: L("Abrir ao ligar o Mac", "Open at login"), detail: L("Liga só o Helper, sem abrir esta janela.", "Starts only the Helper, without opening this window."), symbol: "sunrise") {
                Toggle("", isOn: Binding(get: { core.launchAtLogin }, set: setLaunchAtLogin))
                    .toggleStyle(.switch).labelsHidden()
            }
            Divider()
            SettingRow(title: L("Ícone na barra de menus", "Menu bar icon"), detail: L("No topo da tela, ao lado do relógio.", "At the top of the screen, next to the clock."), symbol: "menubar.rectangle") {
                Toggle("", isOn: $store.config.showMenuBarIcon).toggleStyle(.switch).labelsHidden()
            }
            Divider()
            SettingRow(title: L("Ícone no Dock", "Dock icon"), detail: L("Na barra de apps, embaixo, enquanto os ajustes estão abertos.", "In the Dock at the bottom, while settings are open."), symbol: "dock.rectangle") {
                Toggle("", isOn: $store.config.showDockIcon).toggleStyle(.switch).labelsHidden()
            }
            if !store.config.showMenuBarIcon {
                Label(L("Sem o ícone, o Mouse Fix Pro continua funcionando. Para voltar aqui, abra o Mouse Fix Pro pelo Spotlight ou pela pasta Aplicativos.", "Without the icon, Mouse Fix Pro keeps working. To get back here, open Mouse Fix Pro from Spotlight or the Applications folder."),
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        Card {
            SettingRow(title: L("Memória do Helper", "Helper memory"),
                       detail: L("É só isso que fica rodando quando você fecha esta janela. Ela mesma sai da memória por completo.", "This is all that keeps running when you close this window. The window itself leaves memory completely."),
                       symbol: "memorychip") {
                Text(core.connected ? String(format: "%.1f MB", core.status.memoryMB) : "…").monospacedDigit()
            }
        }
        HStack {
            Spacer()
            Button(L("Desligar o Mouse Fix Pro por completo", "Turn off Mouse Fix Pro completely")) {
                core.quitHelper()
                NSApp.terminate(nil)
            }
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            try core.setLaunchAtLogin(on)
        } catch {
            NSSound.beep()
        }
    }
}
