import Foundation

public enum PermissionSettings {
    /// O macOS 27.0–27.2 chama o painel de Acessibilidade de Controle do Dispositivo e Acesso a Dados.
    /// A partir do 27.3, a Apple volta a oferecer Acessibilidade separadamente.
    public static let usesDeviceControlPanel: Bool = {
        if #available(macOS 27.3, *) { return false }
        if #available(macOS 27, *) { return true }
        return false
    }()
}
