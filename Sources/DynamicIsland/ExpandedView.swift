import SwiftUI

struct ExpandedView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var battery: BatteryMonitor
    @ObservedObject var privacy: PrivacyMonitor
    let notch: CGSize

    var body: some View {
        VStack(spacing: 0) {
            // Ligne de part et d'autre de l'encoche
            HStack {
                TabPicker(tab: $model.tab, shelf: model.shelf)
                Spacer(minLength: notch.width + 20)
                HStack(spacing: 8) {
                    if privacy.camera || privacy.microphone {
                        PrivacyDots(camera: privacy.camera, microphone: privacy.microphone)
                    }
                    if battery.hasBattery {
                        Text("\(battery.level) %").monospacedDigit()
                        BatteryIcon(level: battery.level, charging: battery.isCharging || battery.isPluggedIn)
                    }
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.75))
            .frame(height: notch.height)
            .padding(.horizontal, 18)

            Group {
                switch model.tab {
                case .home:
                    HStack(spacing: 18) {
                        MusicCard(player: model.player)
                            .frame(maxWidth: .infinity)
                        Rectangle().fill(.white.opacity(0.1)).frame(width: 1)
                        VStack(alignment: .leading, spacing: 0) {
                            CalendarWidget(calendar: model.calendar)
                            Spacer(minLength: 8)
                            TimerWidget(timer: model.timer)
                        }
                        .frame(width: 190)
                    }
                    .transition(.opacity)
                case .reminders:
                    RemindersTab(monitor: model.reminders, isEditing: $model.isEditingText)
                        .transition(.opacity)
                case .notifications:
                    NotificationsTab(monitor: model.notifications)
                        .transition(.opacity)
                case .shelf:
                    ShelfTab(shelf: model.shelf)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 18)
            .frame(maxHeight: .infinity)
        }
        .foregroundStyle(.white)
        .animation(.easeInOut(duration: 0.18), value: model.tab)
    }
}

// MARK: - En-tête

struct TabPicker: View {
    @Binding var tab: ExpandedTab
    @ObservedObject var shelf: ShelfModel

    var body: some View {
        HStack(spacing: 2) {
            item(.home, symbol: "house.fill")
            item(.reminders, symbol: "checklist")
            item(.notifications, symbol: "bell.fill")
            item(.shelf, symbol: "tray.full.fill", badge: shelf.items.count)
        }
        .padding(2)
        .background(Capsule().fill(.white.opacity(0.08)))
    }

    private func item(_ value: ExpandedTab, symbol: String, badge: Int = 0) -> some View {
        Button { tab = value } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                if badge > 0 { Text("\(badge)").monospacedDigit() }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(tab == value ? 1 : 0.5))
            .padding(.horizontal, 9)
            .frame(height: 20)
            .background(Capsule().fill(.white.opacity(tab == value ? 0.18 : 0)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Musique

struct MusicCard: View {
    @ObservedObject var player: NowPlayingMonitor

    var body: some View {
        if player.hasTrack { nowPlaying } else { placeholder }
    }

    private var nowPlaying: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Artwork(image: player.artwork, size: 56, corner: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.title).font(.system(size: 14, weight: .semibold))
                    Text(player.artist).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                    if player.sources.count > 1 {
                        SourcePicker(player: player).padding(.top, 2)
                    } else if let app = player.appName {
                        Text(app).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.35))
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 6)
                EqualizerBars(playing: player.isPlaying, color: player.accent, maxHeight: 18)
            }
            ProgressScrubber(player: player)
            HStack(spacing: 36) {
                ControlButton(symbol: "backward.fill", size: 18) { player.previousTrack() }
                ControlButton(symbol: player.isPlaying ? "pause.fill" : "play.fill", size: 26) { player.togglePlayPause() }
                ControlButton(symbol: "forward.fill", size: 18) { player.nextTrack() }
            }
        }
    }

    private var placeholder: some View {
        HStack {
            TimelineView(.everyMinute) { ctx in
                Text(ctx.date, format: .dateTime.hour().minute())
                    .font(.system(size: 46, weight: .semibold, design: .rounded))
            }
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "music.note").font(.system(size: 24)).foregroundStyle(.white.opacity(0.35))
                Text("Aucune lecture").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                if !player.sources.isEmpty { SourcePicker(player: player) }
            }
        }
    }
}

/// Bascule d'un lecteur à l'autre : l'actuel est mis en pause, l'autre démarre.
struct SourcePicker: View {
    @ObservedObject var player: NowPlayingMonitor

