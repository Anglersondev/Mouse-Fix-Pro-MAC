import AppKit
import IOKit.hid

/// Velocidade e aceleração do ponteiro, aplicadas direto no driver HID de cada mouse.
///
/// Não há event tap de movimento nem timer: o próprio macOS passa a mover o ponteiro com a curva
/// nova, então o custo em CPU é zero. O porém é que o sistema reaplica os valores dele quando o
/// mouse reconecta, o Mac acorda ou a tela é desbloqueada; por isso reaplicamos nesses momentos.
final class PointerManager {
    private typealias CreateClient = @convention(c) (CFAllocator?) -> UnsafeMutableRawPointer?
    private typealias CopyServices = @convention(c) (UnsafeMutableRawPointer) -> Unmanaged<CFArray>?
    private typealias ConformsTo = @convention(c) (UnsafeRawPointer, UInt32, UInt32) -> UInt8
    private typealias CopyProperty = @convention(c) (UnsafeRawPointer, CFString) -> Unmanaged<CFTypeRef>?
    private typealias SetProperty = @convention(c) (UnsafeRawPointer, CFString, CFTypeRef) -> UInt8

    private struct API {
        let createClient: CreateClient
        let copyServices: CopyServices
        let conformsTo: ConformsTo
        let copyProperty: CopyProperty
        let setProperty: SetProperty
    }

    /// Funções do IOHIDEventSystemClient, carregadas em tempo de execução.
    private static let api: API? = {
        guard let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else { return nil }
        func load<T>(_ name: String, _: T.Type) -> T? {
            dlsym(h, name).map { unsafeBitCast($0, to: T.self) }
        }
        guard let a = load("IOHIDEventSystemClientCreateSimpleClient", CreateClient.self),
              let b = load("IOHIDEventSystemClientCopyServices", CopyServices.self),
              let c = load("IOHIDServiceClientConformsTo", ConformsTo.self),
              let d = load("IOHIDServiceClientCopyProperty", CopyProperty.self),
              let e = load("IOHIDServiceClientSetProperty", SetProperty.self)
        else { return nil }
        return API(createClient: a, copyServices: b, conformsTo: c, copyProperty: d, setProperty: e)
    }()

    private static let accelerationKeys = ["HIDMouseAcceleration", "HIDPointerAcceleration"] as [CFString]
    private static let resolutionKey = "HIDPointerResolution" as CFString
    /// Resolução padrão do IOHIDFamily: 400 dpi em ponto fixo 16.16.
    private static let defaultResolution = 400 * 65536

    private lazy var client: UnsafeMutableRawPointer? = Self.api?.createClient(kCFAllocatorDefault)
    /// Resolução original de cada mouse antes de a gente mexer, para restaurar.
    private var originalResolution: [String: Int] = [:]
    private var touched = false
    private var settings = PointerSettings()
    private var observers: [NSObjectProtocol] = []

    var isAvailable: Bool { Self.api != nil }

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
        guard let api = Self.api, let client, let services = api.copyServices(client)?.takeRetainedValue() else { return }
        if !settings.custom && !touched { return }

        for i in 0 ..< CFArrayGetCount(services) {
            guard let service = CFArrayGetValueAtIndex(services, i) else { continue }
            guard isExternalMouse(service, api) else { continue }
            let key = identity(of: service, api)
            if originalResolution[key] == nil {
                originalResolution[key] = number(api.copyProperty(service, Self.resolutionKey)) ?? Self.defaultResolution
            }
            let baseResolution = originalResolution[key] ?? Self.defaultResolution

            let acceleration: Double
            var resolution = baseResolution
            if !settings.custom {
                acceleration = systemAcceleration()
            } else if settings.acceleration {
                acceleration = settings.speed * 3 // escala do controle "Velocidade de rastreamento" (0 a 3)
            } else {
                acceleration = -1 // valor negativo desliga a curva de aceleração no driver
                let multiplier = pow(4, settings.speed * 2 - 1) // 0.25× a 4×, 1× no meio
                resolution = max(1, Int(Double(baseResolution) / multiplier))
            }

            let accel = NSNumber(value: Int(acceleration * 65536))
            for k in Self.accelerationKeys { _ = api.setProperty(service, k, accel) }
            _ = api.setProperty(service, Self.resolutionKey, NSNumber(value: resolution))
        }
        touched = settings.custom
    }

    // MARK: Ajudantes

    private func isExternalMouse(_ service: UnsafeRawPointer, _ api: API) -> Bool {
        let isMouse = api.conformsTo(service, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Mouse)) != 0
        let isTouchpad = api.conformsTo(service, UInt32(kHIDPage_Digitizer), UInt32(kHIDUsage_Dig_TouchPad)) != 0
        let builtIn = (api.copyProperty(service, "Built-In" as CFString)?.takeRetainedValue() as? Bool) ?? false
        return isMouse && !isTouchpad && !builtIn
    }

    private func identity(of service: UnsafeRawPointer, _ api: API) -> String {
        let parts = ["VendorID", "ProductID", "LocationID", "SerialNumber"].map {
            api.copyProperty(service, $0 as CFString).map { "\($0.takeRetainedValue())" } ?? "-"
        }
        return parts.joined(separator: ":")
    }

    private func number(_ value: Unmanaged<CFTypeRef>?) -> Int? {
        (value?.takeRetainedValue() as? NSNumber)?.intValue
    }

    /// Aceleração escolhida nos Ajustes do Sistema (padrão do macOS: 0.6875).
    private func systemAcceleration() -> Double {
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["com.apple.mouse.scaling"] as? Double ?? 0.6875
    }
}
