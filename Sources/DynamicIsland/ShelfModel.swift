import AppKit
import UniformTypeIdentifiers

/// Étagère : fichiers glissés sur l'île, gardés sous la main (références, pas de copie).
final class ShelfModel: ObservableObject {
    @Published private(set) var items: [URL] = []
    private let defaultsKey = "shelf.paths"
    private let persists: Bool

    init(persists: Bool = true) {
        self.persists = persists
        guard persists else { return }
        let paths = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        items = paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Ajoute les fichiers déposés ; `completion` reçoit le nombre de nouveaux éléments.
    func add(providers: [NSItemProvider], completion: @escaping (Int) -> Void) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            completion(self?.add(urls) ?? 0)
        }
    }

    @discardableResult
    func add(_ urls: [URL]) -> Int {
        let new = urls.filter { !items.contains($0) }
        items.append(contentsOf: new)
        save()
        return new.count
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    func open(_ url: URL) { NSWorkspace.shared.open(url) }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    func airDrop() {
        guard !items.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: items)
    }

    private func save() {
        guard persists else { return }
        UserDefaults.standard.set(items.map(\.path), forKey: defaultsKey)
    }
}
