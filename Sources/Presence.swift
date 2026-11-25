// mKOBO — présence de l'appli : Dock, barre de menus, ou les deux (préférence dans les réglages).
// Icône de barre de menus : silhouette du logo en couleur (choix du 25/11/2026), sans fond. Jamais de statusItem.menu :
// le menu est ouvert sous l'icône par `socleShow` (plusieurs écrans).
import AppKit

enum IconMode: String, CaseIterable, Identifiable {
    case dock, menubar, both
    var id: String { rawValue }
    var label: String { L.t("settings.icon.\(rawValue)") }
    var showsDock: Bool { self != .menubar }
    var showsMenuBar: Bool { self != .dock }
    static var current: IconMode {
        get { IconMode(rawValue: UserDefaults.standard.string(forKey: "iconMode") ?? "") ?? .dock }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "iconMode") }
    }
}

@MainActor
final class Presence: NSObject {
    static let shared = Presence()
    private var item: NSStatusItem?

    func apply() {
        let m = IconMode.current
        let wanted: NSApplication.ActivationPolicy = m.showsDock ? .regular : .accessory
        if NSApp.activationPolicy() != wanted { NSApp.setActivationPolicy(wanted) }
        if m.showsMenuBar { installItem() } else { removeItem() }
    }

    func set(_ m: IconMode) {
        IconMode.current = m
        apply()
        if m == .menubar { NSApp.activate() }
    }

    private func installItem() {
        if item == nil { item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength) }
        guard let it = item else { return }
        it.button?.image = Self.silhouette()
        it.button?.imagePosition = .imageOnly
        it.button?.toolTip = "mKOBO"
        it.menu = nil
        it.button?.target = self
        it.button?.action = #selector(clicked)
        it.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func removeItem() {
        if let it = item { NSStatusBar.system.removeStatusItem(it) }
        item = nil
    }

    /// Livre ouvert corail : le logo sans son carré de fond (image en couleur, pas une image « modèle »).
    static func silhouette() -> NSImage {
        let img = NSImage(size: NSSize(width: 19, height: 15), flipped: false) { _ in
            let coral = NSColor(srgbRed: 1, green: 0.42, blue: 0.29, alpha: 1)
            func page(_ flip: Bool) -> NSBezierPath {
                let p = NSBezierPath()
                let x: (CGFloat) -> CGFloat = { flip ? 19 - $0 : $0 }
                p.move(to: NSPoint(x: x(9.5), y: 2.2)); p.line(to: NSPoint(x: x(9.5), y: 12))
                p.curve(to: NSPoint(x: x(1.2), y: 13), controlPoint1: NSPoint(x: x(7), y: 13), controlPoint2: NSPoint(x: x(3.6), y: 13.2))
                p.line(to: NSPoint(x: x(1.2), y: 3.2))
                p.curve(to: NSPoint(x: x(9.5), y: 2.2), controlPoint1: NSPoint(x: x(3.6), y: 3.4), controlPoint2: NSPoint(x: x(7), y: 3.2))
                p.close()
                return p
            }
            coral.withAlphaComponent(0.28).setFill()
            coral.setStroke()
            for flip in [false, true] { let p = page(flip); p.lineWidth = 1.7; p.lineJoinStyle = .round; p.fill(); p.stroke() }
            return true
        }
        img.isTemplate = false
        return img
    }

    @objc private func clicked() {
        guard let it = item else { return }
        let e = NSApp.currentEvent
        if e?.type == .rightMouseUp || e?.modifierFlags.contains(.control) == true { it.socleShow(menu()) }
        else if AppDelegate.shared?.window?.isVisible == true, NSApp.isActive { AppDelegate.shared?.window?.orderOut(nil) }
        else { AppDelegate.shared?.showMain() }
    }

    private func menu() -> NSMenu {
        let m = NSMenu()
        func add(_ title: String, _ sel: Selector, enabled: Bool = true) { let i = NSMenuItem(title: title, action: sel, keyEquivalent: ""); i.target = self; i.isEnabled = enabled; m.addItem(i) }
        add(L.t("menu.open"), #selector(openMain))
        m.addItem(.separator())
        let dev = DeviceMonitor.shared.device
        add(dev.map { L.t("status.koboOn", $0.model) } ?? L.t("pill.koboOff"), #selector(openMain), enabled: false)
        let active = Store.shared.jobs.filter { $0.stage.rawValue < Stage.done.rawValue }.count
        if active > 0 { add(L.t("nav.jobs") + " · \(active)", #selector(openJobs)) }
        m.addItem(.separator())
        add(L.t("menu.settings"), #selector(openSettings))
        add(L.t("menu.about"), #selector(openAbout))
        m.addItem(.separator())
        add(L.t("menu.quit"), #selector(quit))
        return m
    }

    @objc private func openMain() { AppDelegate.shared?.showMain() }
    @objc private func openJobs() { Store.shared.screen = .jobs; AppDelegate.shared?.showMain() }
    @objc private func openSettings() { AppDelegate.shared?.showSettings() }
    @objc private func openAbout() { AppDelegate.shared?.showAbout() }
    @objc private func quit() { NSApp.terminate(nil) }
}
