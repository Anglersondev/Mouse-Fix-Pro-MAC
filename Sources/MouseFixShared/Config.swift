import Foundation

public struct Mapping: Codable, Hashable {
    public var trigger: Trigger
    public var kind: ClickKind
    public var action: Action

    public init(trigger: Trigger, kind: ClickKind, action: Action) {
        self.trigger = trigger
        self.kind = kind
        self.action = action
    }
}

public struct AppProfile: Codable, Hashable, Identifiable {
    public var bundleID: String
    public var name: String
    public var path: String
    public var mappings: [Mapping] = []
    public var id: String { bundleID }

    public init(bundleID: String, name: String, path: String) {
        self.bundleID = bundleID
        self.name = name
        self.path = path
    }
}

public struct ScrollSettings: Codable, Hashable {
    public var smooth = true
    public var reverse = false
    public var speed = 1.0

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        smooth = try c.decodeIfPresent(Bool.self, forKey: .smooth) ?? smooth
        reverse = try c.decodeIfPresent(Bool.self, forKey: .reverse) ?? reverse
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? speed
    }
}

public struct PointerSettings: Codable, Hashable {
    /// Desligado, o Mouse Fix Pro não mexe no ponteiro e vale o que está nos Ajustes do Sistema.
    public var custom = false
    public var acceleration = true
    /// 0...1, com 0.5 no meio. Com aceleração vira a "velocidade de rastreamento" do macOS;
    /// sem aceleração vira um multiplicador fixo de 0.25× a 4×.
    public var speed = 0.5

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        custom = try c.decodeIfPresent(Bool.self, forKey: .custom) ?? custom
        acceleration = try c.decodeIfPresent(Bool.self, forKey: .acceleration) ?? acceleration
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? speed
    }
}

public struct Config: Codable {
    public var enabled = true
    public var showMenuBarIcon = true
    public var showDockIcon = false
    /// Botões que aparecem na tela de configuração, na ordem em que foram adicionados.
    public var triggers: [Trigger] = [.button(2), .button(3), .button(4)]
    public var mappings: [Mapping] = []
    public var profiles: [AppProfile] = []
    public var scroll = ScrollSettings()
    public var pointer = PointerSettings()

    public init() {}

    // Decodificação tolerante: chaves novas em versões futuras não quebram a config antiga.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        showMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? showMenuBarIcon
        showDockIcon = try c.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? showDockIcon
        triggers = try c.decodeIfPresent([Trigger].self, forKey: .triggers) ?? triggers
        mappings = try c.decodeIfPresent([Mapping].self, forKey: .mappings) ?? mappings
        profiles = try c.decodeIfPresent([AppProfile].self, forKey: .profiles) ?? profiles
        scroll = try c.decodeIfPresent(ScrollSettings.self, forKey: .scroll) ?? scroll
        pointer = try c.decodeIfPresent(PointerSettings.self, forKey: .pointer) ?? pointer
    }
}

public typealias ActionTable = [Trigger: [ClickKind: Action]]

/// Guarda a configuração em ~/Library/Application Support/MouseFixPro/config.json e mantém
/// índices prontos para o caminho quente (cada clique consulta só dicionários).
///
/// O app de ajustes e o Helper usam o mesmo arquivo: quem salva avisa o outro, que relê.
public final class ConfigStore: ObservableObject {
    @Published public var config: Config {
        didSet {
            rebuildIndex()
            if !reloading {
                save()
                IPC.post(.configChanged)
            }
            onChange?()
        }
    }

    /// Chamado depois de qualquer mudança, inclusive vinda do outro processo.
    public var onChange: (() -> Void)?

    public private(set) var global: ActionTable = [:]
    public private(set) var perApp: [String: ActionTable] = [:]
    /// Todos os gatilhos HID que têm alguma ação em algum perfil.
    public private(set) var mappedHIDTriggers: Set<Trigger> = []

    private let url: URL
    private var reloading = false
    private var observer: NSObjectProtocol?

    public init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MouseFixPro", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("config.json")
        config = Self.load(url) ?? Config()
        rebuildIndex()
        observer = IPC.observe(.configChanged) { [weak self] _ in self?.reload() }
    }

    private static func load(_ url: URL) -> Config? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Config.self, from: data)
    }

    public func reload() {
        guard let fresh = Self.load(url) else { return }
        reloading = true
        config = fresh
        reloading = false
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func table(_ mappings: [Mapping]) -> ActionTable {
        var t: ActionTable = [:]
        for m in mappings { t[m.trigger, default: [:]][m.kind] = m.action }
        return t
    }

    private func rebuildIndex() {
        global = Self.table(config.mappings)
        perApp = Dictionary(config.profiles.map { ($0.bundleID, Self.table($0.mappings)) }, uniquingKeysWith: { a, _ in a })
        let all = config.mappings + config.profiles.flatMap(\.mappings)
        mappedHIDTriggers = Set(all.map(\.trigger).filter(\.isHID))
    }

    /// Ações efetivas de um gatilho no app da frente: o perfil do app sobrescreve o geral.
    public func actions(for trigger: Trigger, app: String?) -> [ClickKind: Action] {
        var result = global[trigger] ?? [:]
        if let app, let overrides = perApp[app]?[trigger] {
            result.merge(overrides) { _, new in new }
        }
        return result
    }

    // MARK: Edição (usado pela interface)

    public func action(_ trigger: Trigger, _ kind: ClickKind, profile: String? = nil) -> Action? {
        if let profile { return perApp[profile]?[trigger]?[kind] }
        return global[trigger]?[kind]
    }

    public func setAction(_ action: Action?, _ trigger: Trigger, _ kind: ClickKind, profile: String? = nil) {
        func apply(_ list: inout [Mapping]) {
            list.removeAll { $0.trigger == trigger && $0.kind == kind }
            if let action { list.append(Mapping(trigger: trigger, kind: kind, action: action)) }
        }
        if let profile, let i = config.profiles.firstIndex(where: { $0.bundleID == profile }) {
            apply(&config.profiles[i].mappings)
        } else if profile == nil {
            apply(&config.mappings)
        }
    }

    public func addTrigger(_ trigger: Trigger) {
        if !config.triggers.contains(trigger) { config.triggers.append(trigger) }
    }

    public func removeTrigger(_ trigger: Trigger) {
        var c = config
        c.triggers.removeAll { $0 == trigger }
        c.mappings.removeAll { $0.trigger == trigger }
        for i in c.profiles.indices { c.profiles[i].mappings.removeAll { $0.trigger == trigger } }
        config = c
    }
}
