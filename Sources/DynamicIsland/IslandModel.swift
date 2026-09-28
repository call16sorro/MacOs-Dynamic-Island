import AppKit
import Combine
import SwiftUI

/// Notification temporaire qui prend la place du contenu compact.
enum LiveActivity: Equatable {
    case charging(level: Int, plugged: Bool)
    case volume(level: Float, muted: Bool)
    case brightness(level: Float)
    case bluetooth(name: String, symbol: String, connected: Bool, battery: Int?)
    case timerDone
    case event(title: String, minutes: Int, color: Color)
    case shelf(count: Int)
    case notification(NotificationMonitor.Item)
    case reminder(title: String, color: Color)

    var duration: TimeInterval {
        switch self {
        case .volume, .brightness: return 1.6
        case .shelf: return 2
        case .timerDone, .event: return 6
        case .notification: return 5
        case .reminder: return 8
        default: return 3.5
        }
    }

    /// Hauteur ajoutée sous l'encoche (bannière de notification).
    var extraHeight: CGFloat {
        if case .notification = self { return 66 }
        return 0
    }

    /// Largeur ajoutée de chaque côté de l'encoche.
    var wing: CGFloat {
        switch self {
        case .volume, .brightness: return 96
        case .bluetooth: return 116
        case .event: return 130
        case .notification: return 150
        case .reminder: return 130
        default: return 104
        }
    }

    /// Même valeur => mise à jour sur place (jauge de volume) sans rejouer la transition.
    var kind: String {
        switch self {
        case .charging: return "charging"
        case .volume: return "volume"
        case .brightness: return "brightness"
        case .bluetooth: return "bluetooth"
        case .timerDone: return "timer"
        case .event: return "event"
        case .shelf: return "shelf"
        case .notification(let item): return "notification-\(item.id)"
        case .reminder: return "reminder"
        }
    }
}

extension LiveActivity {
    var isNotification: Bool {
        if case .notification = self { return true }
        return false
    }
}

/// Ce qui s'affiche de part et d'autre de l'encoche en mode compact.
struct CompactLayout: Equatable {
    var music = false
    var timer = false
    var camera = false
    var microphone = false

    var isEmpty: Bool { !music && !timer && !camera && !microphone }
    var dotCount: Int { (camera ? 1 : 0) + (microphone ? 1 : 0) }

    func wing(notch n: CGSize) -> CGFloat {
        let side = n.height - 10
        let left: CGFloat = music || timer ? side : 0
        let main: CGFloat = timer ? 58 : (music ? side : 0)
        let dots = dotCount > 0 ? CGFloat(dotCount) * 7 + CGFloat(dotCount - 1) * 4 : 0
        let right = main + (main > 0 && dots > 0 ? 8 : 0) + dots
        return max(left, right) + 24
    }
}

enum IslandMode: Equatable {
    case idle                     // caché dans l'encoche
    case compact(CompactLayout)   // musique, minuteur, pastilles caméra/micro
    case activity(LiveActivity)   // notification temporaire
    case expanded                 // déplié au survol
}

enum ExpandedTab { case home, reminders, notifications, shelf }

final class IslandModel: ObservableObject {
    @Published private(set) var mode: IslandMode = .idle
    /// Vrai quand l'île rétrécit : on anime alors sans rebond (sinon elle passe sous l'encoche).
    @Published private(set) var isShrinking = false
    @Published var notchSize: CGSize
    @Published var isHovering = false {
        didSet {
            if !isHovering { tab = .home }
            // Survoler l'alerte d'un rappel ouvre directement l'onglet Rappels.
            if isHovering, case .reminder = activity { tab = .reminders }
            recompute()
        }
    }
    @Published var tab: ExpandedTab = .home
    /// Saisie en cours (nouveau rappel) : l'île ne se replie pas.
    @Published var isEditingText = false
    @Published private(set) var activity: LiveActivity? { didSet { recompute() } }

    let player = NowPlayingMonitor()
    let battery = BatteryMonitor()
    let timer = TimerManager()
    let privacy = PrivacyMonitor()
    let calendar = CalendarMonitor()
    let notifications = NotificationMonitor()
    let reminders = ReminderMonitor()
    let shelf: ShelfModel
    private let volume = VolumeMonitor()
    private let brightness = BrightnessMonitor()
    private let bluetooth = BluetoothMonitor()

    private var cancellables = Set<AnyCancellable>()
    private var activityWork: DispatchWorkItem?
    private var refreshTimer: Timer?
    /// Durée pendant laquelle un lecteur en pause reste affiché.
    private static let pausedLinger: TimeInterval = 30 * 60

