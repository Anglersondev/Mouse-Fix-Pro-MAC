import MouseFixShared
import AppKit
import IOKit.hid

/// Velocidade e aceleração do ponteiro, aplicadas direto no driver HID.
///
/// Não há event tap de movimento nem timer: o próprio macOS passa a mover o ponteiro com a curva
/// nova, então o custo em CPU é zero. O porém é que o sistema reaplica os valores dele quando o
/// mouse reconecta, o Mac acorda ou a tela é desbloqueada; por isso reaplicamos nesses momentos.
///
/// Dois caminhos, porque cada versão do macOS respeita um deles:
/// 1. por mouse, via IOHIDEventSystemClient (o mesmo que o `hidutil` usa);
/// 2. global, via IOHIDSystem (o mesmo que o painel de Mouse antigo usava).
///
/// Sem aceleração, a curva fica em 0 (linear) e a velocidade vem da resolução do ponteiro:
/// resolução menor = ponteiro mais rápido. Não usamos aceleração negativa, que no macOS deixa
/// o ponteiro lento e ignora a resolução.
final class PointerManager {
    private typealias CreateClient = @convention(c) (CFAllocator?) -> UnsafeMutableRawPointer?
    private typealias CopyServices = @convention(c) (UnsafeMutableRawPointer) -> Unmanaged<CFArray>?
    private typealias ConformsTo = @convention(c) (UnsafeRawPointer, UInt32, UInt32) -> UInt8
    private typealias CopyProperty = @convention(c) (UnsafeRawPointer, CFString) -> Unmanaged<CFTypeRef>?
    private typealias SetProperty = @convention(c) (UnsafeRawPointer, CFString, CFTypeRef) -> UInt8
    private typealias OpenEventStatus = @convention(c) () -> UInt32
    private typealias SetCFTypeParameter = @convention(c) (UInt32, CFString, CFTypeRef) -> Int32

    private struct API {
        let createClient: CreateClient
        let copyServices: CopyServices
        let conformsTo: ConformsTo
        let copyProperty: CopyProperty
        let setProperty: SetProperty
    }

    private struct LegacyAPI {
        let open: OpenEventStatus
        let set: SetCFTypeParameter
    }

