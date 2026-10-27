import Foundation

/// Conversa entre o app de ajustes e o Mouse Fix Pro Helper.
///
/// São notificações distribuídas do macOS: sem servidor, sem conexão aberta e custo zero
/// enquanto ninguém fala. Cada processo ignora o que ele mesmo mandou.
public enum IPC {
    public static let appBundleID = "com.anglersondev.mousefixpro"
    public static let helperBundleID = "com.anglersondev.mousefixpro.helper"

    public enum Message: String {
        /// O config.json mudou; quem não salvou relê.
        case configChanged
        /// Ajustes → Helper. userInfo["cmd"]: um `Command`.
        case command
        /// Helper → Ajustes. userInfo: chaves de `Status`.
        case status
        /// Helper → Ajustes. userInfo["trigger"]: JSON do botão detectado.
        case learned
        /// Helper → Ajustes. userInfo["line"]: linha do diagnóstico.
        case log
    }

    public enum Command: String {
        case status, learnStart, learnStop, diagnosticsOn, diagnosticsOff
        case requestAccessibility, requestInputMonitoring, quit
    }

    /// Estado do Helper, enviado em resposta a `Command.status` e quando algo muda.
    public struct Status: Equatable {
        public var accessibility = false
        public var inputMonitoring = false
        public var running = false
        public var learning = false
        public var memoryMB = 0.0
        public var devices: [String] = []
        /// Resultado da última aplicação de velocidade/aceleração.
        public var pointerReport = ""

        public init() {}

        public init?(_ info: [AnyHashable: Any]) {
            guard let running = info["running"] as? Bool else { return nil }
            self.running = running
            accessibility = info["ax"] as? Bool ?? false
            inputMonitoring = info["im"] as? Bool ?? false
            learning = info["learning"] as? Bool ?? false
            memoryMB = info["memory"] as? Double ?? 0
            devices = info["devices"] as? [String] ?? []
            pointerReport = info["pointer"] as? String ?? ""
        }

        public var userInfo: [String: Any] {
            ["running": running, "ax": accessibility, "im": inputMonitoring,
             "learning": learning, "memory": memoryMB, "devices": devices, "pointer": pointerReport]
        }
    }

    private static let center = DistributedNotificationCenter.default()
    private static let pidKey = "pid"
    private static var myPID: Int { Int(ProcessInfo.processInfo.processIdentifier) }

    private static func name(_ m: Message) -> Notification.Name {
        Notification.Name("\(appBundleID).\(m.rawValue)")
    }

    public static func post(_ m: Message, _ info: [String: Any] = [:]) {
        var info = info
        info[pidKey] = myPID
        center.postNotificationName(name(m), object: nil, userInfo: info, deliverImmediately: true)
    }

    public static func send(_ c: Command) {
        post(.command, ["cmd": c.rawValue])
    }

    /// O Helper nunca fica "ativo" na tela, então pedimos entrega imediata em vez da padrão,
    /// que seguraria as mensagens até o app ir para a frente.
    public static func observe(_ m: Message, _ handler: @escaping ([AnyHashable: Any]) -> Void) -> NSObjectProtocol {
        let token = center.addObserver(forName: name(m), object: nil, queue: .main) { note in
            let info = note.userInfo ?? [:]
            if info[pidKey] as? Int == myPID { return }
            handler(info)
        }
        center.suspended = false
        return token
    }

    // MARK: Onde fica cada app

    /// O Helper mora dentro do app de ajustes: Mouse Fix Pro.app/Contents/Library/LoginItems/.
    public static func helperURL(fromApp app: URL) -> URL {
        app.appendingPathComponent("Contents/Library/LoginItems/Mouse Fix Pro Helper.app")
    }

    public static func appURL(fromHelper helper: URL) -> URL {
        helper.deletingLastPathComponent() // LoginItems
            .deletingLastPathComponent() // Library
            .deletingLastPathComponent() // Contents
            .deletingLastPathComponent() // Mouse Fix Pro.app
    }
}
