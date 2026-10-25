import Foundation

struct Mapping: Codable, Hashable {
    var trigger: Trigger
    var kind: ClickKind
    var action: Action
}

struct AppProfile: Codable, Hashable, Identifiable {
    var bundleID: String
    var name: String
    var path: String
    var mappings: [Mapping] = []
    var id: String { bundleID }
}

struct ScrollSettings: Codable, Hashable {
    var smooth = true
    var reverse = false
    var speed = 1.0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        smooth = try c.decodeIfPresent(Bool.self, forKey: .smooth) ?? smooth
        reverse = try c.decodeIfPresent(Bool.self, forKey: .reverse) ?? reverse
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? speed
    }
}

struct PointerSettings: Codable, Hashable {
    /// Desligado, o Mouse Fix Pro não mexe no ponteiro e vale o que está nos Ajustes do Sistema.
    var custom = false
    var acceleration = true
    /// 0...1, com 0.5 no meio. Com aceleração vira a "velocidade de rastreamento" do macOS;
    /// sem aceleração vira um multiplicador fixo de 0.25× a 4×.
    var speed = 0.5

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        custom = try c.decodeIfPresent(Bool.self, forKey: .custom) ?? custom
        acceleration = try c.decodeIfPresent(Bool.self, forKey: .acceleration) ?? acceleration
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? speed
    }
}

struct Config: Codable {
    var enabled = true
    var showMenuBarIcon = true
    var showDockIcon = false
    /// Botões que aparecem na tela de configuração, na ordem em que foram adicionados.
    var triggers: [Trigger] = [.button(2), .button(3), .button(4)]
    var mappings: [Mapping] = []
    var profiles: [AppProfile] = []
    var scroll = ScrollSettings()
    var pointer = PointerSettings()

    init() {}

    // Decodificação tolerante: chaves novas em versões futuras não quebram a config antiga.
    init(from decoder: Decoder) throws {
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

typealias ActionTable = [Trigger: [ClickKind: Action]]

/// Guarda a configuração em ~/Library/Application Support/MouseFixPro/config.json
/// e mantém índices prontos para o caminho quente (cada clique consulta só dicionários).
final class ConfigStore: ObservableObject {
    @Published var config: Config {
        didSet {
            rebuildIndex()
            save()
            onChange?()
        }
    }

    /// Chamado depois de qualquer mudança (o núcleo usa para atualizar o monitor HID e a rolagem).
    var onChange: (() -> Void)?

    private(set) var global: ActionTable = [:]
    private(set) var perApp: [String: ActionTable] = [:]
    /// Todos os gatilhos HID que têm alguma ação em algum perfil.
    private(set) var mappedHIDTriggers: Set<Trigger> = []

    private let url: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MouseFixPro", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("config.json")
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(Config.self, from: data) {
            config = saved
        } else {
            config = Config()
        }
        rebuildIndex()
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
        perApp = Dictionary(uniqueKeysWithValues: config.profiles.map { ($0.bundleID, Self.table($0.mappings)) })
        let all = config.mappings + config.profiles.flatMap(\.mappings)
        mappedHIDTriggers = Set(all.map(\.trigger).filter(\.isHID))
    }

    /// Ações efetivas de um gatilho no app da frente: o perfil do app sobrescreve o geral.
    func actions(for trigger: Trigger, app: String?) -> [ClickKind: Action] {
        var result = global[trigger] ?? [:]
        if let app, let overrides = perApp[app]?[trigger] {
            result.merge(overrides) { _, new in new }
        }
        return result
    }

    // MARK: Edição (usado pela interface)

    func action(_ trigger: Trigger, _ kind: ClickKind, profile: String? = nil) -> Action? {
        if let profile { return perApp[profile]?[trigger]?[kind] }
        return global[trigger]?[kind]
    }

    func setAction(_ action: Action?, _ trigger: Trigger, _ kind: ClickKind, profile: String? = nil) {
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

    func addTrigger(_ trigger: Trigger) {
        if !config.triggers.contains(trigger) { config.triggers.append(trigger) }
    }

    func removeTrigger(_ trigger: Trigger) {
        var c = config
        c.triggers.removeAll { $0 == trigger }
        c.mappings.removeAll { $0.trigger == trigger }
        for i in c.profiles.indices { c.profiles[i].mappings.removeAll { $0.trigger == trigger } }
        config = c
    }
}
