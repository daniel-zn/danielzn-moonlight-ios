//
//  ComputerStore.swift
//  Artemis
//
//  What MainFrameViewController used to do, for SwiftUI: discovery, pairing,
//  wake-on-LAN, app lists and box art, quitting games, starting streams and the
//  home-screen quick actions. The Obj-C network classes do the work; this keeps
//  their TemporaryHost objects and publishes value snapshots of them.
//

import SwiftUI
import UIKit

@Observable
final class ComputerStore {
    // MARK: Published state

    private(set) var computers: [Computer] = []
    private(set) var gamesByHost: [String: [Game]] = [:]
    var path: [Route] = []
    /// A full-screen "working" card (connecting, ending a session, testing the network).
    var busyMessage: String?
    var alert: AlertInfo?
    var pairing: PairingInfo?
    /// Hosts whose apps list shows hidden apps too ("Show All Apps, Including Hidden").
    var showingHiddenGames: Set<String> = []
    private(set) var loadingGames: Set<String> = []
    /// Bumped when new box art arrives, so the rows load it again.
    private(set) var boxArtRevision = 0
    private(set) var isStreaming = false

    /// The host whose games are on screen.
    var selectedHostID: String? {
        if case .games(let id)? = path.last { return id }
        return nil
    }

    // MARK: Plumbing

    @ObservationIgnored let isDemo: Bool
    @ObservationIgnored private var hosts: [String: TemporaryHost] = [:]
    @ObservationIgnored private var discovery: DiscoveryManager?
    @ObservationIgnored private var assetManager: AppAssetManager?
    @ObservationIgnored private let opQueue = OperationQueue()
    @ObservationIgnored private var clientCert: Data?
    @ObservationIgnored private var callbacks: HostCallbacks!
    @ObservationIgnored private var wakingUntil: [String: Date] = [:]
    @ObservationIgnored private var pairingHostID: String?
    @ObservationIgnored private var inBackground = false
    @ObservationIgnored private var started = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// Presents the stream view; calls the closure once it has been dismissed.
    @ObservationIgnored var presentStream: ((StreamConfiguration, @escaping () -> Void) -> Void)?

    init(demo: Bool) {
        isDemo = demo
        callbacks = HostCallbacks(store: self)
    }

    // MARK: Startup and lifecycle

