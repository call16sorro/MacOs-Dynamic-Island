import AppKit
import SQLite3

/// Lit les notifications reçues dans la base du Centre de notifications (lecture seule).
/// macOS la protège : l'app doit avoir l'« Accès complet au disque ».
final class NotificationMonitor: ObservableObject {
    struct Item: Identifiable, Equatable {
        let id: Int64
        let bundleID: String
        let appName: String
        let title: String
        let subtitle: String
        let body: String
        let date: Date
    }

    enum Access: Equatable { case unknown, granted, denied, unsupported(String) }

    @Published private(set) var access: Access = .unknown
    @Published private(set) var recent: [Item] = []
    @Published var isEnabled = UserDefaults.standard.object(forKey: "notifications.enabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "notifications.enabled") }
    }
    var onNew: ((Item) -> Void)?

    private var db: OpaquePointer?
    private var lastID: Int64 = -1
    private var dateColumn = "delivered_date"
    private var timer: Timer?
    private var appNames: [String: String] = [:]

    static var databaseURL: URL? {
        let fm = FileManager.default
        let modern = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db")
        if fm.fileExists(atPath: modern.path) { return modern }
        // Emplacement d'avant macOS 15.
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard confstr(_CS_DARWIN_USER_DIR, &buf, buf.count) > 0 else { return nil }
        let legacy = URL(fileURLWithPath: String(cString: buf))
            .appendingPathComponent("com.apple.notificationcenter/db2/db")
        return fm.fileExists(atPath: legacy.path) ? legacy : nil
    }

    func start() {
        poll()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func openApp(of item: Item) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func clearRecent() { recent.removeAll() }

    func setDemo(_ items: [Item]) {
        access = .granted
        recent = items
    }

    // MARK: - Base de données

    private var retryCountdown = 0

    private func poll() {
        if db == nil {
            // Sans accès, on réessaie toutes les 5 s (l'utilisateur peut l'accorder entre-temps).
            guard retryCountdown <= 0 else { retryCountdown -= 1; return }
            retryCountdown = 5
            guard open() else { return }
        }
        fetchNew()
    }

    private func open() -> Bool {
        guard let url = Self.databaseURL else {
            // Le dossier existe mais est illisible : c'est la protection de macOS.
            access = .denied
            return false
        }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let handle, tableExists("record", in: handle) else {
            sqlite3_close(handle)
            access = FileManager.default.isReadableFile(atPath: url.path) ? .unsupported("structure inconnue") : .denied
            return false
        }
        db = handle
        let columns = self.columns(of: "record")
        dateColumn = columns.contains("delivered_date") ? "delivered_date"
            : columns.contains("request_date") ? "request_date" : "0"
        access = .granted

        // Au démarrage : on charge l'historique récent sans l'annoncer.
        lastID = scalar("SELECT IFNULL(MAX(rec_id), 0) FROM record")
        recent = query(where: "r.rec_id > \(max(lastID - 40, 0))").reversed().prefix(20).map { $0 }
        return true
    }

    private func fetchNew() {
        let items = query(where: "r.rec_id > \(lastID)")
        guard !items.isEmpty else { return }
        lastID = max(lastID, items.map(\.id).max() ?? lastID)
        recent = Array((items.reversed() + recent).prefix(20))
        if isEnabled, let latest = items.last { onNew?(latest) }
    }

    private func query(where condition: String) -> [Item] {
        guard let db else { return [] }
        let sql = """
            SELECT r.rec_id, IFNULL(a.identifier, ''), r.data, r.\(dateColumn)
            FROM record r LEFT JOIN app a ON a.app_id = r.app_id
            WHERE \(condition) ORDER BY r.rec_id
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_finalize(stmt)
            // Base remplacée ou verrouillée : on rouvrira au prochain passage.
            sqlite3_close(db)
            self.db = nil
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var items: [Item] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let appID = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            var plist: [String: Any] = [:]
            if let bytes = sqlite3_column_blob(stmt, 2) {
                let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 2)))
                plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] ?? [:]
            }
            let req = plist["req"] as? [String: Any] ?? [:]
            let bundle = (plist["app"] as? String) ?? appID
            let title = req["titl"] as? String ?? ""
            let body = req["body"] as? String ?? ""
            guard !bundle.isEmpty, bundle != Bundle.main.bundleIdentifier, !(title.isEmpty && body.isEmpty) else { continue }
            let stamp = sqlite3_column_double(stmt, 3)
            items.append(Item(id: id, bundleID: bundle, appName: appName(for: bundle),
                              title: title, subtitle: req["subt"] as? String ?? "", body: body,
                              date: stamp > 0 ? Date(timeIntervalSinceReferenceDate: stamp) : Date()))
        }
        return items
    }

    private func scalar(_ sql: String) -> Int64 {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return sqlite3_column_int64(stmt, 0)
    }

    private func tableExists(_ name: String, in handle: OpaquePointer) -> Bool {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = '\(name)'"
        return sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK && sqlite3_step(stmt) == SQLITE_ROW
    }

    func columns(of table: String) -> [String] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &stmt, nil) == SQLITE_OK else { return [] }
        var names: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 1) { names.append(String(cString: c)) }
        }
        return names
    }

    private func appName(for bundleID: String) -> String {
        if let cached = appNames[bundleID] { return cached }
        var name = bundleID.components(separatedBy: ".").last ?? bundleID
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            name = FileManager.default.displayName(atPath: url.path)
            if name.hasSuffix(".app") { name.removeLast(4) }
        }
        appNames[bundleID] = name
        return name
    }
}
