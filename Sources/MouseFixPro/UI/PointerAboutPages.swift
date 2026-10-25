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
        PageHeader(title: "Ponteiro",
                   subtitle: "Velocidade e aceleração do mouse. O trackpad continua com os ajustes do sistema.")
        Card {
            SettingRow(title: "Ajustar o ponteiro pelo Mouse Fix Pro",
                       detail: "Desligado, valem os ajustes do macOS.",
                       symbol: "slider.horizontal.3") {
                Toggle("", isOn: $store.config.pointer.custom).toggleStyle(.switch).labelsHidden()
            }
            if store.config.pointer.custom {
                Divider()
                SettingRow(title: "Aceleração do mouse",
                           detail: store.config.pointer.acceleration
                               ? "Mexer rápido leva o ponteiro mais longe (padrão do macOS)."
                               : "Desligada: o ponteiro anda sempre a mesma distância para o mesmo movimento, como em jogos e design.",
                           symbol: "gauge.with.dots.needle.67percent") {
                    Toggle("", isOn: $store.config.pointer.acceleration).toggleStyle(.switch).labelsHidden()
                }
                Divider()
                SettingRow(title: "Velocidade", detail: speedLabel, symbol: "speedometer") {
                    HStack {
                        Image(systemName: "tortoise").foregroundStyle(.secondary)
                        Slider(value: $store.config.pointer.speed, in: 0 ... 1)
                            .frame(width: 200)
                        Image(systemName: "hare").foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Spacer()
                    Button("Voltar ao meio") { store.config.pointer.speed = 0.5 }
                        .buttonStyle(.link)
                }
            }
        }
        Card {
            Label("Fica do jeito que você deixou", systemImage: "lock.rotation")
                .font(.headline)
            Text("O macOS costuma voltar a velocidade do mouse ao padrão quando a tela é bloqueada, o Mac dorme ou o mouse Bluetooth reconecta. O Mouse Fix Pro percebe esses momentos e reaplica seu ajuste sozinho, sem ficar rodando nada em segundo plano.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

struct AboutPage: View {
    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        return "Versão \(v)"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Mouse Fix Pro").font(.largeTitle.bold())
            Text(version).foregroundStyle(.secondary)
            Text("Leve, rápido e feito para qualquer mouse no Mac.")
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)

        Card {
            SettingRow(title: "Desenvolvido por Anglerson", symbol: "person.crop.circle") {
                EmptyView()
            }
            Divider()
            SettingRow(title: "Site", symbol: "globe") {
                Link("anglerson.com.br", destination: URL(string: "https://anglerson.com.br/")!)
            }
            Divider()
            SettingRow(title: "GitHub", symbol: "chevron.left.forwardslash.chevron.right") {
                Link("github.com/Anglersondev", destination: URL(string: "https://github.com/Anglersondev")!)
            }
            Divider()
            SettingRow(title: "Código-fonte e novidades", symbol: "shippingbox") {
                Link("Ver no GitHub", destination: URL(string: "https://github.com/Anglersondev/MouseFix-Lite-MAC")!)
            }
        }
        Text("Inspirado no Mac Mouse Fix, de Noah Nuebling. Escrito do zero, sem código do original.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
    }
}