    func start() {
        guard !started else { return }
        started = true

        if isDemo {
            for host in DemoData.makeHosts() {
                hosts[host.uuid] = host
            }
            rebuild()
            return
        }

        // Set up crypto
        CryptoManager.generateKeyPairUsingSSL()
        _ = IdManager.getUniqueId()
        clientCert = CryptoManager.readCertFromFile()

        assetManager = AppAssetManager(callback: callbacks)
        opQueue.maxConcurrentOperationCount = 1

        let saved = (DataManager().getHosts() as? [TemporaryHost]) ?? []
        for host in saved {
            ArtemisBridge.prepareSavedHost(host)
            hosts[host.uuid] = host
        }
        discovery = DiscoveryManager(hosts: Array(hosts.values), andCallback: callbacks)
        rebuild()
        updateShortcuts()
        preloadBoxArt()

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.returnedToForeground()
        })
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.enteredBackground()
        })
        observers.append(center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
            BoxArtCache.shared.removeAll()
        })

        // One PC: open it straight away, as upstream did
        if hosts.count == 1, let only = hosts.keys.first {
            open(only, userInitiated: false)
        }
        beginForegroundRefresh()
    }

    private func returnedToForeground() {
        inBackground = false
        beginForegroundRefresh()
    }

    private func enteredBackground() {
        inBackground = true
        discovery?.stopDiscovery()
    }

    private func beginForegroundRefresh() {
        guard !inBackground, !isStreaming, !isDemo else { return }
        // Reset state first so we can rediscover hosts that were deleted before
        discovery?.resetDiscoveryState()
        discovery?.startDiscovery()

        // Refresh the app list when a paired host is open
        if let id = selectedHostID, let host = hosts[id], host.pairState == .paired {
            open(id, userInitiated: false)
        }
    }

    // MARK: Snapshots

    fileprivate func discoveryUpdated(_ newHosts: [TemporaryHost]) {
        var updated: [String: TemporaryHost] = [:]
        for host in newHosts {
            updated[host.uuid] = host
        }
        hosts = updated
        rebuild()
        updateShortcuts()
    }

    private func rebuild() {
        let now = Date()
        wakingUntil = wakingUntil.filter { $0.value > now }

        var newComputers: [Computer] = []
        var newGames: [String: [Game]] = [:]
        for host in hosts.values {
            let apps = Self.apps(of: host)
            let running = Self.runningApp(of: host)
            let status: ComputerStatus
            switch host.state {
            case .online: status = .online
            case .offline: status = .offline
            default: status = .unknown
            }
            newComputers.append(Computer(
                id: host.uuid,
                name: host.name,
                status: status,
                isPaired: host.pairState == .paired,
                isWaking: wakingUntil[host.uuid] != nil,
                canWake: Self.canWake(host),
                runningGameName: running?.name,
                gameCount: apps.count,
                isNvidia: host.isNvidiaServerSoftware))
            newGames[host.uuid] = apps.map { app in
                Game(hostID: host.uuid, appID: app.id ?? "", name: app.name ?? "",
                     isHidden: app.hidden, isRunning: running?.id == app.id && running != nil)
            }
        }
        newComputers.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if newComputers != computers { computers = newComputers }
        if newGames != gamesByHost { gamesByHost = newGames }
    }

    func computer(_ id: String) -> Computer? {
        computers.first { $0.id == id }
    }

    /// The games on a PC, sorted by name; hidden ones only when asked for.
    func games(for hostID: String) -> [Game] {
        let all = gamesByHost[hostID] ?? []
        return showingHiddenGames.contains(hostID) ? all : all.filter { !$0.isHidden }
    }

    func runningGame(on hostID: String) -> Game? {
        gamesByHost[hostID]?.first { $0.isRunning }
    }

    private static func apps(of host: TemporaryHost) -> [TemporaryApp] {
        host.appList.compactMap { $0 as? TemporaryApp }
            .sorted { ($0.name ?? "").localizedStandardCompare($1.name ?? "") == .orderedAscending }
    }

    private static func runningApp(of host: TemporaryHost) -> TemporaryApp? {
        guard let current = host.currentGame else { return nil }
        return apps(of: host).first { $0.id == current }
    }

    private static func canWake(_ host: TemporaryHost) -> Bool {
        guard let mac = host.mac else { return false }
        return mac != "00:00:00:00:00:00"
    }

    private func app(_ game: Game) -> TemporaryApp? {
        guard let host = hosts[game.hostID] else { return nil }
        return Self.apps(of: host).first { $0.id == game.appID }
    }

    // MARK: Opening a PC

    /// Opens a PC the way the Mac app does: its games when paired, pairing when not,
    /// waking it when it's offline. `userInitiated` false is a refresh (coming back from
    /// a stream or the background, a quick action): no pairing and no error alerts.
    func open(_ id: String, userInitiated: Bool = true) {
        guard let host = hosts[id] else { return }

        if userInitiated && host.state == .offline {
            wake(id)
            return
        }

        if isDemo {
            openDemo(host, userInitiated: userInitiated)
            return
        }

        // The fast path: online, paired and a cached app list. Not after a stream,
        // where serverinfo has to be fetched again for the running game.
        if userInitiated && host.state == .online && host.pairState == .paired && host.appList.count > 0 {
            showGames(id)
            refreshApps(host)
            return
        }

        if userInitiated {
            busyMessage = "Connecting to \(host.name)…"
        }
        let discovery = self.discovery
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Wait for the PC's status to be known
            var waited = 0
            while host.state == .unknown && waited < 20 {
                sleep(1)
                waited += 1
            }
            if host.state != .online {
                DispatchQueue.main.async {
                    self?.busyMessage = nil
                    self?.leaveGames(of: id)
                }
                return
            }

            if let error = ArtemisBridge.refreshServerInfo(for: host, discovery: discovery) {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.busyMessage = nil
                    host.state = .offline
                    self.rebuild()
                    self.leaveGames(of: id)
                    // Only display an alert if this was the result of a real user action
                    if userInitiated {
                        self.alert = AlertInfo(title: "Connection Failed", message: error, showsHelp: true)
                    }
                }
                return
            }

            if host.pairState == .paired {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.busyMessage = nil
                    self.rebuild()
                    if userInitiated || self.selectedHostID == id || self.path.isEmpty {
                        self.showGames(id)
                    }
                    self.refreshApps(host)
                }
            }
            else if userInitiated {
                logInfo("Trying to pair")
                DispatchQueue.main.async { self?.pairingHostID = id }
                // Polling the server while pairing causes the server to screw up
                discovery?.stopDiscoveryBlocking()
                guard let self else { return }
                let manager = PairManager(manager: HttpManager(host: host), clientCert: self.clientCert, callback: self.callbacks)
                self.opQueue.addOperation(manager!)
            }
            else {
                DispatchQueue.main.async {
                    self?.busyMessage = nil
                    self?.rebuild()
                }
            }
        }
    }

    private func showGames(_ id: String) {
        if selectedHostID != id {
            path = [.games(id)]
        }
    }

    private func leaveGames(of id: String) {
        if selectedHostID == id {
            path.removeAll()
        }
    }

    /// Fetches the app list; the cached one shows meanwhile.
    func refreshApps(_ host: TemporaryHost) {
        let id: String = host.uuid
        if isDemo { return }
        loadingGames.insert(id)
        let discovery = self.discovery
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let error = ArtemisBridge.refreshAppList(for: host, discovery: discovery)
            DispatchQueue.main.async {
                guard let self else { return }
                self.loadingGames.remove(id)
                if let error {
                    host.state = .offline
                    self.rebuild()
                    if self.selectedHostID == id {
                        self.path.removeAll()
                        self.alert = AlertInfo(title: "Connection Interrupted", message: error, showsHelp: true)
                    }
                    return
                }
                self.rebuild()
                // This host may be eligible for a shortcut now that the app list has been populated
                self.updateShortcuts()
                self.preloadBoxArt(for: host)
                self.assetManager?.stopRetrieving()
                self.assetManager?.retrieveAssets(from: host)
            }
        }
    }

    func refreshGames(_ hostID: String) {
        open(hostID, userInitiated: false)
    }

    // MARK: Pairing

    fileprivate func pairingStarted(pin: String) {
        guard let id = pairingHostID, let host = hosts[id] else { return }
        busyMessage = nil
        pairing = PairingInfo(hostID: id, hostName: host.name, pin: pin)
    }

    fileprivate func pairingFailed(_ message: String) {
        guard pairingHostID != nil else { return }
        pairingHostID = nil
        pairing = nil
        busyMessage = nil
        discovery?.startDiscovery()
        alert = AlertInfo(title: "Pairing Failed", message: message, showsHelp: true)
    }

    fileprivate func pairingSucceeded(serverCert: Data?) {
        guard let id = pairingHostID, let host = hosts[id] else { return }
        pairingHostID = nil
        pairing = nil
        busyMessage = nil
        if let serverCert {
            // Store the cert from pairing with the host
            host.serverCert = serverCert
        }
        host.pairState = .paired
        DataManager().update(host)
        discovery?.startDiscovery()
        rebuild()
        showGames(id)
        refreshApps(host)
    }

    /// Cancel on the PIN sheet. The host gives up on the attempt by itself.
    func cancelPairing() {
        guard pairingHostID != nil || pairing != nil else { return }
        pairingHostID = nil
        pairing = nil
        if !isDemo {
            discovery?.startDiscovery()
        }
    }

    // MARK: Waking, removing, adding

    func wake(_ id: String) {
        guard let host = hosts[id] else { return }
        guard Self.canWake(host) else {
            alert = AlertInfo(title: "Wake PC", message: "\(host.name) is offline, and Artemis can't wake it because it doesn't know the PC's network address yet. Turn the PC on and pair with it, and Artemis will be able to wake it next time.")
            return
        }
        if !isDemo {
            DispatchQueue.global().async {
                WakeOnLanManager.wake(host)
            }
        }
        wakingUntil[id] = Date().addingTimeInterval(60)
        rebuild()
        DispatchQueue.main.asyncAfter(deadline: .now() + 61) { [weak self] in
            self?.rebuild()
        }
    }

    func remove(_ id: String) {
        guard let host = hosts[id] else { return }
        leaveGames(of: id)
        if !isDemo {
            discovery?.removeHost(fromDiscovery: host)
            DataManager().remove(host)
        }
        hosts[id] = nil
        rebuild()
        updateShortcuts()
    }

    /// Adds a PC by address; the completion gets nil, or the error to show.
    func addComputer(address: String, completion: @escaping (String?) -> Void) {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if isDemo {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                completion("Could not connect to host.\n\nIf you're hosting using Sunshine, ensure it is running properly. If you're using a non-default port, you will need to include that here.")
            }
            return
        }
        guard let discovery else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            discovery.discoverHost(address) { host, error in
                if let host {
                    DispatchQueue.main.async {
                        self?.hosts[host.uuid] = host
                        self?.rebuild()
                        completion(nil)
                    }
                } else {
                    let message = ArtemisBridge.addHostErrorMessage(error ?? "Unable to connect to the specified PC.")
                    DispatchQueue.main.async { completion(message) }
                }
            }
        }
    }

    func testNetwork() {
        busyMessage = "Testing your network…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let message = ArtemisBridge.runNetworkTest()
            DispatchQueue.main.async {
                self?.busyMessage = nil
                self?.alert = AlertInfo(title: "Network Test Complete", message: message)
            }
        }
    }

    // MARK: Games

    func setHidden(_ game: Game, hidden: Bool) {
        guard let app = app(game) else { return }
        if isDemo {
            app.hidden = hidden
        } else {
            ArtemisBridge.setApp(app, hidden: hidden)
        }
        rebuild()
    }

    /// Launches a game, or resumes it when it's the one running.
    func play(_ game: Game) {
        guard let app = app(game) else { return }
        assetManager?.stopRetrieving()
        logInfo(game.isRunning ? "Resuming application: \(game.name)" : "Launching application: \(game.name)")
        let config = ArtemisBridge.streamConfiguration(for: app)
        guard let presentStream else { return }
        isStreaming = true
        discovery?.stopDiscovery()
        presentStream(config) { [weak self] in
            self?.streamEnded()
        }
    }

    private func streamEnded() {
        isStreaming = false
        BoxArtCache.shared.removeAll()
        // Fetch serverinfo again so the running game is right
        if let id = selectedHostID {
            open(id, userInitiated: false)
        }
        beginForegroundRefresh()
    }

    /// Quits the running game on the PC, then starts `next` if given.
    func endGame(on hostID: String, thenStart next: Game? = nil) {
        guard let host = hosts[hostID], let running = runningGame(on: hostID) else { return }
        logInfo("Quitting application: \(running.name)")
        busyMessage = "Ending the session…"
        if isDemo {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                host.currentGame = "0"
                self?.busyMessage = nil
                self?.rebuild()
                if let next { self?.play(next) }
            }
            return
        }
        let discovery = self.discovery
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let quit = ArtemisBridge.quitApp(on: host, discovery: discovery)
            DispatchQueue.main.async {
                guard let self else { return }
                self.busyMessage = nil
                self.rebuild()
                if !quit {
                    self.alert = AlertInfo(title: "Couldn't End the Session", message: "If the session was started from another device, end it from that device.")
                } else if let next, let fresh = self.games(for: hostID).first(where: { $0.appID == next.appID }) {
                    self.play(fresh)
                }
            }
        }
    }

    // MARK: Box art

    fileprivate func receivedAsset(for app: TemporaryApp) {
        boxArtRevision += 1
    }

    func boxArtPath(for game: Game) -> String? {
        if isDemo { return nil }
        guard let app = app(game) else { return nil }
        return AppAssetManager.boxArtPath(for: app)
    }

    /// Decodes box art ahead of the list, as upstream did.
    private func preloadBoxArt(for host: TemporaryHost? = nil) {
        guard !isDemo else { return }
        let targets = host.map { [$0] } ?? Array(hosts.values)
        for host in targets {
            for app in Self.apps(of: host) {
                DispatchQueue.global(qos: .utility).async {
                    _ = BoxArtCache.shared.image(atPath: AppAssetManager.boxArtPath(for: app))
                }
            }
        }
    }

    // MARK: Quick actions

    private func updateShortcuts() {
        guard !isDemo else { return }
        // Pair state may be unknown if we haven't polled it yet, but the app list
        // count will persist from paired PCs
        UIApplication.shared.shortcutItems = computers.filter { $0.gameCount > 0 }.map { computer in
            UIApplicationShortcutItem(type: "PC", localizedTitle: computer.name, localizedSubtitle: nil,
                                      icon: UIApplicationShortcutIcon(systemImageName: "desktopcomputer"),
                                      userInfo: ["UUID": computer.id as NSString])
        }
    }

    /// A home-screen quick action: opens that PC's apps.
    @discardableResult
    func handleShortcut(_ item: UIApplicationShortcutItem) -> Bool {
        guard let uuid = item.userInfo?["UUID"] as? String, hosts[uuid] != nil else { return false }
        if selectedHostID != uuid {
            path.removeAll()
            open(uuid, userInitiated: false)
            if isDemo { showGames(uuid) }
        }
        return true
    }

    // MARK: Demo

    private func openDemo(_ host: TemporaryHost, userInitiated: Bool) {
        let id: String = host.uuid
        if host.pairState == .paired {
            showGames(id)
        } else if userInitiated {
            pairingHostID = id
            pairingStarted(pin: "4821")
        }
    }
}

