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
    @Published private(set) var restarting = false
    @Published private(set) var helperError = false
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
    private var permissionVisit = false
    private var leftForPermissions = false
    private var restartTimeout: DispatchWorkItem?
    private let expectedBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    private var triedReplacingOldHelper = false

    init() {
        observers.append(IPC.observe(.status) { [weak self] info in
            guard let self, !self.restarting, self.isFromCurrentHelper(info),
                  let s = IPC.Status(info) else { return }
            guard s.helperBuild == self.expectedBuild else {
                guard !self.launching else { return }
                if self.triedReplacingOldHelper {
                    self.helperError = true
                } else {
                    self.triedReplacingOldHelper = true
                    self.restartHelper()
                }
                return
            }
            self.triedReplacingOldHelper = false
            self.helperError = false
            if !self.connected {
                self.connected = true
                if self.diagnosticsOn { IPC.send(.diagnosticsOn) }
            }
            if s != self.status { self.status = s }
            self.updatePermissionRefresh()
        })
        observers.append(IPC.observe(.learned) { [weak self] info in
            guard let self, self.isFromCurrentHelper(info), let json = info["trigger"] as? String,
                  let trigger = try? JSONDecoder().decode(Trigger.self, from: Data(json.utf8)) else { return }
            self.learnDone?(trigger)
            self.learnDone = nil
        })
        observers.append(IPC.observe(.log) { [weak self] info in
            guard let self, self.diagnosticsOn, self.isFromCurrentHelper(info),
                  let lines = info["lines"] as? [String] else { return }
            self.log = Array((self.log + lines.suffix(80).map { LogLine(text: $0) }).suffix(80))
        })
        helperExitObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == IPC.helperBundleID
            else { return }
            if self.restarting {
                self.finishRestartIfStopped()
            } else if self.isCurrentHelper(app), !self.helperIsRunning {
                self.resetConnection()
                if self.permissionVisit && NSApp.isActive { self.launchHelper() }
            }
        }
    }

    deinit {
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        if let helperExitObserver { NSWorkspace.shared.notificationCenter.removeObserver(helperExitObserver) }
        permissionRefresh?.invalidate()
        restartTimeout?.cancel()
    }

    // MARK: Helper

    static var helperURL: URL { IPC.helperURL(fromApp: Bundle.main.bundleURL) }

    private var helpers: [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: IPC.helperBundleID).filter { !$0.isTerminated }
    }

    private func isCurrentHelper(_ application: NSRunningApplication) -> Bool {
        application.bundleURL?.resolvingSymlinksInPath().path == Self.helperURL.resolvingSymlinksInPath().path
    }

    private func isFromCurrentHelper(_ info: [AnyHashable: Any]) -> Bool {
        guard let pid = info["pid"] as? Int, let processID = pid_t(exactly: pid),
              let app = NSRunningApplication(processIdentifier: processID),
              app.bundleIdentifier == IPC.helperBundleID else { return false }
        return isCurrentHelper(app)
    }

    private var helperIsRunning: Bool { helpers.contains(where: isCurrentHelper) }

    func launchHelper() {
        guard !launching, !restarting else { return }
        let runningHelpers = helpers
        if runningHelpers.contains(where: { !isCurrentHelper($0) }) {
            restartHelper()
            return
        }
        guard runningHelpers.isEmpty else { return }
        helperError = false
        launching = true
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false
        NSWorkspace.shared.openApplication(at: Self.helperURL, configuration: cfg) { [weak self] app, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.launching = false
                if let app, error == nil, self.isCurrentHelper(app) {
                    IPC.send(.status)
                } else {
                    self.helperError = true
                }
            }
        }
    }

    func restartHelper() {
        guard !restarting, !launching else { return }
        permissionVisit = false
        leftForPermissions = false
        let runningHelpers = helpers
        resetConnection()
        guard !runningHelpers.isEmpty else {
            launchHelper()
            return
        }

        restarting = true
        helperError = false
        for helper in runningHelpers { _ = helper.terminate() }
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.restarting else { return }
            if self.helpers.isEmpty {
                self.finishRestartIfStopped()
            } else {
                self.restarting = false
                self.helperError = true
                self.restartTimeout = nil
            }
        }
        restartTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: timeout)
    }

    private func finishRestartIfStopped() {
        guard helpers.isEmpty else { return }
        restartTimeout?.cancel()
        restartTimeout = nil
        restarting = false
        launchHelper()
    }

    private func resetConnection() {
        connected = false
        status = IPC.Status()
        learnDone = nil
        updatePermissionRefresh()
    }

    func refreshStatus() {
        if leftForPermissions {
            restartHelper()
        } else {
            IPC.send(.status)
        }
        updatePermissionRefresh()
    }

    private func updatePermissionRefresh() {
        let needsPermission = !status.accessibility || !status.running || !status.hidReady
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
        if permissionVisit { leftForPermissions = true }
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

    func requestAccessibility() {
        permissionVisit = true
        IPC.send(.requestAccessibility)
    }

    func requestInputMonitoring() {
        permissionVisit = true
        IPC.send(.requestInputMonitoring)
    }

    func revealHelper() {
        NSWorkspace.shared.activateFileViewerSelecting([Self.helperURL])
    }

    // MARK: Abrir ao ligar o Mac (registra o Helper, não a janela)

    private var loginItem: SMAppService { .loginItem(identifier: IPC.helperBundleID) }

    var launchAtLogin: Bool { loginItem.status == .enabled }

    func setLaunchAtLogin(_ on: Bool) throws {
        if on { try loginItem.register() } else { try loginItem.unregister() }
        objectWillChange.send()
    }
}
