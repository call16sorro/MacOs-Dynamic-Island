import Foundation

/// Lance l'adaptateur MediaRemote (Helper/) dans /usr/bin/perl et relaie l'état
/// « À l'écoute » de macOS : Deezer, Spotify, Musique, navigateurs…
final class MediaRemoteBridge {
    struct State {
        var title = ""
        var artist = ""
        var album = ""
        var duration: Double = 0
        var elapsed: Double = 0
        var timestamp: Double = 0
        var rate: Double = 0
        var playing = false
        var bundleID: String?
        var pid: Int32 = 0
        /// nil : pochette inchangée ; Data vide : aucune pochette.
        var artwork: Data?
        /// Apps ayant un lecteur enregistré auprès du système.
        var clients: [String] = []
    }

    enum Command: Int {
        case play = 0, pause = 1, togglePlayPause = 2, nextTrack = 4, previousTrack = 5
    }

    var onState: ((State) -> Void)?
    /// Appelé si l'adaptateur ne peut pas fonctionner (retour aux notifications Musique/Spotify).
    var onFailure: (() -> Void)?

    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var restarts = 0
    private var stopped = false

    static var isAvailable: Bool { resources != nil }

    private static var resources: (script: URL, dylib: URL)? {
        guard let dir = Bundle.main.resourceURL else { return nil }
        let script = dir.appendingPathComponent("mediaremote.pl")
        let dylib = dir.appendingPathComponent("MediaRemoteAdapter.dylib")
        let fm = FileManager.default
        guard fm.fileExists(atPath: script.path), fm.fileExists(atPath: dylib.path) else { return nil }
        return (script, dylib)
    }

    func start() {
        guard let res = Self.resources else { onFailure?(); return }
        stopped = false

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [res.script.path, res.dylib.path]
        let stdout = Pipe(), stdin = Pipe()
        p.standardOutput = stdout
        p.standardInput = stdin
        p.standardError = FileHandle.nullDevice

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { self?.receive(data) }
        }
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async { self?.terminated(status: proc.terminationStatus) }
        }

        do {
            try p.run()
            process = p
            input = stdin.fileHandleForWriting
        } catch {
            onFailure?()
        }
    }

    func stop() {
        stopped = true
        process?.terminate()
    }

    func send(_ command: Command) { write("cmd \(command.rawValue)") }
    func send(_ command: Command, to bundleID: String) { write("app \(command.rawValue) \(bundleID)") }
    func seek(to seconds: Double) { write("seek \(seconds)") }

    private func write(_ line: String) {
        guard let input, process?.isRunning == true else { return }
        try? input.write(contentsOf: Data((line + "\n").utf8))
    }

    private func terminated(status: Int32) {
        process = nil
        input = nil
        buffer.removeAll()
        guard !stopped else { return }
        // Plantage ponctuel : on relance quelques fois avant d'abandonner.
        if status != 1, restarts < 3 {
            restarts += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.start() }
        } else {
            onFailure?()
        }
    }

    private func receive(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let nl = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            parse(Data(line))
        }
    }

    private func parse(_ line: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        if json["error"] != nil { return }
        restarts = 0

        func num(_ key: String) -> Double { (json[key] as? NSNumber)?.doubleValue ?? 0 }
        var s = State()
        s.title = json["title"] as? String ?? ""
        s.artist = json["artist"] as? String ?? ""
        s.album = json["album"] as? String ?? ""
        s.duration = num("duration")
        s.elapsed = num("elapsed")
        s.timestamp = num("timestamp")
        s.rate = num("rate")
        s.playing = (json["playing"] as? NSNumber)?.boolValue ?? false
        s.bundleID = json["bundle"] as? String
        s.pid = Int32(num("pid"))
        s.clients = json["clients"] as? [String] ?? []
        if let art = json["artwork"] as? String {
            s.artwork = art.isEmpty ? Data() : Data(base64Encoded: art) ?? Data()
        }
        onState?(s)
    }
}
