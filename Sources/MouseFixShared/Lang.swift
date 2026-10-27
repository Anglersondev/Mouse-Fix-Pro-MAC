import Foundation

/// Idioma da interface. No automático segue o Mac: português se o Mac estiver em português,
/// inglês em qualquer outro caso. Na aba Geral dá para fixar um dos dois.
///
/// As traduções ficam no próprio código, lado a lado, em vez de arquivos .strings:
/// são só dois idiomas e assim nada de texto se perde entre os dois processos.
/// O idioma é lido uma vez ao abrir; trocar reabre o app.
public enum Lang {
    public static let isPortuguese: Bool = {
        switch savedChoice() {
        case "pt": return true
        case "en": return false
        default: return (Locale.preferredLanguages.first ?? "en").hasPrefix("pt")
        }
    }()

    /// Lê só a chave "language" do config.json, sem montar a configuração inteira.
    private static func savedChoice() -> String {
        guard let data = try? Data(contentsOf: ConfigStore.fileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return "auto" }
        return json["language"] as? String ?? "auto"
    }
}

/// Texto traduzido: `L("Botões", "Buttons")`.
@inline(__always)
public func L(_ pt: String, _ en: String) -> String {
    Lang.isPortuguese ? pt : en
}
