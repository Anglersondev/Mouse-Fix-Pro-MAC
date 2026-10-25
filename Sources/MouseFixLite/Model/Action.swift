import Foundation

struct KeyCombo: Codable, Hashable {
    var keyCode: UInt16
    var modifiers: UInt64
    var display: String
}

enum Action: Codable, Hashable {
    case none
    case missionControl, appExpose, showDesktop, launchpad
    case spaceLeft, spaceRight
    case back, forward, middleClick
    case playPause, nextTrack, previousTrack, volumeUp, volumeDown, mute
    case lookUp, screenshot, lockScreen
    case closeTab, newTab, reopenTab, zoomIn, zoomOut
    case shortcut(KeyCombo)
    case openApp(path: String)

    var title: String {
        switch self {
        case .none: return "Não fazer nada"
        case .missionControl: return "Mission Control"
        case .appExpose: return "Janelas do app"
        case .showDesktop: return "Mostrar a mesa"
        case .launchpad: return "Launchpad / Apps"
        case .spaceLeft: return "Mesa à esquerda"
        case .spaceRight: return "Mesa à direita"
        case .back: return "Voltar"
        case .forward: return "Avançar"
        case .middleClick: return "Clique do meio"
        case .playPause: return "Tocar / pausar"
        case .nextTrack: return "Próxima faixa"
        case .previousTrack: return "Faixa anterior"
        case .volumeUp: return "Aumentar volume"
        case .volumeDown: return "Diminuir volume"
        case .mute: return "Silenciar"
        case .lookUp: return "Pesquisar palavra"
        case .screenshot: return "Captura de tela"
        case .lockScreen: return "Bloquear tela"
        case .closeTab: return "Fechar aba (⌘W)"
        case .newTab: return "Nova aba (⌘T)"
        case .reopenTab: return "Reabrir aba (⌘⇧T)"
        case .zoomIn: return "Aumentar zoom"
        case .zoomOut: return "Diminuir zoom"
        case .shortcut(let k): return "Atalho \(k.display)"
        case .openApp(let path): return "Abrir \(FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: ""))"
        }
    }

    var symbol: String {
        switch self {
        case .none: return "nosign"
        case .missionControl: return "rectangle.3.group"
        case .appExpose: return "rectangle.stack"
        case .showDesktop: return "menubar.dock.rectangle"
        case .launchpad: return "square.grid.3x3"
        case .spaceLeft: return "arrow.left.square"
        case .spaceRight: return "arrow.right.square"
        case .back: return "chevron.backward"
        case .forward: return "chevron.forward"
        case .middleClick: return "computermouse"
        case .playPause: return "playpause"
        case .nextTrack: return "forward"
        case .previousTrack: return "backward"
        case .volumeUp: return "speaker.plus"
        case .volumeDown: return "speaker.minus"
        case .mute: return "speaker.slash"
        case .lookUp: return "character.book.closed"
        case .screenshot: return "camera.viewfinder"
        case .lockScreen: return "lock"
        case .closeTab: return "xmark.square"
        case .newTab: return "plus.square"
        case .reopenTab: return "arrow.uturn.backward.square"
        case .zoomIn: return "plus.magnifyingglass"
        case .zoomOut: return "minus.magnifyingglass"
        case .shortcut: return "command"
        case .openApp: return "app"
        }
    }

    static let groups: [(String, [Action])] = [
        ("Janelas e mesas", [.missionControl, .appExpose, .showDesktop, .launchpad, .spaceLeft, .spaceRight]),
        ("Navegação", [.back, .forward, .middleClick, .closeTab, .newTab, .reopenTab, .zoomIn, .zoomOut]),
        ("Mídia", [.playPause, .nextTrack, .previousTrack, .volumeUp, .volumeDown, .mute]),
        ("Sistema", [.lookUp, .screenshot, .lockScreen, .none]),
    ]
}
