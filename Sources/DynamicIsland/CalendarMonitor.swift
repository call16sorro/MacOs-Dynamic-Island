import AppKit
import EventKit
import SwiftUI

/// Prochain événement du calendrier, et rappel 5 minutes avant.
final class CalendarMonitor: ObservableObject {
    enum Access { case unknown, granted, denied }

    struct Event: Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let color: Color

        func subtitle(at now: Date) -> String {
            let time = Date.FormatStyle().hour().minute()
            if start <= now { return "En cours · jusqu'à \(end.formatted(time))" }
            let minutes = Int(start.timeIntervalSince(now) / 60) + 1
            if minutes <= 60 { return "Dans \(minutes) min" }
            let day = Calendar.current.isDateInToday(start) ? "" : "Demain, "
            return "\(day)\(start.formatted(time)) – \(end.formatted(time))"
        }
    }

    @Published private(set) var access: Access = .unknown
    @Published private(set) var next: Event?
    var onSoon: ((Event) -> Void)?

    private let store = EKEventStore()
    private var reminded = Set<String>()
    private var timer: Timer?

    func start() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: access = .granted
        case .notDetermined: requestAccess()
        default: access = .denied
        }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.reload()
        }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.reload() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        reload()
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.access = granted ? .granted : .denied
                self?.reload()
            }
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    func setDemo(_ event: Event) {
        access = .granted
        next = event
    }

    private func reload() {
        guard access == .granted else { return }
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-12 * 3600),
                                                 end: now.addingTimeInterval(24 * 3600), calendars: nil)
        let event = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now }
            .min { $0.startDate < $1.startDate }

        next = event.map {
            Event(id: "\($0.eventIdentifier ?? "")|\($0.startDate.timeIntervalSince1970)",
                  title: $0.title ?? "Sans titre", start: $0.startDate, end: $0.endDate,
                  color: Color(cgColor: $0.calendar.cgColor))
        }

        if let next, next.start > now, next.start.timeIntervalSince(now) <= 5 * 60, !reminded.contains(next.id) {
            reminded.insert(next.id)
            onSoon?(next)
        }
    }
}
