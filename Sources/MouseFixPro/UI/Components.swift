import AppKit
import MouseFixShared
import SwiftUI

// Seleciona o property wrapper, disponível também nas Command Line Tools sem a macro do Xcode 27.
typealias ViewState<Value> = State<Value>

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
                    Text(L("Clique em Abrir Ajustes e autorize “Mouse Fix Pro Helper”. Se ele não aparecer, clique em Mostrar Helper e adicione esse arquivo pelo botão + nos Ajustes do Sistema.", "Click Open Settings and allow “Mouse Fix Pro Helper”. If it is missing, click Show Helper and use the + button in System Settings to add that file."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            row(L("Acessibilidade", "Accessibility"), L("Para interceptar cliques e executar ações.", "To intercept clicks and run actions."),
                granted: core.status.accessibility, ready: core.status.running, action: core.requestAccessibility)
            row(L("Monitoração de Entrada", "Input Monitoring"), L("Para ler mouses que mandam o botão lateral como tecla.", "To read mice that send side buttons as keys."),
                granted: core.status.inputMonitoring, ready: core.status.hidReady, action: core.requestInputMonitoring)
            HStack {
                Button(L("Mostrar Helper", "Show Helper"), action: core.revealHelper)
                Button(L("Reiniciar Helper", "Restart Helper"), action: core.restartHelper)
            }
            if let error = core.status.hidError {
                Text(L("O macOS autorizou a entrada, mas o leitor HID falhou (\(error)).", "macOS allowed input, but the HID reader failed (\(error))."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ title: String, _ detail: String, granted: Bool, ready: Bool, action: @escaping () -> Void) -> some View {
        SettingRow(title: title, detail: detail, symbol: ready ? "checkmark.circle.fill" : "circle") {
            if ready {
                Text(L("Ativo", "Active")).foregroundStyle(.green)
            } else if granted {
                Text(L("Autorizado, aguardando acesso", "Allowed, waiting for access"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button(L("Abrir Ajustes", "Open Settings"), action: action).buttonStyle(.borderedProminent)
            }
        }
    }
}
