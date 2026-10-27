import Foundation

/// Algo que o mouse faz e que pode ser remapeado.
///
/// Mouses mandam os botões laterais de jeitos diferentes. Os "bem comportados" mandam
/// Botão 4/5, que o macOS entrega como clique de mouse. Muitos mouses Bluetooth baratos
/// mandam uma tecla de mídia (Voltar/Avançar) ou um atalho de teclado no lugar. Esses
/// chegam como `.hid`, lidos direto do relatório HID do mouse.
public enum Trigger: Hashable, Codable {
    /// Número do botão como o macOS conta: 2 = meio, 3 = Botão 4, 4 = Botão 5...
    case button(Int)
    /// Uso HID cru vindo de um mouse (tecla de mídia, tecla de teclado, página do fabricante).
    case hid(page: UInt32, usage: UInt32)

    public static let consumerPage: UInt32 = 0x0C
    public static let keyboardPage: UInt32 = 0x07

    public var title: String {
        switch self {
        case .button(2): return L("Botão do meio", "Middle button")
        case .button(let n): return L("Botão \(n + 1)", "Button \(n + 1)")
        case .hid(Self.consumerPage, 0x224): return L("Botão lateral (Voltar)", "Side button (Back)")
        case .hid(Self.consumerPage, 0x225): return L("Botão lateral (Avançar)", "Side button (Forward)")
        case .hid(Self.consumerPage, let u): return L("Botão especial 0x\(String(u, radix: 16, uppercase: true))", "Special button 0x\(String(u, radix: 16, uppercase: true))")
        case .hid(Self.keyboardPage, let u): return L("Botão que envia “\(KeyNames.name(forUsage: u))”", "Button that sends “\(KeyNames.name(forUsage: u))”")
        case .hid(let p, let u): return L("Sinal 0x\(String(p, radix: 16)):0x\(String(u, radix: 16))", "Signal 0x\(String(p, radix: 16)):0x\(String(u, radix: 16))")
        }
    }

    public var subtitle: String {
        switch self {
        case .button(2): return L("Clique na rodinha", "Scroll wheel click")
        case .button(3): return L("Normalmente o lateral de trás (Voltar)", "Usually the rear side button (Back)")
        case .button(4): return L("Normalmente o lateral da frente (Avançar)", "Usually the front side button (Forward)")
        case .button: return L("Botão extra do mouse", "Extra mouse button")
        case .hid(Self.consumerPage, _): return L("Seu mouse envia este botão como tecla de mídia", "Your mouse sends this button as a media key")
        case .hid(Self.keyboardPage, _): return L("Seu mouse envia este botão como atalho de teclado", "Your mouse sends this button as a keyboard shortcut")
        case .hid: return L("Sinal próprio do fabricante", "Manufacturer-specific signal")
        }
    }

    public var symbol: String {
        switch self {
        case .button(2): return "computermouse"
        case .hid(Self.consumerPage, 0x224), .button(3): return "arrow.left.circle"
        case .hid(Self.consumerPage, 0x225), .button(4): return "arrow.right.circle"
        case .hid(Self.keyboardPage, _): return "keyboard"
        default: return "circle.grid.cross"
        }
    }

    public var isHID: Bool {
        if case .hid = self { return true }
        return false
    }
}

/// Como o botão foi usado.
public enum ClickKind: String, Codable, CaseIterable, Identifiable {
    case click, doubleClick, hold, dragUp, dragDown, dragLeft, dragRight

    public var id: String { rawValue }

    public static let basic: [ClickKind] = [.click, .doubleClick, .hold]
    public static let drags: [ClickKind] = [.dragUp, .dragDown, .dragLeft, .dragRight]

    public var title: String {
        switch self {
        case .click: return L("Clique", "Click")
        case .doubleClick: return L("Clique duplo", "Double click")
        case .hold: return L("Segurar", "Hold")
        case .dragUp: return L("Segurar e arrastar para cima", "Hold and drag up")
        case .dragDown: return L("Segurar e arrastar para baixo", "Hold and drag down")
        case .dragLeft: return L("Segurar e arrastar para a esquerda", "Hold and drag left")
        case .dragRight: return L("Segurar e arrastar para a direita", "Hold and drag right")
        }
    }

    public var symbol: String {
        switch self {
        case .click: return "cursorarrow.click"
        case .doubleClick: return "cursorarrow.click.2"
        case .hold: return "hand.tap"
        case .dragUp: return "arrow.up"
        case .dragDown: return "arrow.down"
        case .dragLeft: return "arrow.left"
        case .dragRight: return "arrow.right"
        }
    }
}
