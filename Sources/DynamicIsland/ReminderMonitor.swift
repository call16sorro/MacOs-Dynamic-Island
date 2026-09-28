import AppKit
import EventKit
import SwiftUI

/// Rappels (app Rappels de macOS) : liste des rappels à faire, alerte à l'échéance,
/// cocher et créer depuis l'île.
final class ReminderMonitor: ObservableObject {
    enum Access { case unknown, granted, denied }

    struct Item: Identifiable, Equatable {
        let id: String
        let title: String
        let due: Date?
        let hasTime: Bool
        let color: Color
        let list: String

        func isOverdue(at now: Date) -> Bool {
            guard let due else { return false }
            return hasTime ? due < now : due < Calendar.current.startOfDay(for: now)
        }

        func dueText(at now: Date) -> String? {
            guard let due else { return nil }
            let cal = Calendar.current
            let time = hasTime ? " " + due.formatted(date: .omitted, time: .shortened) : ""
            let day: String
            if cal.isDateInToday(due) { day = "Aujourd'hui" }
            else if cal.isDateInYesterday(due) { day = "Hier" }
            else if cal.isDateInTomorrow(due) { day = "Demain" }
            else { day = due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) }
            return day + time
        }
    }

    @Published private(set) var access: Access = .unknown
    @Published private(set) var items: [Item] = []
    var onDue: ((Item) -> Void)?

    private let store = EKEventStore()
    private var reminders: [String: EKReminder] = [:]
    private var alerted = Set<String>()
    private var loadedOnce = false
    private var timer: Timer?
    private var nextDueWork: DispatchWorkItem?

    func start() {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: access = .granted
        case .notDetermined: requestAccess()
        default: access = .denied
        }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.reload()
        }
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in self?.reload() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        reload()
    }

    func requestAccess() {
        store.requestFullAccessToReminders { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.access = granted ? .granted : .denied
                self?.reload()
            }
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            NSWorkspace.shared.open(url)
        }
    }

    func openRemindersApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func complete(_ item: Item) {
        items.removeAll { $0.id == item.id }
        guard let reminder = reminders[item.id] else { return }
        reminder.isCompleted = true
        try? store.save(reminder, commit: true)
    }

    func add(title: String) {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard access == .granted, !text.isEmpty, let list = store.defaultCalendarForNewReminders() else { return }
        let reminder = EKReminder(eventStore: store)
        reminder.title = text
        reminder.calendar = list
        try? store.save(reminder, commit: true)
        reload()
    }

    func setDemo(_ items: [Item]) {
        access = .granted
        self.items = items
    }

    private func reload() {
        guard access == .granted else { return }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        store.fetchReminders(matching: predicate) { [weak self] result in
            let fetched = result ?? []
            DispatchQueue.main.async { self?.apply(fetched) }
        }
    }

    private func apply(_ fetched: [EKReminder]) {
        reminders = Dictionary(fetched.map { ($0.calendarItemIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        let now = Date()
        let list = fetched.map { r -> Item in
            let comps = r.dueDateComponents
            return Item(id: r.calendarItemIdentifier, title: r.title ?? "Sans titre",
                        due: comps.flatMap { Calendar.current.date(from: $0) },
                        hasTime: comps?.hour != nil,
                        color: Color(cgColor: r.calendar.cgColor), list: r.calendar.title)
        }
        // Rappels datés d'abord (du plus ancien au plus lointain), puis les autres.
        .sorted { a, b in
            switch (a.due, b.due) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.title.localizedCompare(b.title) == .orderedAscending
            }
        }
        items = Array(list.prefix(40))

        // Alerte à l'échéance ; au premier chargement, les retards ne déclenchent rien.
        for item in list where item.hasTime {
            guard let due = item.due, due <= now, !alerted.contains(item.id) else { continue }
            alerted.insert(item.id)
            if loadedOnce, now.timeIntervalSince(due) < 120 { onDue?(item) }
        }
        loadedOnce = true

        // Rechargement pile à la prochaine échéance, pour une alerte à l'heure.
        nextDueWork?.cancel()
        if let next = list.compactMap({ $0.hasTime ? $0.due : nil }).filter({ $0 > now }).min() {
            let work = DispatchWorkItem { [weak self] in self?.reload() }
            nextDueWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + next.timeIntervalSince(now) + 0.5, execute: work)
        }
    }
}