    /// `live: false` pour les rendus de test : aucun capteur ni demande de permission.
    init(notchSize: CGSize, live: Bool = true) {
        self.notchSize = notchSize
        shelf = ShelfModel(persists: live)

        // Les @Published émettent avant le changement : on recalcule au tour suivant.
        Publishers.MergeMany(
            player.$isPlaying.map { _ in () }.eraseToAnyPublisher(),
            player.$title.map { _ in () }.eraseToAnyPublisher(),
            timer.$kind.map { _ in () }.eraseToAnyPublisher(),
            privacy.$camera.map { _ in () }.eraseToAnyPublisher(),
            privacy.$microphone.map { _ in () }.eraseToAnyPublisher())
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.recompute() }
            .store(in: &cancellables)

        battery.onPlugChange = { [weak self] plugged in
            guard let self else { return }
            self.showActivity(.charging(level: self.battery.level, plugged: plugged))
        }
        volume.onChange = { [weak self] level, muted in self?.showActivity(.volume(level: level, muted: muted)) }
        brightness.onChange = { [weak self] level in self?.showActivity(.brightness(level: level)) }
        bluetooth.onEvent = { [weak self] e in
            self?.showActivity(.bluetooth(name: e.name, symbol: e.symbol, connected: e.connected, battery: e.battery))
        }
        timer.onFinish = { [weak self] in
            NSSound(named: "Glass")?.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { NSSound(named: "Glass")?.play() }
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            self?.showActivity(.timerDone)
        }
        reminders.onDue = { [weak self] item in
            NSSound(named: "Tink")?.play()
            self?.showActivity(.reminder(title: item.title, color: item.color))
        }
        notifications.onNew = { [weak self] item in self?.showActivity(.notification(item)) }
        calendar.onSoon = { [weak self] event in
            let minutes = max(1, Int(event.start.timeIntervalSinceNow / 60 + 0.5))
            self?.showActivity(.event(title: event.title, minutes: minutes, color: event.color))
        }

        if live {
            player.start()
            volume.start()
            brightness.start()
            bluetooth.start()
            privacy.start()
            calendar.start()
            notifications.start()
            reminders.start()
        }
        // Fait disparaître la musique après une longue pause.
        let refresh = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.recompute() }
        RunLoop.main.add(refresh, forMode: .common)
        refreshTimer = refresh
    }

    func showActivity(_ activity: LiveActivity) {
        activityWork?.cancel()
        self.activity = activity
        scheduleDismiss(after: activity.duration)
    }

    private func scheduleDismiss(after delay: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Une notification survolée reste affichée.
            if self.isHovering, self.activity?.isNotification == true {
                self.scheduleDismiss(after: 1)
            } else {
                self.activity = nil
            }
        }
        activityWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Clic sur la bannière : ouvre l'app qui a envoyé la notification.
    func openNotification(_ item: NotificationMonitor.Item) {
        notifications.openApp(of: item)
        activityWork?.cancel()
        activity = nil
    }

    func dropFiles(_ providers: [NSItemProvider]) {
        shelf.add(providers: providers) { [weak self] added in
            guard let self, added > 0 else { return }
            self.tab = .shelf
            if !self.isHovering { self.showActivity(.shelf(count: added)) }
        }
    }

    private func recompute() {
        let recentlyPlayed = player.lastPlayedAt.map { Date().timeIntervalSince($0) < Self.pausedLinger } ?? false
        let layout = CompactLayout(music: player.hasTrack && (player.isPlaying || recentlyPlayed),
                                   timer: timer.isActive,
                                   camera: privacy.camera,
                                   microphone: privacy.microphone)
        let new: IslandMode
        // Survoler une notification la garde (pour cliquer dessus) au lieu de déplier l'île.
        if isHovering, let activity, activity.isNotification { new = .activity(activity) }
        else if isHovering { new = .expanded }
        else if let activity { new = .activity(activity) }
        else if !layout.isEmpty { new = .compact(layout) }
        else { new = .idle }
        guard new != mode else { return }
        let old = size(for: mode), next = size(for: new)
        isShrinking = next.width * next.height < old.width * old.height
        mode = new
    }

    // MARK: - Géométrie (tailles totales, arrondis supérieurs inclus)

    var size: CGSize { size(for: mode) }

    func size(for mode: IslandMode) -> CGSize {
        let n = notchSize
        switch mode {
        case .idle:                  return n
        case .compact(let layout):   return CGSize(width: n.width + 2 * layout.wing(notch: n), height: n.height)
        case .activity(let a):       return CGSize(width: n.width + 2 * a.wing, height: n.height + a.extraHeight)
        case .expanded:              return CGSize(width: max(n.width + 440, 640), height: n.height + 160)
        }
    }

    var topRadius: CGFloat { mode == .expanded ? 14 : 6 }
    var bottomRadius: CGFloat {
        switch mode {
        case .expanded: return 34
        case .activity(let a) where a.extraHeight > 0: return 26
        case .idle: return 10
        default: return 14
        }
    }
}
