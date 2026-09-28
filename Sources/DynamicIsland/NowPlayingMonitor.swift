import AppKit
import SwiftUI

/// Suit la lecture en cours. Source principale : l'« À l'écoute » de macOS via
/// MediaRemoteBridge (Deezer, Spotify, Musique, navigateurs…). En secours : les
/// notifications distribuées de Musique et Spotify, avec AppleScript pour les contrôles.
final class NowPlayingMonitor: ObservableObject {
    enum Source: String {
        case music = "com.apple.Music"
        case spotify = "com.spotify.client"
        var appName: String { self == .music ? "Music" : "Spotify" }
        var displayName: String { self == .music ? "Musique" : "Spotify" }
    }

    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var album = ""
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: Double = 0
    @Published private(set) var artwork: NSImage?
    @Published fileprivate(set) var accent: Color = .white
    @Published private(set) var source: Source?
    /// Nom de l'app qui joue (« Deezer », « Safari »…).
    @Published private(set) var appName: String?
    /// Dernier instant où quelque chose jouait (l'île reste affichée un moment en pause).
    @Published private(set) var lastPlayedAt: Date?
    /// Lecteurs entre lesquels on peut basculer (Deezer, YouTube dans Safari…).
    @Published private(set) var sources: [MediaSource] = []

    private var positionAnchor: Double = 0
    private var anchorDate = Date()
    private var artworkKey = ""
    private var bridge: MediaRemoteBridge?
    private var appNames: [String: String] = [:]
    private var currentBundle: String?
    private var sourceOrder: [String] = []
    private var lastTracks: [String: String] = [:]
    /// Apps enregistrées comme lecteur auprès de macOS (joignables par MediaRemote).
    private var clients: [String] = []
    private var pendingClear: DispatchWorkItem?
    /// Titres du menu « Lecture » des apps sans AppleScript (Deezer : Lecture / Play…).
    private static let playMenuTitles: Set<String> = ["Lecture", "Play", "Wiedergabe", "Reproducir", "Ascolta",
                                                     "Reproduzir", "Afspil", "Spela", "Toista", "Spill"]
    /// Apps de musique proposées dès qu'elles sont ouvertes, même sans lecture en cours.
    private static let musicApps = ["com.deezer.deezer-desktop", "com.spotify.client", "com.apple.Music"]

    var hasTrack: Bool { !title.isEmpty }

    func position(at date: Date) -> Double {
        let p = positionAnchor + (isPlaying ? date.timeIntervalSince(anchorDate) : 0)
        return duration > 0 ? min(max(p, 0), duration) : max(p, 0)
    }

    func start() {
        let bridge = MediaRemoteBridge()
        bridge.onState = { [weak self] in self?.applyBridge($0) }
        bridge.onFailure = { [weak self] in
            self?.bridge = nil
            self?.startLegacy()
        }
        self.bridge = bridge
        bridge.start()
    }

