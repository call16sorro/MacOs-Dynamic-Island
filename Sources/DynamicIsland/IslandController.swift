import AppKit
import SwiftUI

/// Crée la fenêtre, la place sur l'encoche et gère le survol de la souris.
final class IslandController {
    let model: IslandModel
    private let panel: IslandPanel
    private var screen: NSScreen
    private var timer: Timer?
    private var insideSince: Date?
    private var outsideSince: Date?

    private static let canvas = CGSize(width: 820, height: 340)

    init() {
        screen = Self.preferredScreen()
        model = IslandModel(notchSize: screen.notchSize)
        panel = IslandPanel(contentRect: NSRect(origin: .zero, size: Self.canvas))

        let host = NSHostingView(rootView: IslandView(model: model))
        host.frame = NSRect(origin: .zero, size: Self.canvas)
        panel.contentView = host

        reposition()
        panel.orderFrontRegardless()

        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.trackMouse() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // Clic ailleurs pendant la saisie d'un rappel : on libère l'île.
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel,
                                               queue: .main) { [weak self] _ in
            self?.model.isEditingText = false
        }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.screen = Self.preferredScreen()
            self.model.notchSize = self.screen.notchSize
            self.reposition()
        }
    }

    private static func preferredScreen() -> NSScreen {
        NSScreen.screens.first(where: \.hasNotch) ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func reposition() {
        let f = screen.frame
        let origin = CGPoint(x: f.midX - Self.canvas.width / 2, y: f.maxY - Self.canvas.height)
        panel.setFrame(NSRect(origin: origin, size: Self.canvas), display: true)
    }

    private func trackMouse() {
        let mouse = NSEvent.mouseLocation
        let f = screen.frame
        let size = model.size
        var rect = CGRect(x: f.midX - size.width / 2, y: f.maxY - size.height,
                          width: size.width, height: size.height + 2)
        if !model.isHovering {
            // Zone de déclenchement un peu plus généreuse autour de l'encoche.
            rect = rect.insetBy(dx: -8, dy: -4)
        }
        let inside = rect.contains(mouse)
        let now = Date()

        if inside {
            outsideSince = nil
            if insideSince == nil { insideSince = now }
            if !model.isHovering, now.timeIntervalSince(insideSince!) > 0.06 {
                model.isHovering = true
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        } else {
            insideSince = nil
            if outsideSince == nil { outsideSince = now }
            // Bouton enfoncé : glisser-déposer ou déplacement dans la barre de lecture en cours.
            if model.isHovering, NSEvent.pressedMouseButtons == 0, !model.isEditingText, now.timeIntervalSince(outsideSince!) > 0.18 {
                model.isHovering = false
            }
        }
        panel.ignoresMouseEvents = !(inside && model.isHovering)
    }
}