    var body: some View {
        HStack(spacing: 2) {
            ForEach(player.sources) { source in
                Button { player.switchTo(source.bundleID) } label: {
                    HStack(spacing: 4) {
                        Image(nsImage: AppIcons.icon(for: source.bundleID))
                            .resizable()
                            .frame(width: 15, height: 15)
                        if source.isCurrent {
                            Text(source.name).font(.system(size: 10, weight: .semibold))
                        }
                    }
                    .padding(.horizontal, source.isCurrent ? 6 : 3)
                    .frame(height: 20)
                    .background(Capsule().fill(.white.opacity(source.isCurrent ? 0.14 : 0)))
                    .opacity(source.isCurrent ? 1 : 0.6)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(source.isCurrent ? source.name
                      : "Passer à \(source.name)" + (source.lastTrack.map { " : \($0)" } ?? ""))
            }
        }
        .foregroundStyle(.white.opacity(0.8))
        .animation(.easeOut(duration: 0.15), value: player.sources)
    }
}

struct ProgressScrubber: View {
    @ObservedObject var player: NowPlayingMonitor
    @State private var dragValue: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let dur = player.duration
            let pos = dragValue ?? player.position(at: ctx.date)
            HStack(spacing: 10) {
                Text(format(pos)).frame(width: 36, alignment: .leading)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.2))
                        Capsule().fill(.white)
                            .frame(width: dur > 0 ? geo.size.width * min(pos / dur, 1) : 0)
                    }
                    .frame(height: dragValue == nil ? 5 : 8)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            guard dur > 0 else { return }
                            dragValue = min(max(g.location.x / geo.size.width, 0), 1) * dur
                        }
                        .onEnded { _ in
                            if let v = dragValue { player.seek(to: v) }
                            dragValue = nil
                        })
                    .animation(.easeOut(duration: 0.15), value: dragValue == nil)
                }
                .frame(height: 14)
                Text("-" + format(max(dur - pos, 0))).frame(width: 42, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func format(_ t: Double) -> String { TimerManager.format(t.rounded(.down)) }
}

// MARK: - Calendrier

