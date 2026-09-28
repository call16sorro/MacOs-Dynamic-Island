import IOBluetooth

/// Annonce la connexion / déconnexion d'appareils Bluetooth (AirPods, claviers…).
final class BluetoothMonitor: NSObject {
    struct Event {
        let name: String
        let symbol: String
        let connected: Bool
        let battery: Int?
    }

    var onEvent: ((Event) -> Void)?
    private var connectNotification: IOBluetoothUserNotification?
    private var startDate = Date()

    func start() {
        startDate = Date()
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self,
                                                         selector: #selector(deviceConnected(_:device:)))
    }

    @objc private func deviceConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
        // À l'enregistrement, macOS signale les appareils déjà connectés : on les ignore.
        guard Date().timeIntervalSince(startDate) > 3 else { return }
        // La batterie n'est connue qu'un instant après la connexion.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.onEvent?(Self.event(for: device, connected: true))
        }
    }

    @objc private func deviceDisconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        note.unregister()
        onEvent?(Self.event(for: device, connected: false))
    }

    private static func event(for device: IOBluetoothDevice, connected: Bool) -> Event {
        let name = device.name ?? "Appareil Bluetooth"
        return Event(name: name, symbol: symbol(for: device, name: name), connected: connected,
                     battery: connected ? battery(of: device) : nil)
    }

    static func symbol(for device: IOBluetoothDevice?, name: String) -> String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("beats") { return "beats.headphones" }
        if n.contains("keyboard") || n.contains("clavier") { return "keyboard" }
        if n.contains("mouse") || n.contains("souris") { return "magicmouse" }
        if n.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        if let device, device.deviceClassMajor == UInt32(kBluetoothDeviceClassMajorAudio) { return "headphones" }
        return "wave.3.right"
    }

    /// Niveaux exposés par IOBluetooth en privé (AirPods, Beats…), lus prudemment.
    private static func battery(of device: IOBluetoothDevice) -> Int? {
        func read(_ key: String) -> Int? {
            guard device.responds(to: NSSelectorFromString(key)),
                  let v = (device.value(forKey: key) as? NSNumber)?.intValue, v > 0 else { return nil }
            return v
        }
        if let single = read("batteryPercentSingle") { return single }
        let buds = [read("batteryPercentLeft"), read("batteryPercentRight")].compactMap { $0 }
        if let low = buds.min() { return low }
        return read("batteryPercentCombined")
    }
}