/// The Obj-C callback protocols, forwarded to the store on the main thread.
private final class HostCallbacks: NSObject, DiscoveryCallback, PairCallback, AppAssetCallback {
    weak var store: ComputerStore?

    init(store: ComputerStore) {
        self.store = store
    }

    func updateAllHosts(_ hosts: [Any]!) {
        // Copied here because discovery can change the array before the main thread runs
        let copy = (hosts ?? []).compactMap { $0 as? TemporaryHost }
        DispatchQueue.main.async { [weak self] in
            self?.store?.discoveryUpdated(copy)
        }
    }

    func startPairing(_ PIN: String!) {
        // Synchronous, so the PIN shows before any failure callback can arrive
        let pin = PIN ?? ""
        DispatchQueue.main.sync {
            store?.pairingStarted(pin: pin)
        }
    }

    func pairSuccessful(_ serverCert: Data!) {
        DispatchQueue.main.async { [weak self] in
            self?.store?.pairingSucceeded(serverCert: serverCert)
        }
    }

    func pairFailed(_ message: String!) {
        let message = message ?? "Pairing failed."
        DispatchQueue.main.async { [weak self] in
            self?.store?.pairingFailed(message)
        }
    }

    func alreadyPaired() {
        DispatchQueue.main.async { [weak self] in
            self?.store?.pairingSucceeded(serverCert: nil)
        }
    }

    func receivedAsset(for app: TemporaryApp!) {
        guard let app else { return }
        // Decode it here so the main thread doesn't have to
        _ = BoxArtCache.shared.image(atPath: AppAssetManager.boxArtPath(for: app), reload: true)
        DispatchQueue.main.async { [weak self] in
            self?.store?.receivedAsset(for: app)
        }
    }
}
