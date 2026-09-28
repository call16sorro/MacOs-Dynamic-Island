import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var controller: IslandController?
    private var statusItem: NSStatusItem?
    private var loginItem: NSMenuItem?
    private var notificationsItem: NSMenuItem?

    private var model: IslandModel? { controller?.model }

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = IslandController()
        setupStatusItem()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Dynamic Island")

        let menu = NSMenu()
        menu.delegate = self

        let timers = NSMenu()
        for minutes in [1, 5, 10, 15, 25, 60] {
            add("\(minutes) min", #selector(startTimer(_:)), to: timers).tag = minutes
        }
        timers.addItem(.separator())
        add("Chronomètre", #selector(startStopwatch), to: timers)
        add("Arrêter", #selector(stopTimer), to: timers)
        menu.addItem(withTitle: "Minuteur", action: nil, keyEquivalent: "").submenu = timers

        let demos = NSMenu()
        add("Branchement secteur", #selector(demoCharging), to: demos)
        add("AirPods connectés", #selector(demoAirPods), to: demos)
        add("Rappel d'événement", #selector(demoEvent), to: demos)
        add("Fin du minuteur", #selector(demoTimerDone), to: demos)
        add("Notification", #selector(demoNotification), to: demos)
        add("Rappel", #selector(demoReminder), to: demos)
        menu.addItem(withTitle: "Simuler", action: nil, keyEquivalent: "").submenu = demos

        menu.addItem(.separator())
        notificationsItem = add("Afficher les notifications", #selector(toggleNotifications), to: menu)
        add("Autoriser l'accès aux notifications…", #selector(openNotificationSettings), to: menu)
        loginItem = add("Ouvrir au démarrage de la session", #selector(toggleLoginItem), to: menu)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter Dynamic Island", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        loginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        notificationsItem?.state = model?.notifications.isEnabled == true ? .on : .off
    }

    // MARK: - Actions

    @objc private func startTimer(_ sender: NSMenuItem) { model?.timer.startCountdown(TimeInterval(sender.tag * 60)) }
    @objc private func startStopwatch() { model?.timer.startStopwatch() }
    @objc private func stopTimer() { model?.timer.stop() }

    @objc private func toggleNotifications() { model?.notifications.isEnabled.toggle() }
    @objc private func openNotificationSettings() { model?.notifications.openPrivacySettings() }

    @objc private func demoNotification() {
        model?.showActivity(.notification(.init(id: -1, bundleID: "com.apple.MobileSMS", appName: "Messages",
                                                title: "Léa", subtitle: "", body: "On se retrouve à 19 h devant le cinéma ?",
                                                date: Date())))
    }

    @objc private func demoReminder() {
        NSSound(named: "Tink")?.play()
        model?.showActivity(.reminder(title: "Appeler le garagiste", color: .orange))
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Impossible de modifier l'ouverture au démarrage"
            alert.runModal()
        }
    }

    @objc private func demoCharging() {
        guard let model else { return }
        model.showActivity(.charging(level: model.battery.level, plugged: true))
    }

    @objc private func demoAirPods() {
        model?.showActivity(.bluetooth(name: "AirPods Pro", symbol: "airpodspro", connected: true, battery: 84))
    }

    @objc private func demoEvent() {
        model?.showActivity(.event(title: "Point d'équipe", minutes: 5, color: .blue))
    }

    @objc private func demoTimerDone() {
        NSSound(named: "Glass")?.play()
        model?.showActivity(.timerDone)
    }
}
