import AppKit

/// Minuteur (compte à rebours) ou chronomètre, affiché en direct dans l'île.
final class TimerManager: ObservableObject {
    enum Kind: Equatable { case countdown, stopwatch }

    @Published private(set) var kind: Kind?
    @Published private(set) var isPaused = false
    private(set) var total: TimeInterval = 0

    /// Date de fin (minuteur) ou de départ (chronomètre) tant que ça tourne.
    private var anchor: Date?
    /// Temps restant (minuteur) ou écoulé (chronomètre) au moment de la pause.
    private var stored: TimeInterval = 0
    private var finishWork: DispatchWorkItem?

    var onFinish: (() -> Void)?
    var isActive: Bool { kind != nil }

    /// Restant pour le minuteur, écoulé pour le chronomètre.
    func value(at date: Date) -> TimeInterval {
        switch kind {
        case .countdown: return anchor.map { max($0.timeIntervalSince(date), 0) } ?? stored
        case .stopwatch: return anchor.map { stored + date.timeIntervalSince($0) } ?? stored
        case nil: return 0
        }
    }

    func text(at date: Date) -> String {
        let v = value(at: date)
        return Self.format(kind == .countdown ? v.rounded(.up) : v.rounded(.down))
    }

    func startCountdown(_ seconds: TimeInterval) {
        stop()
        kind = .countdown
        total = seconds
        stored = seconds
        resume()
    }

    func startStopwatch() {
        stop()
        kind = .stopwatch
        stored = 0
        resume()
    }

    func togglePause() { isPaused ? resume() : pause() }

    func stop() {
        finishWork?.cancel()
        kind = nil
        anchor = nil
        isPaused = false
        stored = 0
    }

    private func pause() {
        guard kind != nil, !isPaused else { return }
        stored = value(at: Date())
        anchor = nil
        finishWork?.cancel()
        isPaused = true
    }

    private func resume() {
        guard let kind else { return }
        isPaused = false
        let now = Date()
        switch kind {
        case .stopwatch:
            anchor = now
        case .countdown:
            anchor = now.addingTimeInterval(stored)
            let work = DispatchWorkItem { [weak self] in
                self?.stop()
                self?.onFinish?()
            }
            finishWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + stored, execute: work)
        }
    }

    static func format(_ t: TimeInterval) -> String {
        let s = Int(t)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}
