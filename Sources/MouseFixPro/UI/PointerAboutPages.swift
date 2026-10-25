import AppKit
import MouseFixShared
import SwiftUI

struct PointerPage: View {
    @EnvironmentObject var store: ConfigStore

    private var speedLabel: String {
        let s = store.config.pointer.speed
        if store.config.pointer.acceleration {
            return String(format: "%.0f%%", s * 100)
        }
        return String(format: "%.2g×", pow(4, s * 2 - 1))
    }

    var body: some View {
        PageHeader(title: L("Ponteiro", "Pointer"),
                   subtitle: L("Velocidade e aceleração do mouse. O trackpad continua com os ajustes do sistema.", "Mouse speed and acceleration. The trackpad keeps the system settings."))
        Card {
            SettingRow(title: L("Ajustar o ponteiro pelo Mouse Fix Pro", "Adjust the pointer with Mouse Fix Pro"),
                       detail: L("Desligado, valem os ajustes do macOS.", "When off, macOS settings apply."),
                       symbol: "slider.horizontal.3") {
                Toggle("", isOn: $store.config.pointer.custom).toggleStyle(.switch).labelsHidden()
            }
            if store.config.pointer.custom {
                Divider()
                SettingRow(title: L("Aceleração do mouse", "Mouse acceleration"),
                           detail: store.config.pointer.acceleration
                               ? L("Mexer rápido leva o ponteiro mais longe (padrão do macOS).", "Moving fast takes the pointer further (macOS default).")
                               : L("Desligada: o ponteiro anda sempre a mesma distância para o mesmo movimento, como em jogos e design.", "Off: the pointer always moves the same distance for the same motion, as in games and design."),
                           symbol: "gauge.with.dots.needle.67percent") {
                    Toggle("", isOn: $store.config.pointer.acceleration).toggleStyle(.switch).labelsHidden()
                }
                Divider()
                SettingRow(title: L("Velocidade", "Speed"), detail: speedLabel, symbol: "speedometer") {
                    HStack {
                        Image(systemName: "tortoise").foregroundStyle(.secondary)
                        Slider(value: $store.config.pointer.speed, in: 0 ... 1)
                            .frame(width: 200)
                        Image(systemName: "hare").foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Spacer()
                    Button(L("Voltar ao meio", "Reset to middle")) { store.config.pointer.speed = 0.5 }
                        .buttonStyle(.link)
                }
            }
        }
        Card {
            Label(L("Fica do jeito que você deixou", "Stays the way you set it"), systemImage: "lock.rotation")
                .font(.headline)
            Text(L("O macOS costuma voltar a velocidade do mouse ao padrão quando a tela é bloqueada, o Mac dorme ou o mouse Bluetooth reconecta. O Mouse Fix Pro percebe esses momentos e reaplica seu ajuste sozinho, sem ficar rodando nada em segundo plano.", "macOS tends to reset mouse speed when the screen locks, the Mac sleeps or a Bluetooth mouse reconnects. Mouse Fix Pro notices these moments and re-applies your setting on its own, with nothing extra running in the background."))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

struct AboutPage: View {
    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        return L("Versão \(v)", "Version \(v)")
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Mouse Fix Pro").font(.largeTitle.bold())
            Text(version).foregroundStyle(.secondary)
            Text(L("Leve, rápido e feito para qualquer mouse no Mac.", "Light, fast and made for any mouse on the Mac."))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)

        Card {
            SettingRow(title: L("Desenvolvido por Anglerson", "Built by Anglerson"), symbol: "person.crop.circle") {
                EmptyView()
            }
            Divider()
            SettingRow(title: L("Site", "Website"), symbol: "globe") {
                Link("anglerson.com.br", destination: URL(string: "https://anglerson.com.br/")!)
            }
            Divider()
            SettingRow(title: "GitHub", symbol: "chevron.left.forwardslash.chevron.right") {
                Link("github.com/Anglersondev", destination: URL(string: "https://github.com/Anglersondev")!)
            }
            Divider()
            SettingRow(title: L("Código-fonte e novidades", "Source code and updates"), symbol: "shippingbox") {
                Link(L("Ver no GitHub", "View on GitHub"), destination: URL(string: "https://github.com/Anglersondev/Mouse-Fix-Pro-MAC")!)
            }
        }
        Text(L("Inspirado no Mac Mouse Fix, de Noah Nuebling. Escrito do zero, sem código do original.", "Inspired by Mac Mouse Fix by Noah Nuebling. Written from scratch, with no code from the original."))
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
    }
}