struct CalendarWidget: View {
    @ObservedObject var calendar: CalendarMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            TimelineView(.everyMinute) { ctx in
                Text(ctx.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .textCase(.uppercase)
            }
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(Color(red: 1, green: 0.36, blue: 0.33))

            switch calendar.access {
            case .granted:
                if let event = calendar.next {
                    HStack(alignment: .top, spacing: 7) {
                        RoundedRectangle(cornerRadius: 1.5).fill(event.color).frame(width: 3, height: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                            TimelineView(.everyMinute) { ctx in
                                Text(event.subtitle(at: ctx.date))
                            }
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                        }
                    }
                } else {
                    Text("Rien de prévu d'ici demain").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                }
            case .denied:
                Button("Autoriser le calendrier…") { calendar.openPrivacySettings() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            case .unknown:
                Button("Afficher mon agenda") { calendar.requestAccess() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

// MARK: - Minuteur

struct TimerWidget: View {
    @ObservedObject var timer: TimerManager

    var body: some View {
        if timer.isActive {
            HStack(spacing: 8) {
                Image(systemName: timer.kind == .stopwatch ? "stopwatch.fill" : "timer")
                    .font(.system(size: 14, weight: .semibold))
                TimerText(timer: timer)
                    .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                Spacer(minLength: 0)
                RoundButton(symbol: timer.isPaused ? "play.fill" : "pause.fill", tint: .orange) { timer.togglePause() }
                RoundButton(symbol: "xmark", tint: .white) { timer.stop() }
            }
            .foregroundStyle(.orange)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("MINUTEUR").font(.system(size: 10.5, weight: .bold)).foregroundStyle(.white.opacity(0.45))
                HStack(spacing: 5) {
                    ForEach([5, 15, 25], id: \.self) { m in
                        Chip(label: "\(m) min") { timer.startCountdown(TimeInterval(m * 60)) }
                    }
                    Chip(symbol: "stopwatch") { timer.startStopwatch() }
                }
            }
        }
    }
}

// MARK: - Rappels

struct RemindersTab: View {
    @ObservedObject var monitor: ReminderMonitor
    @Binding var isEditing: Bool
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        switch monitor.access {
        case .granted:
            HStack(alignment: .top, spacing: 14) {
                Group {
                    if monitor.items.isEmpty {
                        VStack(spacing: 5) {
                            Image(systemName: "checkmark.circle").font(.system(size: 22)).foregroundStyle(.white.opacity(0.4))
                            Text("Tout est fait").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 2) {
                                ForEach(monitor.items) { item in
                                    ReminderRow(item: item) { monitor.complete(item) }
                                        .transition(.opacity.combined(with: .move(edge: .leading)))
                                }
                            }
                            .animation(.easeOut(duration: 0.2), value: monitor.items)
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 8) {
                    TextField("Nouveau rappel", text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($focused)
                        .onSubmit {
                            monitor.add(title: draft)
                            draft = ""
                            focused = false
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.1)))
                    ShelfAction(title: "Rappels", symbol: "arrow.up.forward.app") { monitor.openRemindersApp() }
                }
                .frame(width: 150)
            }
            .onChange(of: focused) { _, f in isEditing = f }
        case .denied:
            VStack(spacing: 8) {
                Image(systemName: "lock.shield").font(.system(size: 22)).foregroundStyle(.white.opacity(0.4))
                Text("Accès aux rappels refusé").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                ShelfAction(title: "Ouvrir les Réglages", symbol: "gearshape") { monitor.openPrivacySettings() }
                    .frame(width: 170)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unknown:
            ShelfAction(title: "Afficher mes rappels", symbol: "checklist") { monitor.requestAccess() }
                .frame(width: 190)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct ReminderRow: View {
    let item: ReminderMonitor.Item
    let complete: () -> Void
    @State private var checked = false
    @State private var hover = false

    var body: some View {
        HStack(spacing: 9) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { checked = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: complete)
            } label: {
                ZStack {
                    Circle().strokeBorder(item.color, lineWidth: 1.5)
                    if checked || hover {
                        Circle().fill(item.color.opacity(checked ? 1 : 0.25)).padding(3)
                    }
                }
                .frame(width: 16, height: 16)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { h in hover = h }

            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(checked ? 0.4 : 0.95))
                    .strikethrough(checked)
                TimelineView(.everyMinute) { ctx in
                    if let due = item.dueText(at: ctx.date) {
                        Text(due)
                            .font(.system(size: 10.5))
                            .foregroundStyle(item.isOverdue(at: ctx.date) ? Color.red : .white.opacity(0.45))
                    }
                }
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Notifications

struct NotificationsTab: View {
    @ObservedObject var monitor: NotificationMonitor

    var body: some View {
        switch monitor.access {
        case .granted:
            if monitor.recent.isEmpty {
                message(symbol: "bell.slash", title: "Aucune notification récente", detail: nil)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 4) {
                            ForEach(monitor.recent) { item in
                                NotificationRow(item: item) { monitor.openApp(of: item) }
                            }
                        }
                    }
                    VStack(spacing: 8) {
                        ShelfAction(title: monitor.isEnabled ? "Muet" : "Activer",
                                    symbol: monitor.isEnabled ? "bell.slash" : "bell") { monitor.isEnabled.toggle() }
                        ShelfAction(title: "Effacer", symbol: "xmark") { monitor.clearRecent() }
                    }
                    .frame(width: 92)
                }
            }
        case .unsupported(let reason):
            message(symbol: "exclamationmark.triangle", title: "Notifications illisibles", detail: reason)
        case .denied, .unknown:
            VStack(spacing: 8) {
                message(symbol: "lock.shield", title: "Accès aux notifications requis",
                        detail: "Ajoutez Dynamic Island dans Réglages › Confidentialité › Accès complet au disque, puis relancez-la.")
                ShelfAction(title: "Ouvrir les Réglages", symbol: "gearshape") { monitor.openPrivacySettings() }
                    .frame(width: 170)
            }
        }
    }

    private func message(symbol: String, title: String, detail: String?) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(.white.opacity(0.4))
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
            if let detail {
                Text(detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.4)).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NotificationRow: View {
    let item: NotificationMonitor.Item
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(nsImage: AppIcons.icon(for: item.bundleID)).resizable().frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(item.title).font(.system(size: 12, weight: .semibold))
                        Spacer(minLength: 6)
                        Text(Self.relative(item.date, now: Date()))
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                    }
                    Text(item.body).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                }
                .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(hover ? 0.1 : 0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in hover = h }
    }

    static func relative(_ date: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "maintenant" }
        if minutes < 60 { return "il y a \(minutes) min" }
        if Calendar.current.isDate(date, inSameDayAs: now) { return date.formatted(date: .omitted, time: .shortened) }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

// MARK: - Étagère

struct ShelfTab: View {
    @ObservedObject var shelf: ShelfModel

    var body: some View {
        if shelf.items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down").font(.system(size: 26)).foregroundStyle(.white.opacity(0.4))
                Text("Glissez des fichiers ici").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                Text("Ils restent à portée de main, prêts à être redéposés ou envoyés par AirDrop.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.35))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.15), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        } else {
            HStack(spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(shelf.items, id: \.self) { url in FileTile(url: url, shelf: shelf) }
                    }
                }
                VStack(spacing: 8) {
                    ShelfAction(title: "AirDrop", symbol: "dot.radiowaves.up.forward") { shelf.airDrop() }
                    ShelfAction(title: "Vider", symbol: "trash") { shelf.clear() }
                }
                .frame(width: 92)
            }
        }
    }
}

struct FileTile: View {
    let url: URL
    let shelf: ShelfModel
    @State private var hover = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 52, height: 52)
            Text(url.lastPathComponent)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 28, alignment: .top)
        }
        .frame(width: 76)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(hover ? 0.08 : 0)))
        .overlay(alignment: .topTrailing) {
            if hover {
                Button { shelf.remove(url) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color(white: 0.3))
                }
                .buttonStyle(.plain)
                .offset(x: 2, y: -2)
            }
        }
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .onTapGesture(count: 2) { shelf.open(url) }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu {
            Button("Ouvrir") { shelf.open(url) }
            Button("Afficher dans le Finder") { shelf.reveal(url) }
            Divider()
            Button("Retirer de l'étagère") { shelf.remove(url) }
        }
    }
}
