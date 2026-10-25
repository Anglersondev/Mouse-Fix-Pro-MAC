import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var core: MouseCore
    @State private var page: Page? = .buttons

    enum Page: String, CaseIterable, Identifiable {
        case buttons, scroll, apps, diagnostics, general
        var id: String { rawValue }

        var title: String {
            switch self {
            case .buttons: return "Botões"
            case .scroll: return "Rolagem"
            case .apps: return "Por app"
            case .diagnostics: return "O que o mouse envia"
            case .general: return "Geral"
            }
        }

        var symbol: String {
            switch self {
            case .buttons: return "computermouse"
            case .scroll: return "arrow.up.arrow.down"
            case .apps: return "square.stack.3d.up"
            case .diagnostics: return "waveform.path.ecg"
            case .general: return "gearshape"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: $page) { p in
                Label(p.title, systemImage: p.symbol).tag(p)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !Permissions.allGranted {
                        PermissionBanner()
                    }
                    switch page ?? .buttons {
                    case .buttons: ButtonsPage()
                    case .scroll: ScrollPage()
                    case .apps: AppsPage()
                    case .diagnostics: DiagnosticsPage()
                    case .general: GeneralPage()
                    }
                }
                .padding(24)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 780, minHeight: 540)
    }
}
