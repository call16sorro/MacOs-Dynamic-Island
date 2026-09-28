import AppKit
import SwiftUI

/// `DynamicIsland --snapshot <dossier>` : rend chaque état en PNG puis quitte.
enum Snapshot {
    @MainActor static func runIfRequested() {
        let args = CommandLine.arguments
        if args.contains("--nowplaying") { diagnoseNowPlaying() }
        if args.contains("--notifications") { diagnoseNotifications() }
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        let notch = CGSize(width: 185, height: 32)
        func make() -> IslandModel { IslandModel(notchSize: notch, live: false) }

        render(make(), "01-idle", dir)

        let playing = make()
        playing.player.loadDemoTrack()
        render(playing, "02-music", dir)

        let combo = make()
        combo.player.loadDemoTrack()
        combo.timer.startCountdown(754)
        combo.privacy.setDemo(camera: true, microphone: true)
        render(combo, "03-music-timer-privacy", dir)

        let privacy = make()
        privacy.privacy.setDemo(camera: false, microphone: true)
        render(privacy, "04-privacy", dir)

        let activities: [(String, LiveActivity)] = [
            ("05-charging", .charging(level: 76, plugged: true)),
            ("06-volume", .volume(level: 0.62, muted: false)),
            ("07-brightness", .brightness(level: 0.4)),
            ("08-airpods", .bluetooth(name: "AirPods Pro", symbol: "airpodspro", connected: true, battery: 84)),
            ("09-event", .event(title: "Point d'équipe", minutes: 5, color: .blue)),
            ("10-timer-done", .timerDone),
        ]
        for (name, activity) in activities {
            let m = make()
            m.showActivity(activity)
            render(m, name, dir)
        }

        let home = make()
        home.player.loadDemoTrack()
        home.timer.startCountdown(754)
        home.calendar.setDemo(.init(id: "demo", title: "Point d'équipe", start: Date().addingTimeInterval(25 * 60),
                                    end: Date().addingTimeInterval(55 * 60), color: .blue))
        home.isHovering = true
        render(home, "11-expanded-music", dir)

        let empty = make()
        empty.isHovering = true
        render(empty, "12-expanded-empty", dir)

        let note = NotificationMonitor.Item(id: 1, bundleID: "com.apple.MobileSMS", appName: "Messages", title: "Léa",
                                            subtitle: "", body: "On se retrouve à 19 h devant le cinéma ? J'ai pris les places.",
                                            date: Date())
        let banner = make()
        banner.showActivity(.notification(note))
        render(banner, "15-notification", dir)

        let notes = make()
        notes.notifications.setDemo([note,
            .init(id: 2, bundleID: "com.apple.mail", appName: "Mail", title: "Facture disponible", subtitle: "",
                  body: "Votre facture de septembre est prête.", date: Date().addingTimeInterval(-600))])
        notes.isHovering = true
        notes.tab = .notifications
        render(notes, "16-notifications-tab", dir)

        let remindersDemo = make()
        let cal = Calendar.current
        remindersDemo.reminders.setDemo([
            .init(id: "1", title: "Envoyer le devis à Marc", due: Date().addingTimeInterval(-3600), hasTime: true, color: .red, list: "Travail"),
            .init(id: "2", title: "Appeler le garagiste", due: Date().addingTimeInterval(2 * 3600), hasTime: true, color: .orange, list: "Perso"),
            .init(id: "3", title: "Acheter du pain", due: cal.date(byAdding: .day, value: 1, to: Date()), hasTime: false, color: .blue, list: "Courses"),
            .init(id: "4", title: "Réserver les vacances", due: nil, hasTime: false, color: .purple, list: "Perso")])
        remindersDemo.isHovering = true
        remindersDemo.tab = .reminders
        render(remindersDemo, "18-reminders-tab", dir)

        // La ScrollView de l'onglet n'est pas rendue hors écran : on rend les lignes seules.
        renderView(VStack(spacing: 2) {
            ForEach(remindersDemo.reminders.items) { ReminderRow(item: $0, complete: {}) }
        }
        .padding(16).frame(width: 400).background(Color.black).environment(\.colorScheme, .dark),
        "18b-reminder-rows", dir)

        let reminderAlert = make()
        reminderAlert.showActivity(.reminder(title: "Appeler le garagiste", color: .orange))
        render(reminderAlert, "19-reminder-alert", dir)

        let locked = make()
        locked.isHovering = true
        locked.tab = .notifications
        render(locked, "17-notifications-locked", dir)

        let shelf = make()
        shelf.shelf.add([URL(fileURLWithPath: "/System/Applications/Calculator.app"),
                         URL(fileURLWithPath: "/System/Library/Desktop Pictures"),
                         URL(fileURLWithPath: "/etc/hosts")])
        shelf.isHovering = true
        shelf.tab = .shelf
        render(shelf, "13-shelf", dir)

        let emptyShelf = make()
        emptyShelf.isHovering = true
        emptyShelf.tab = .shelf
        render(emptyShelf, "14-shelf-empty", dir)
        exit(0)
    }

    /// `DynamicIsland --nowplaying` : affiche ce que voit le moniteur de lecture, puis quitte.
    @MainActor private static func diagnoseNowPlaying() {
        let player = NowPlayingMonitor()
        player.start()
        RunLoop.main.run(until: Date().addingTimeInterval(3))
        print(player.hasTrack
              ? "\(player.appName ?? "?") — \(player.title) / \(player.artist) / \(player.album)\n"
                + "lecture: \(player.isPlaying), position: \(Int(player.position(at: Date())))/\(Int(player.duration)) s, "
                + "pochette: \(player.artwork.map { "\(Int($0.size.width))×\(Int($0.size.height))" } ?? "aucune")"
              : "Aucune lecture détectée")
        print("lecteurs : " + player.sources.map { $0.name + ($0.isCurrent ? " (actuel)" : "") }.joined(separator: ", "))
        exit(0)
    }

    /// `DynamicIsland --notifications` : état de l'accès à la base (sans afficher de contenu).
    @MainActor private static func diagnoseNotifications() {
        let monitor = NotificationMonitor()
        monitor.start()
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        print("base : \(NotificationMonitor.databaseURL?.path ?? "introuvable ou protégée")")
        print("accès : \(monitor.access)")
        if monitor.access == .granted {
            print("colonnes : \(monitor.columns(of: "record").joined(separator: ", "))")
            print("notifications récentes lues : \(monitor.recent.count)")
        }
        exit(0)
    }

    @MainActor private static func renderView<V: View>(_ view: V, _ name: String, _ dir: URL) {
        let r = ImageRenderer(content: view)
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: dir.appendingPathComponent("\(name).png"))
    }

    @MainActor private static func render(_ model: IslandModel, _ name: String, _ dir: URL) {
        // Laisse passer les mises à jour Combine reçues sur la boucle principale.
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let view = IslandView(model: model)
            .frame(width: 700, height: 230)
            .background(Color(white: 0.85))
            .transaction { $0.animation = nil }
        let r = ImageRenderer(content: view)
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