    private static let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)

    private static func load<T>(_ name: String, _: T.Type) -> T? {
        guard let handle else { return nil }
        return dlsym(handle, name).map { unsafeBitCast($0, to: T.self) }
    }

    /// Funções do IOHIDEventSystemClient, carregadas em tempo de execução.
    private static let api: API? = {
        guard let a = load("IOHIDEventSystemClientCreateSimpleClient", CreateClient.self),
              let b = load("IOHIDEventSystemClientCopyServices", CopyServices.self),
              let c = load("IOHIDServiceClientConformsTo", ConformsTo.self),
              let d = load("IOHIDServiceClientCopyProperty", CopyProperty.self),
              let e = load("IOHIDServiceClientSetProperty", SetProperty.self)
        else { return nil }
        return API(createClient: a, copyServices: b, conformsTo: c, copyProperty: d, setProperty: e)
    }()

    private static let legacy: LegacyAPI? = {
        guard let a = load("NXOpenEventStatus", OpenEventStatus.self),
              let b = load("IOHIDSetCFTypeParameter", SetCFTypeParameter.self)
        else { return nil }
        return LegacyAPI(open: a, set: b)
    }()

    private static let accelerationKeys = ["HIDMouseAcceleration", "HIDPointerAcceleration"] as [CFString]
    private static let resolutionKey = "HIDPointerResolution" as CFString
    /// Resolução padrão do IOHIDFamily: 400 dpi em ponto fixo 16.16.
    private static let defaultResolution = 400 * 65536

    private lazy var client: UnsafeMutableRawPointer? = Self.api?.createClient(kCFAllocatorDefault)
    private lazy var eventStatus: UInt32 = Self.legacy?.open() ?? 0
    private var touched = false
    private var settings = PointerSettings()
    private var observers: [NSObjectProtocol] = []

    /// Resumo da última aplicação, mostrado na aba Ponteiro.
    private(set) var report = ""
    var onReport: (() -> Void)?

    init() {
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.reapplySoon() })
        }
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in self?.reapplySoon() })
    }

    func update(_ new: PointerSettings) {
        guard new != settings else { return }
        settings = new
        apply()
    }

    /// Mouse conectado ou acordado: o sistema pode demorar um pouco para reaplicar os valores dele,
    /// então aplicamos de novo logo depois e mais uma vez em seguida.
    func reapplySoon() {
        guard settings.custom || touched else { return }
        for delay in [0.3, 1.5, 4.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.apply() }
        }
    }

    /// Devolve o controle ao macOS (ao sair do app).
    func restore() {
        guard touched else { return }
        var s = settings
        s.custom = false
        settings = s
        apply()
    }

    func apply() {
        if !settings.custom && !touched { return }

        let acceleration: Double
        var resolution = Self.defaultResolution
        if !settings.custom {
            acceleration = systemAcceleration()
        } else if settings.acceleration {
            acceleration = settings.speed * 3 // escala do controle "Velocidade de rastreamento" (0 a 3)
        } else {
            acceleration = 0 // curva linear: mesma distância para o mesmo movimento
            let multiplier = pow(4, settings.speed * 2 - 1) // 0.25× a 4×, 1× no meio
            resolution = max(5 * 65536, min(1995 * 65536, Int(Double(Self.defaultResolution) / multiplier)))
        }
        let accel = NSNumber(value: Int(acceleration * 65536))
        let res = NSNumber(value: resolution)

        // 1. Por mouse.
        var names: [String] = []
        var serviceOK = true
        if let api = Self.api, let client, let services = api.copyServices(client)?.takeRetainedValue() {
            for i in 0 ..< CFArrayGetCount(services) {
                guard let service = CFArrayGetValueAtIndex(services, i), isExternalMouse(service, api) else { continue }
                names.append(api.copyProperty(service, kIOHIDProductKey as CFString)
                    .flatMap { $0.takeRetainedValue() as? String } ?? "mouse")
                for k in Self.accelerationKeys { _ = api.setProperty(service, k, accel) }
                _ = api.setProperty(service, Self.resolutionKey, res)
                let readBack = (api.copyProperty(service, Self.resolutionKey)?.takeRetainedValue() as? NSNumber)?.intValue
                if readBack != resolution { serviceOK = false }
            }
        } else {
            serviceOK = false
        }

        // 2. Global, para todos os mouses (a aceleração de mouse não mexe no trackpad).
        var legacyOK = false
        if let legacy = Self.legacy, eventStatus != 0 {
            let a = legacy.set(eventStatus, "HIDMouseAcceleration" as CFString, accel)
            // Alguns macOS guardam a resolução por mouse mas só leem a global; mandamos as duas.
            let r = legacy.set(eventStatus, Self.resolutionKey, res)
            legacyOK = a == KERN_SUCCESS && r == KERN_SUCCESS
        }

        touched = settings.custom
        let mice = names.isEmpty ? L("nenhum mouse externo encontrado", "no external mouse found") : names.joined(separator: ", ")
        report = "\(mice) · " + L("driver", "driver") + ": \(serviceOK && !names.isEmpty ? "ok" : "–") · "
            + L("sistema", "system") + ": \(legacyOK ? "ok" : "–")"
        onReport?()
    }

    // MARK: Ajudantes

    private func isExternalMouse(_ service: UnsafeRawPointer, _ api: API) -> Bool {
        let page = UInt32(kHIDPage_GenericDesktop)
        let isPointing = api.conformsTo(service, page, UInt32(kHIDUsage_GD_Mouse)) != 0
            || api.conformsTo(service, page, UInt32(kHIDUsage_GD_Pointer)) != 0
        let isTouchpad = api.conformsTo(service, UInt32(kHIDPage_Digitizer), UInt32(kHIDUsage_Dig_TouchPad)) != 0
        let builtIn = (api.copyProperty(service, "Built-In" as CFString)?.takeRetainedValue() as? Bool) ?? false
        return isPointing && !isTouchpad && !builtIn
    }

    /// Aceleração escolhida nos Ajustes do Sistema (padrão do macOS: 0.6875).
    private func systemAcceleration() -> Double {
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["com.apple.mouse.scaling"] as? Double ?? 0.6875
    }
}
