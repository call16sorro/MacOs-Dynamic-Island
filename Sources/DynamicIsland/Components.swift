import SwiftUI

struct Artwork: View {
    let image: NSImage?
    let size: CGFloat
    let corner: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [.gray.opacity(0.5), .gray.opacity(0.25)], startPoint: .top, endPoint: .bottom)
                Image(systemName: "music.note").font(.system(size: size * 0.45)).foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

struct EqualizerBars: View {
    let playing: Bool
    let color: Color
    var bars = 4
    var maxHeight: CGFloat = 14

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !playing)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<bars, id: \.self) { i in
                    let v = playing ? 0.3 + 0.7 * abs(sin(t * (2.6 + Double(i) * 1.15) + Double(i) * 1.7)) : 0.2
                    Capsule().fill(color).frame(width: 3, height: maxHeight * v)
                }
            }
            .frame(height: maxHeight)
        }
    }
}

struct BatteryIcon: View {
    let level: Int
    let charging: Bool

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3.5).stroke(.white.opacity(0.45), lineWidth: 1)
                RoundedRectangle(cornerRadius: 2)
                    .fill(fill)
                    .frame(width: max(2, 19 * CGFloat(level) / 100))
                    .padding(2)
                if charging {
                    Image(systemName: "bolt.fill").font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white).frame(maxWidth: .infinity)
                }
            }
            .frame(width: 25, height: 12)
            RoundedRectangle(cornerRadius: 1).fill(.white.opacity(0.45)).frame(width: 1.5, height: 4)
        }
    }

    private var fill: Color {
        if charging { return .green }
        return level <= 20 ? .red : .white
    }
}

/// Anneau de batterie façon AirPods.
struct BatteryRing: View {
    let value: Double

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.2), lineWidth: 2.5)
            Circle().trim(from: 0, to: value)
                .stroke(value <= 0.2 ? .red : .green, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 15, height: 15)
    }
}

/// Jauge horizontale (volume, luminosité).
struct LevelBar: View {
    let value: Double
    var color: Color = .white

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule().fill(color).frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.12), value: value)
    }
}

/// Pastilles caméra (verte) et micro (orange).
struct PrivacyDots: View {
    let camera: Bool
    let microphone: Bool

    var body: some View {
        HStack(spacing: 4) {
            if camera { Circle().fill(.green).frame(width: 7, height: 7) }
            if microphone { Circle().fill(.orange).frame(width: 7, height: 7) }
        }
    }
}

struct TimerText: View {
    @ObservedObject var timer: TimerManager

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            Text(timer.text(at: ctx.date))
        }
    }
}

struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .frame(width: size + 16, height: size + 12)
                .contentShape(Rectangle())
                .scaleEffect(hover ? 1.12 : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }
}

struct RoundButton: View {
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(Circle().fill(tint.opacity(0.2)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct Chip: View {
    var label: String?
    var symbol: String?
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Group {
                if let label { Text(label) } else if let symbol { Image(systemName: symbol) }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Capsule().fill(.orange.opacity(hover ? 0.3 : 0.18)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
    }
}

struct ShelfAction: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(title)
            }
            .font(.system(size: 12, weight: .medium))
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(hover ? 0.16 : 0.1)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
    }
}