    private func startLegacy() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(musicInfo(_:)),
                        name: Notification.Name("com.apple.Music.playerInfo"), object: nil)
        dnc.addObserver(self, selector: #selector(spotifyInfo(_:)),
                        name: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appTerminated(_:)),
                        name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        for s in [Source.spotify, .music] where isRunning(s) { fetchInitialState(s) }
    }

    // MARK: - Contrôles

    func togglePlayPause() {
        if let bridge { bridge.send(.togglePlayPause) } else { send("playpause") }
    }
    func nextTrack() {
        if let bridge { bridge.send(.nextTrack) } else { send("next track") }
    }
    func previousTrack() {
        if let bridge { bridge.send(.previousTrack) } else { send("previous track") }
    }

    func seek(to seconds: Double) {
        if let bridge {
            bridge.seek(to: seconds)
        } else {
            guard let s = source, isRunning(s) else { return }
            AppleScript.run("tell application \"\(s.appName)\" to set player position to \(seconds)")
        }
        positionAnchor = seconds
        anchorDate = Date()
        objectWillChange.send()
    }

    /// Lance la lecture dans `bundleID` puis met en pause le lecteur actuel.
    /// Le lecteur actuel n'est mis en pause que si l'autre a bien pu démarrer.
    func switchTo(_ bundleID: String) {
        guard let bridge else { return }
        if bundleID == currentBundle {
            bridge.send(.togglePlayPause)
            return
        }
        let current = isPlaying ? currentBundle : nil
        let pauseCurrent = { if let current { bridge.send(.pause, to: current) } }

        // 1. L'app est un lecteur enregistré : commande MediaRemote directe.
        if clients.contains(bundleID) {
            pauseCurrent()
            bridge.send(.play, to: bundleID)
            return
        }
        // 2. Musique et Spotify comprennent AppleScript.
        if let legacy = Source(rawValue: bundleID) {
            pauseCurrent()
            AppleScript.run("tell application \"\(legacy.appName)\" to play")
            return
        }
        // 3. Sinon (Deezer…) : on clique sur « Lecture » dans son menu, via l'accessibilité.
        guard AccessibilityControl.isTrusted else {
            AccessibilityControl.requestTrust()
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = AccessibilityControl.pressMenuItem(of: bundleID, titles: Self.playMenuTitles)
            DispatchQueue.main.async {
                if ok {
                    pauseCurrent()
                } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                    // Dernier recours : on ouvre l'app pour lancer la lecture à la main.
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                }
            }
        }
    }

    // MARK: - MediaRemote

    private func applyBridge(_ s: MediaRemoteBridge.State) {
        currentBundle = s.title.isEmpty ? nil : s.bundleID
        if let b = s.bundleID, !s.title.isEmpty {
            lastTracks[b] = s.artist.isEmpty ? s.title : "\(s.title) — \(s.artist)"
        }
        clients = s.clients
        updateSources(clients: s.clients)

        guard !s.title.isEmpty else {
            // Entre deux morceaux, Deezer annonce brièvement « plus rien » : on attend avant d'effacer.
            if hasTrack, pendingClear == nil {
                let work = DispatchWorkItem { [weak self] in
                    self?.pendingClear = nil
                    self?.clear()
                }
                pendingClear = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
            }
            return
        }
        pendingClear?.cancel()
        pendingClear = nil
        if s.playing { lastPlayedAt = Date() }
        let now = Date()
        // Position échantillonnée à `timestamp` : on la projette jusqu'à maintenant.
        let drift = s.playing && s.timestamp > 0 ? max(now.timeIntervalSince1970 - s.timestamp, 0) * max(s.rate, 1) : 0
        positionAnchor = s.elapsed + drift
        anchorDate = now

        let name = s.bundleID.map(displayName(for:))
        if appName != name { appName = name }
        if title != s.title { title = s.title }
        if artist != s.artist { artist = s.artist }
        if album != s.album { album = s.album }
        if duration != s.duration { duration = s.duration }
        if isPlaying != s.playing { isPlaying = s.playing }
        objectWillChange.send()

        if let data = s.artwork {
            if data.isEmpty {
                artwork = nil
                accent = .white
            } else if let img = NSImage(data: data) {
                artwork = img
                accent = img.vibrantAverageColor.map { Color(nsColor: $0) } ?? .white
            }
        }
    }

    private func updateSources(clients: [String]) {
        let candidates = clients + Self.musicApps + [currentBundle].compactMap { $0 }
        for id in candidates where !sourceOrder.contains(id) { sourceOrder.append(id) }
        let list = sourceOrder
            .filter { candidates.contains($0) && !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
            .map { MediaSource(bundleID: $0, name: displayName(for: $0), lastTrack: lastTracks[$0],
                               isCurrent: $0 == currentBundle) }
        if list != sources { sources = list }
    }

    private func displayName(for bundleID: String) -> String {
        if let cached = appNames[bundleID] { return cached }
        var name = bundleID
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            name = FileManager.default.displayName(atPath: url.path)
            if name.hasSuffix(".app") { name.removeLast(4) }
        }
        appNames[bundleID] = name
        return name
    }

    private func send(_ command: String) {
        guard let s = source, isRunning(s) else { return }
        AppleScript.run("tell application \"\(s.appName)\" to \(command)")
    }

    // MARK: - Notifications

    @objc private func musicInfo(_ n: Notification) { handle(n.userInfo, from: .music) }
    @objc private func spotifyInfo(_ n: Notification) { handle(n.userInfo, from: .spotify) }

    @objc private func appTerminated(_ n: Notification) {
        let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        if let id = app?.bundleIdentifier, id == source?.rawValue { clear() }
    }

    private func handle(_ info: [AnyHashable: Any]?, from src: Source) {
        guard let info else { return }
        let state = info["Player State"] as? String ?? ""
        let name = info["Name"] as? String ?? ""
        let artist = info["Artist"] as? String ?? ""
        let album = info["Album"] as? String ?? ""
        let ms = (info["Total Time"] ?? info["Duration"]) as? Double ?? 0
        let pos = info["Playback Position"] as? Double

        DispatchQueue.main.async { [self] in
            if state == "Stopped" || name.isEmpty {
                if source == src { clear() }
                return
            }
            // Une pause venant d'un autre lecteur ne doit pas écraser celui qui joue.
            if state != "Playing", let cur = source, cur != src, isPlaying { return }

            apply(title: name, artist: artist, album: album, playing: state == "Playing",
                  duration: ms / 1000, position: pos, source: src)
            if pos == nil { fetchPosition(src) }
        }
    }

    fileprivate func apply(title: String, artist: String, album: String, playing: Bool,
                       duration: Double, position: Double?, source src: Source, loadArtwork: Bool = true) {
        let now = Date()
        let trackChanged = title != self.title || album != self.album || src != source
        positionAnchor = position ?? (trackChanged ? 0 : self.position(at: now))
        anchorDate = now

        source = src
        appName = src.displayName
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        isPlaying = playing
        if playing { lastPlayedAt = Date() }

        let key = "\(src.rawValue)|\(title)|\(album)"
        if key != artworkKey {
            artworkKey = key
            if loadArtwork { fetchArtwork(src, key: key) }
        }
    }

    private func clear() {
        source = nil; appName = nil; title = ""; artist = ""; album = ""
        isPlaying = false; duration = 0; artwork = nil; accent = .white
        artworkKey = ""
    }

    // MARK: - AppleScript

    private func isRunning(_ s: Source) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: s.rawValue).isEmpty
    }

    private func fetchInitialState(_ s: Source) {
        let script = """
        tell application "\(s.appName)"
            if player state is stopped then return ""
            set t to current track
            return (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & ¬
                (player state as string) & linefeed & ((duration of t) as string) & linefeed & ((player position) as string)
        end tell
        """
        AppleScript.run(script) { [weak self] result in
            guard let self, self.source == nil || self.source == s,
                  let parts = result?.stringValue?.components(separatedBy: "\n"), parts.count >= 6 else { return }
            var dur = Self.number(parts[4])
            if s == .spotify { dur /= 1000 }   // Spotify renvoie des millisecondes
            self.apply(title: parts[0], artist: parts[1], album: parts[2], playing: parts[3] == "playing",
                       duration: dur, position: Self.number(parts[5]), source: s)
        }
    }

    private func fetchPosition(_ s: Source) {
        guard isRunning(s) else { return }
        AppleScript.run("tell application \"\(s.appName)\" to return (player position as string)") { [weak self] result in
            guard let self, self.source == s, let str = result?.stringValue else { return }
            self.positionAnchor = Self.number(str)
            self.anchorDate = Date()
            self.objectWillChange.send()
        }
    }

    private func fetchArtwork(_ s: Source, key: String) {
        artwork = nil
        accent = .white
        // Un « tell » vers une app absente ouvre un dialogue AppKit hors du thread principal : plantage.
        guard isRunning(s) else { return }
        let script = s == .spotify
            ? "tell application \"Spotify\" to return artwork url of current track"
            : "tell application \"Music\" to return raw data of artwork 1 of current track"

        AppleScript.run(script) { [weak self] result in
            guard let self, let result else { return }
            if s == .spotify, let str = result.stringValue, let url = URL(string: str) {
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    guard let data, let img = NSImage(data: data) else { return }
                    DispatchQueue.main.async { self.setArtwork(img, key: key) }
                }.resume()
            } else if let img = NSImage(data: result.data) {
                self.setArtwork(img, key: key)
            }
        }
    }

    private func setArtwork(_ image: NSImage, key: String) {
        guard key == artworkKey else { return }
        artwork = image
        if let c = image.vibrantAverageColor { accent = Color(nsColor: c) }
    }

    private static func number(_ s: String) -> Double {
        Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) ?? 0
    }
}

