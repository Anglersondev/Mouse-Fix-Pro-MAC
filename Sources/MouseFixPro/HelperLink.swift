import AppKit
import MouseFixShared
import ServiceManagement

/// O lado do app de ajustes na conversa com o Mouse Fix Pro Helper.
final class HelperLink: ObservableObject {
    struct Device: Identifiable, Hashable {
        let name: String
        let transport: String
        let ids: String
        var id: String { "\(name)|\(ids)" }
    }

    struct LogLine: Identifiable {
        let id = UUID()
        let text: String
    }

    @Published private(set) var status = IPC.Status()
    /// Já ouvimos o Helper alguma vez desde que a janela abriu.
    @Published private(set) var connected = false
    @Published private(set) var log: [LogLine] = []

    var running: Bool { status.running }
    var learning: Bool { status.learning }
    var devices: [Device] {
        status.devices.map {
            let p = $0.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            return Device(name: p.first ?? "?", transport: p.count > 1 ? p[1] : "?", ids: p.count > 2 ? p[2] : "")
        }
    }

    var diagnosticsOn = false {
        didSet { IPC.send(diagnosticsOn ? .diagnosticsOn : .diagnosticsOff) }
    }

    private var learnDone: ((Trigger) -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?

    init() {
        observers.append(IPC.observe(.status) { [weak self] info in
            guard let self, let s = IPC.Status(info) else { return }
            self.connected = true
            if s != self.status { self.status = s }
        })
        observers.append(IPC.observe(.learned) { [weak self] info in
            guard let self, let json = info["trigger"] as? String,
                  let trigger = try? JSONDecoder().decode(Trigger.self, from: Data(json.utf8)) else { return }
            self.learnDone?(trigger)
            self.learnDone = nil
        })
        observers.append(IPC.observe(.log) { [weak self] info in
            guard let self, let line = info["line"] as? String else { return }
            self.log.append(LogLine(text: line))
            if self.log.count > 80 { self.log.removeFirst(self.log.count - 80) }
        })
    }

    deinit {
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        timer?.invalidate()
    }

    // MARK: Helper

    static var helperURL: URL { IPC.helperURL(fromApp: Bundle.main.bundleURL) }

    var helperIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: IPC.helperBundleID).isEmpty
    }

    func launchHelper() {
        guard !helperIsRunning else { return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false
        NSWorkspace.shared.openApplication(at: Self.helperURL, configuration: cfg) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { IPC.send(.status) }
        }
    }

    /// Pergunta o estado do Helper a cada 1,5 s enquanto a janela está aberta (permissões, memória).
    func startPolling() {
        guard timer == nil else { return }
        IPC.send(.status)
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if !self.helperIsRunning { self.launchHelper() }
            IPC.send(.status)
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func quitHelper() {
        IPC.send(.quit)
    }

    /// Reabre o Helper e esta janela (ex.: depois de trocar o idioma).
    func relaunchEverything() {
        IPC.send(.quit)
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.createsNewApplicationInstance = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: cfg) { _, _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        }
    }

    // MARK: Ações

    func startLearning(_ done: @escaping (Trigger) -> Void) {
        learnDone = done
        status.learning = true
        IPC.send(.learnStart)
    }

    func cancelLearning() {
        learnDone = nil
        status.learning = false
        IPC.send(.learnStop)
    }

    func clearLog() { log.removeAll() }

    func requestAccessibility() { IPC.send(.requestAccessibility) }
    func requestInputMonitoring() { IPC.send(.requestInputMonitoring) }

    // MARK: Abrir ao ligar o Mac (registra o Helper, não a janela)

    private var loginItem: SMAppService { .loginItem(identifier: IPC.helperBundleID) }

    var launchAtLogin: Bool { loginItem.status == .enabled }

    func setLaunchAtLogin(_ on: Bool) throws {
        if on { try loginItem.register() } else { try loginItem.unregister() }
        objectWillChange.send()
    }
}
