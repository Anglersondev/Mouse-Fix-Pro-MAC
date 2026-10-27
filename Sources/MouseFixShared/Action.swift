import Foundation

public struct KeyCombo: Codable, Hashable {
    public var keyCode: UInt16
    public var modifiers: UInt64
    public var display: String

    public init(keyCode: UInt16, modifiers: UInt64, display: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.display = display
    }
}

public enum Action: Codable, Hashable {
    case none
    case missionControl, appExpose, showDesktop, launchpad
    case spaceLeft, spaceRight
    case back, forward, middleClick
    case playPause, nextTrack, previousTrack, volumeUp, volumeDown, mute
    case lookUp, screenshot, lockScreen
    case closeTab, newTab, reopenTab, zoomIn, zoomOut
    case shortcut(KeyCombo)
    case openApp(path: String)

    public var title: String {
        switch self {
        case .none: return L("Não fazer nada", "Do nothing")
        case .missionControl: return "Mission Control"
        case .appExpose: return L("Janelas do app", "App windows")
        case .showDesktop: return L("Mostrar a mesa", "Show desktop")
        case .launchpad: return "Launchpad / Apps"
        case .spaceLeft: return L("Mesa à esquerda", "Desktop to the left")
        case .spaceRight: return L("Mesa à direita", "Desktop to the right")
        case .back: return L("Voltar", "Back")
        case .forward: return L("Avançar", "Forward")
        case .middleClick: return L("Clique do meio", "Middle click")
        case .playPause: return L("Tocar / pausar", "Play / pause")
        case .nextTrack: return L("Próxima faixa", "Next track")
        case .previousTrack: return L("Faixa anterior", "Previous track")
        case .volumeUp: return L("Aumentar volume", "Volume up")
        case .volumeDown: return L("Diminuir volume", "Volume down")
        case .mute: return L("Silenciar", "Mute")
        case .lookUp: return L("Pesquisar palavra", "Look up word")
        case .screenshot: return L("Captura de tela", "Screenshot")
        case .lockScreen: return L("Bloquear tela", "Lock screen")
        case .closeTab: return L("Fechar aba (⌘W)", "Close tab (⌘W)")
        case .newTab: return L("Nova aba (⌘T)", "New tab (⌘T)")
        case .reopenTab: return L("Reabrir aba (⌘⇧T)", "Reopen tab (⌘⇧T)")
        case .zoomIn: return L("Aumentar zoom", "Zoom in")
        case .zoomOut: return L("Diminuir zoom", "Zoom out")
        case .shortcut(let k): return L("Atalho \(k.display)", "Shortcut \(k.display)")
        case .openApp(let path): return L("Abrir", "Open") + " \(FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: ""))"
        }
    }

    public var symbol: String {
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

    public static let groups: [(String, [Action])] = [
        (L("Janelas e mesas", "Windows and desktops"), [.missionControl, .appExpose, .showDesktop, .launchpad, .spaceLeft, .spaceRight]),
        (L("Navegação", "Navigation"), [.back, .forward, .middleClick, .closeTab, .newTab, .reopenTab, .zoomIn, .zoomOut]),
        (L("Mídia", "Media"), [.playPause, .nextTrack, .previousTrack, .volumeUp, .volumeDown, .mute]),
        (L("Sistema", "System"), [.lookUp, .screenshot, .lockScreen, .none]),
    ]
}
