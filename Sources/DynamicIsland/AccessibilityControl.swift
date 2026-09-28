import AppKit
import ApplicationServices

/// Pilote les menus d'une autre app via l'API d'accessibilité (autorisation
/// « Accessibilité » requise). Sert à relancer Deezer quand il n'est plus
/// enregistré comme lecteur auprès de macOS.
enum AccessibilityControl {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Affiche la demande d'autorisation de macOS (une seule fois par signature d'app).
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Active le premier élément de menu de l'app dont le titre figure dans `titles`.
    static func pressMenuItem(of bundleID: String, titles: Set<String>) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return false }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 1)
        guard let menuBar: AXUIElement = attribute(root, kAXMenuBarAttribute) else { return false }
        return press(in: menuBar, titles: titles, depth: 0)
    }

    private static func press(in element: AXUIElement, titles: Set<String>, depth: Int) -> Bool {
        guard depth < 5, let children: [AXUIElement] = attribute(element, kAXChildrenAttribute) else { return false }
        for child in children {
            let role: String? = attribute(child, kAXRoleAttribute)
            if role == kAXMenuItemRole as String,
               let title: String = attribute(child, kAXTitleAttribute), titles.contains(title),
               (attribute(child, kAXEnabledAttribute) as Bool?) != false,
               AXUIElementPerformAction(child, kAXPressAction as CFString) == .success {
                return true
            }
            if press(in: child, titles: titles, depth: depth + 1) { return true }
        }
        return false
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
