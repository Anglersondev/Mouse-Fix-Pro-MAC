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
    /// O Helper respondeu desde a última inicialização.
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
    private var helperExitObserver: NSObjectProtocol?
    private var launching = false
    private var permissionRefresh: Timer?

    init() {
        observers.append(IPC.observe(.status) { [weak self] info in
            guard let self, let s = IPC.Status(info) else { return }
            if !self.connected {
                self.connected = true
                if self.diagnosticsOn { IPC.send(.diagnosticsOn) }
            }
            if s != self.status { self.status = s }
            self.updatePermissionRefresh()
        })
        observers.append(IPC.observe(.learned) { [weak self] info in
            guard let self, let json = info["trigger"] as? String,
                  let trigger = try? JSONDecoder().decode(Trigger.self, from: Data(json.utf8)) else { return }
            self.learnDone?(trigger)
            self.learnDone = nil
        })
        observers.append(IPC.observe(.log) { [weak self] info in
            guard let self, self.diagnosticsOn, let lines = info["lines"] as? [String] else { return }
            self.log = Array((self.log + lines.suffix(80).map { LogLine(text: $0) }).suffix(80))
        })
        helperExitObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == IPC.helperBundleID, !self.helperIsRunning
            else { return }
            self.connected = false
            self.status = IPC.Status()
            self.learnDone = nil
            self.updatePermissionRefresh()
        }
    }

    deinit {
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        if let helperExitObserver { NSWorkspace.shared.notificationCenter.removeObserver(helperExitObserver) }
        permissionRefresh?.invalidate()
    }

    // MARK: Helper

    static var helperURL: URL { IPC.helperURL(fromApp: Bundle.main.bundleURL) }

    var helperIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: IPC.helperBundleID).isEmpty
    }

    func launchHelper() {
        guard !helperIsRunning, !launching else { return }
        launching = true
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false
        NSWorkspace.shared.openApplication(at: Self.helperURL, configuration: cfg) { [weak self] _, error in
            DispatchQueue.main.async {
                self?.launching = false
                if error == nil { IPC.send(.status) }
            }
        }
    }

    func refreshStatus() {
        IPC.send(.status)
        updatePermissionRefresh()
    }

    private func updatePermissionRefresh() {
        let needsPermission = !status.accessibility || !status.inputMonitoring
        guard connected, NSApp.isActive, needsPermission else {
            permissionRefresh?.invalidate()
            permissionRefresh = nil
            return
        }
        guard permissionRefresh == nil else { return }
        permissionRefresh = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in IPC.send(.status) }
        permissionRefresh?.tolerance = 0.5
    }

    func pausePermissionRefresh() {
        permissionRefresh?.invalidate()
        permissionRefresh = nil
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
