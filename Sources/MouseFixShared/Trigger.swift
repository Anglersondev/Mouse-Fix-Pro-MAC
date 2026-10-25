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
        case .button(2): return "Botão do meio"
        case .button(let n): return "Botão \(n + 1)"
        case .hid(Self.consumerPage, 0x224): return "Botão lateral (Voltar)"
        case .hid(Self.consumerPage, 0x225): return "Botão lateral (Avançar)"
        case .hid(Self.consumerPage, let u): return "Botão especial 0x\(String(u, radix: 16, uppercase: true))"
        case .hid(Self.keyboardPage, let u): return "Botão que envia “\(KeyNames.name(forUsage: u))”"
        case .hid(let p, let u): return "Sinal 0x\(String(p, radix: 16)):0x\(String(u, radix: 16))"
        }
    }

    public var subtitle: String {
        switch self {
        case .button(2): return "Clique na rodinha"
        case .button(3): return "Normalmente o lateral de trás (Voltar)"
        case .button(4): return "Normalmente o lateral da frente (Avançar)"
        case .button: return "Botão extra do mouse"
        case .hid(Self.consumerPage, _): return "Seu mouse envia este botão como tecla de mídia"
        case .hid(Self.keyboardPage, _): return "Seu mouse envia este botão como atalho de teclado"
        case .hid: return "Sinal próprio do fabricante"
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
        case .click: return "Clique"
        case .doubleClick: return "Clique duplo"
        case .hold: return "Segurar"
        case .dragUp: return "Segurar e arrastar para cima"
        case .dragDown: return "Segurar e arrastar para baixo"
        case .dragLeft: return "Segurar e arrastar para a esquerda"
        case .dragRight: return "Segurar e arrastar para a direita"
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
