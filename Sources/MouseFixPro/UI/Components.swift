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
                    Text(L("Falta liberar o Mouse Fix Pro Helper", "Mouse Fix Pro Helper needs permission")).font(.headline)
                    Text(L("O macOS pede sua autorização antes de um app ler o mouse. Clique em Liberar, ative o “Mouse Fix Pro Helper” na lista e volte aqui. É ele que faz o mouse funcionar.", "macOS asks for your approval before an app can read the mouse. Click Allow, turn on “Mouse Fix Pro Helper” in the list and come back here. It's the part that makes your mouse work."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            row(L("Acessibilidade", "Accessibility"), L("Para interceptar cliques e executar ações.", "To intercept clicks and run actions."),
                granted: core.status.accessibility, action: core.requestAccessibility)
            row(L("Monitoramento de Entrada", "Input Monitoring"), L("Para ler mouses que mandam o botão lateral como tecla.", "To read mice that send side buttons as keys."),
                granted: core.status.inputMonitoring, action: core.requestInputMonitoring)
        }
    }

    private func row(_ title: String, _ detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        SettingRow(title: title, detail: detail, symbol: granted ? "checkmark.circle.fill" : "circle") {
            if granted {
                Text(L("Liberado", "Allowed")).foregroundStyle(.green)
            } else {
                Button(L("Liberar", "Allow"), action: action).buttonStyle(.borderedProminent)
            }
        }
    }
}
