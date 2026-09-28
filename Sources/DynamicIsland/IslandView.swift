import SwiftUI
import UniformTypeIdentifiers

let islandSpring = Animation.spring(response: 0.42, dampingFraction: 0.78)
/// Fermeture : amortissement critique, aucun dépassement sous la taille de l'encoche.
let islandCloseSpring = Animation.spring(response: 0.36, dampingFraction: 1)

struct IslandView: View {
    @ObservedObject var model: IslandModel
    @State private var dropTargeted = false

    var body: some View {
        let size = model.size
        let tr = model.topRadius
        let shape = IslandShape(topRadius: tr, bottomRadius: model.bottomRadius)
        ZStack(alignment: .top) {
            Color.black
            content
                .padding(.horizontal, tr)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.8, anchor: .top)).animation(islandSpring.delay(0.08)),
                    removal: .opacity.animation(.easeOut(duration: 0.12))))
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay(shape.stroke(.white.opacity(dropTargeted ? 0.35 : 0), lineWidth: 1.5))
        .shadow(color: .black.opacity(model.mode == .expanded ? 0.45 : 0), radius: 14, y: 6)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            model.dropFiles(providers)
            return true
        }
        .onChange(of: dropTargeted) { _, targeted in
            if targeted { withAnimation(islandSpring) { model.tab = .shelf } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(model.isShrinking ? islandCloseSpring : islandSpring, value: model.mode)
        .animation(islandSpring, value: model.notchSize)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var content: some View {
        let n = model.notchSize
        switch model.mode {
        case .idle:
            EmptyView()
        case .compact(let layout):
            CompactView(player: model.player, timer: model.timer, layout: layout, notch: n)
                .frame(height: n.height)
                .id("compact")
        case .activity(.notification(let item)):
            NotificationBanner(item: item, notch: n)
                .frame(height: model.size.height, alignment: .top)
                .contentShape(Rectangle())
                .onTapGesture { model.openNotification(item) }
                .id("activity-notification-\(item.id)")
        case .activity(let activity):
            ActivityView(activity: activity, notch: n)
                .frame(height: n.height)
                .id("activity-" + activity.kind)
        case .expanded:
            let s = model.size(for: .expanded)
            ExpandedView(model: model, battery: model.battery, privacy: model.privacy, notch: n)
                .frame(width: s.width - 2 * model.topRadius, height: s.height)
                .id("expanded")
        }
    }
}

// MARK: - Compact

struct CompactView: View {
    @ObservedObject var player: NowPlayingMonitor
    @ObservedObject var timer: TimerManager
    let layout: CompactLayout
    let notch: CGSize

    var body: some View {
        let side = notch.height - 10
        HStack(spacing: 0) {
            if layout.music {
                Artwork(image: player.artwork, size: side, corner: 6)
            } else if layout.timer {
                Image(systemName: timer.kind == .stopwatch ? "stopwatch.fill" : "timer")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: side, height: side)
            }
            Spacer(minLength: notch.width)
            HStack(spacing: 8) {
                if layout.timer {
                    TimerText(timer: timer)
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.orange)
                } else if layout.music {
                    Group {
                        if player.isPlaying {
                            EqualizerBars(playing: true, color: player.accent, maxHeight: notch.height * 0.42)
                        } else {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(player.accent.opacity(0.9))
                        }
                    }
                    .frame(width: side)
                    .animation(.easeOut(duration: 0.2), value: player.isPlaying)
                }
                if layout.dotCount > 0 {
                    PrivacyDots(camera: layout.camera, microphone: layout.microphone)
                }
            }
        }
        .padding(.horizontal, 12)
    }
}

// MARK: - Activités temporaires

struct ActivityView: View {
    let activity: LiveActivity
    let notch: CGSize

    var body: some View {
        HStack(spacing: 6) {
            leading
            Spacer(minLength: notch.width)
            trailing
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white.opacity(0.9))
        .lineLimit(1)
        .padding(.horizontal, 12)
    }

    @ViewBuilder private var leading: some View {
        switch activity {
        case .charging(_, let plugged):
            Image(systemName: plugged ? "bolt.fill" : "powerplug")
                .foregroundStyle(plugged ? .green : .white.opacity(0.7))
            Text(plugged ? "En charge" : "Sur batterie")
        case .volume(let level, let muted):
            Image(systemName: Self.speaker(level: level, muted: muted))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 22, alignment: .leading)
        case .brightness:
            Image(systemName: "sun.max.fill").foregroundStyle(.yellow)
        case .bluetooth(let name, let symbol, _, _):
            Image(systemName: symbol)
            Text(name).truncationMode(.tail)
        case .timerDone:
            Image(systemName: "timer").foregroundStyle(.orange)
            Text("Minuteur")
        case .event(let title, _, let color):
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).truncationMode(.tail)
        case .shelf:
            Image(systemName: "tray.and.arrow.down.fill")
            Text("Étagère")
        case .notification:
            EmptyView()   // affichée par NotificationBanner
        case .reminder(let title, let color):
            Image(systemName: "checklist").foregroundStyle(color)
            Text(title).truncationMode(.tail)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch activity {
        case .charging(let level, let plugged):
            Text("\(level) %")
                .foregroundStyle(plugged ? .green : .white)
                .monospacedDigit()
            BatteryIcon(level: level, charging: plugged)
        case .volume(let level, let muted):
            LevelBar(value: muted ? 0 : Double(level))
                .frame(width: 70)
        case .brightness(let level):
            LevelBar(value: Double(level), color: .yellow)
                .frame(width: 70)
        case .bluetooth(_, _, let connected, let battery):
            if connected, let battery {
                Text("\(battery) %").monospacedDigit().foregroundStyle(.green)
                BatteryRing(value: Double(battery) / 100)
            } else {
                Text(connected ? "Connecté" : "Déconnecté")
                    .foregroundStyle(connected ? .green : .white.opacity(0.55))
            }
        case .timerDone:
            Text("Terminé").foregroundStyle(.orange)
        case .event(_, let minutes, _):
            Text("Dans \(minutes) min").foregroundStyle(.white.opacity(0.7))
        case .shelf(let count):
            Text("+\(count)").foregroundStyle(.white.opacity(0.7))
        case .notification:
            EmptyView()
        case .reminder:
            Text("Rappel").foregroundStyle(.orange)
        }
    }

    static func speaker(level: Float, muted: Bool) -> String {
        if muted || level <= 0.001 { return "speaker.slash.fill" }
        if level < 0.34 { return "speaker.wave.1.fill" }
        if level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

// MARK: - Notification

struct NotificationBanner: View {
    let item: NotificationMonitor.Item
    let notch: CGSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(nsImage: AppIcons.icon(for: item.bundleID)).resizable().frame(width: 16, height: 16)
                Text(item.appName).lineLimit(1)
                Spacer(minLength: notch.width)
                TimelineView(.everyMinute) { ctx in
                    Text(NotificationRow.relative(item.date, now: ctx.date))
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.55))
            .frame(height: notch.height)

            HStack(alignment: .top, spacing: 10) {
                Image(nsImage: AppIcons.icon(for: item.bundleID)).resizable().frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.subtitle.isEmpty ? item.title : "\(item.title) · \(item.subtitle)")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(item.body)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
    }
}