enum AppleScript {
    private static let queue = DispatchQueue(label: "dynamicisland.applescript")

    static func run(_ source: String, completion: ((NSAppleEventDescriptor?) -> Void)? = nil) {
        queue.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            DispatchQueue.main.async { completion?(error == nil ? result : nil) }
        }
    }
}

extension NSImage {
    /// Couleur moyenne de l'image, éclaircie pour rester lisible sur fond noir.
    var vibrantAverageColor: NSColor? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        let ok = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                      bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard ok else { return nil }
        let c = NSColor(deviceRed: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255,
                        blue: CGFloat(px[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: min(s * 1.2, 0.9), brightness: max(b, 0.8), alpha: 1)
    }
}

extension NowPlayingMonitor {
    /// Données factices pour les rendus de test (`--snapshot`).
    func loadDemoTrack() {
        apply(title: "Blinding Lights", artist: "The Weeknd", album: "After Hours", playing: true,
              duration: 200, position: 74, source: .spotify, loadArtwork: false)
        appName = "Deezer"
        sources = [MediaSource(bundleID: "com.deezer.deezer-desktop", name: "Deezer", lastTrack: nil, isCurrent: true),
                   MediaSource(bundleID: "com.apple.Safari", name: "Safari", lastTrack: "YouTube", isCurrent: false),
                   MediaSource(bundleID: "com.spotify.client", name: "Spotify", lastTrack: nil, isCurrent: false)]
        accent = Color(red: 1, green: 0.45, blue: 0.35)
    }
}

struct MediaSource: Identifiable, Equatable {
    let bundleID: String
    let name: String
    let lastTrack: String?
    let isCurrent: Bool
    var id: String { bundleID }
}

enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String) -> NSImage {
        if let cached = cache[bundleID] { return cached }
        let image = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        cache[bundleID] = image
        return image
    }
}
