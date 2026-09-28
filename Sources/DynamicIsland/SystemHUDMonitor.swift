import AppKit
import AudioToolbox
import CoreAudio

/// Suit le volume de la sortie audio par défaut (CoreAudio, sans permission).
final class VolumeMonitor {
    var onChange: ((Float, Bool) -> Void)?

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var last: (Float, Bool)?
    private var quietUntil = Date()

    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)

    func start() {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { [weak self] _, _ in
            self?.attach()
        }
        attach()
    }

    private func attach() {
        for (addr, block) in listeners {
            var a = addr
            AudioObjectRemovePropertyListenerBlock(device, &a, .main, block)
        }
        listeners.removeAll()

        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr else { return }
        device = id
        // Changer de sortie (AirPods…) modifie le volume : pas de HUD pour ça.
        quietUntil = Date().addingTimeInterval(1)
        last = read()

        for base in [Self.volumeAddress, Self.muteAddress] {
            var a = base
            guard AudioObjectHasProperty(device, &a) else { continue }
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.changed() }
            AudioObjectAddPropertyListenerBlock(device, &a, .main, block)
            listeners.append((base, block))
        }
    }

    private func read() -> (Float, Bool)? {
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var a = Self.volumeAddress
        guard AudioObjectHasProperty(device, &a),
              AudioObjectGetPropertyData(device, &a, 0, nil, &size, &volume) == noErr else { return nil }
        var muted: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        var m = Self.muteAddress
        if AudioObjectHasProperty(device, &m) {
            AudioObjectGetPropertyData(device, &m, 0, nil, &size, &muted)
        }
        return (volume, muted != 0)
    }

    private func changed() {
        guard let now = read() else { return }
        defer { last = now }
        if let last, abs(last.0 - now.0) < 0.001, last.1 == now.1 { return }
        guard Date() > quietUntil else { return }
        onChange?(now.0, now.1)
    }
}

/// Suit la luminosité de l'écran intégré (DisplayServices, framework privé en lecture seule).
final class BrightnessMonitor {
    var onChange: ((Float) -> Void)?

    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private var getBrightness: GetBrightness?
    private var display: CGDirectDisplayID = 0
    private var last: Float?
    private var lastShown = Date.distantPast
    private var timer: Timer?

    func start() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let sym = dlsym(handle, "DisplayServicesGetBrightness") else { return }
        getBrightness = unsafeBitCast(sym, to: GetBrightness.self)

        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &count)
        guard let builtin = ids.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) != 0 }) else { return }
        display = builtin
        last = read()

        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func read() -> Float? {
        var value: Float = 0
        guard let getBrightness, getBrightness(display, &value) == 0 else { return nil }
        return value
    }

    private func poll() {
        guard let now = read() else { return }
        defer { last = now }
        guard let last else { return }
        let delta = abs(now - last)
        // La luminosité auto varie lentement ; les touches font des sauts d'1/16.
        // Une fois le HUD affiché, on suit chaque variation pour une jauge fluide.
        let following = Date().timeIntervalSince(lastShown) < 1.2
        guard delta >= 0.015 || (following && delta > 0.001) else { return }
        lastShown = Date()
        onChange?(now)
    }
}
