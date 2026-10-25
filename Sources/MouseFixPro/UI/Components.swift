import AppKit
import MouseFixShared
import SwiftUI

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08)))
    }
}

struct PageHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.largeTitle.bold())
            if let subtitle {
                Text(subtitle).foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 4)
    }
}

struct SettingRow<Trailing: View>: View {
    let title: String
    var detail: String?
    var symbol: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .frame(width: 22)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

struct PermissionBanner: View {
    @EnvironmentObject var core: HelperLink
    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "hand.raised.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Falta liberar o Mouse Fix Pro Helper").font(.headline)
                    Text("O macOS pede sua autorização antes de um app ler o mouse. Clique em Liberar, ative o “Mouse Fix Pro Helper” na lista e volte aqui. É ele que faz o mouse funcionar.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            row("Acessibilidade", "Para interceptar cliques e executar ações.",
                granted: core.status.accessibility, action: core.requestAccessibility)
            row("Monitoramento de Entrada", "Para ler mouses que mandam o botão lateral como tecla.",
                granted: core.status.inputMonitoring, action: core.requestInputMonitoring)
        }
    }

    private func row(_ title: String, _ detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        SettingRow(title: title, detail: detail, symbol: granted ? "checkmark.circle.fill" : "circle") {
            if granted {
                Text("Liberado").foregroundStyle(.green)
            } else {
                Button("Liberar", action: action).buttonStyle(.borderedProminent)
            }
        }
    }
}
