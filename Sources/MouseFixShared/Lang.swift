import Foundation

/// Idioma da interface: português se o Mac estiver em português, inglês em qualquer outro caso.
///
/// As traduções ficam no próprio código, lado a lado, em vez de arquivos .strings:
/// são só dois idiomas e assim nada de texto se perde entre os dois processos.
public enum Lang {
    public static let isPortuguese: Bool = {
        let first = Locale.preferredLanguages.first ?? "en"
        return first.hasPrefix("pt")
    }()
}

/// Texto traduzido: `L("Botões", "Buttons")`.
@inline(__always)
public func L(_ pt: String, _ en: String) -> String {
    Lang.isPortuguese ? pt : en
}
