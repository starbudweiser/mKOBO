// mKOBO — trouve des livres, BD et livres audio gratuits et légaux, et les envoie sur une liseuse Kobo ou sur Google Drive.
import AppKit
import SwiftUI

@main
struct MkoboApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Window("mKOBO", id: "main") { RootView() }
            .defaultSize(width: 1180, height: 760)
            .windowStyle(.hiddenTitleBar)
            .commands {
                CommandGroup(replacing: .newItem) {}
                CommandGroup(replacing: .appInfo) { Button(L.t("menu.about")) { AppDelegate.shared?.showAbout() } }
                CommandGroup(replacing: .appSettings) { Button(L.t("menu.settings")) { AppDelegate.shared?.showSettings() }.keyboardShortcut(",") }
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    var window: NSWindow?
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    static let isDev = (Bundle.main.bundleIdentifier ?? "").hasSuffix(".dev")

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        UserDefaults.standard.register(defaults: ["autoUpdate": true])
        Prefs.applyTheme()
        Presence.shared.apply()
        DeviceMonitor.shared.start()
        UpdateEngine.shared.configure(repo: "mKOBO", lang: { L.code }, brandName: "mKOBO")
        UpdateEngine.shared.autoInstall = { UserDefaults.standard.bool(forKey: "autoUpdate") }
        if !AppDelegate.isDev, !CommandLine.arguments.contains("--selftest"), !CommandLine.arguments.contains("--capture") { UpdateEngine.shared.start() }
        UpdateEngine.shared.installAppMenuItem()
        SelfTest.runIfRequested()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !IconMode.current.showsMenuBar }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showMain(); return true }

    @MainActor func showMain() {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    @MainActor func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 720), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.title = L.t("settings.title")
            w.titlebarAppearsTransparent = true
            w.backgroundColor = Theme.ns(0x131316, 0xf5f5f7)
            w.contentView = NSHostingView(rootView: SettingsView())
            settingsWindow = w
        }
        recenterOnOpen(settingsWindow)      // règle Socle : fenêtre secondaire centrée sur la fenêtre de l'appli, à chaque ouverture
    }

    @MainActor func showAbout() {
        if aboutWindow == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.title = L.t("about.menu")
            w.titlebarAppearsTransparent = true
            w.backgroundColor = Theme.ns(0x131316, 0xf5f5f7)
            let host = NSHostingView(rootView: AboutView())
            w.contentView = host
            w.setContentSize(host.fittingSize)
            aboutWindow = w
        }
        recenterOnOpen(aboutWindow)
    }

    /// Centre la fenêtre secondaire avant son affichage, puis une seconde fois quand sa taille définitive est connue (la vue SwiftUI la ajuste à l'ouverture).
    @MainActor private func recenterOnOpen(_ w: NSWindow?) {
        guard let w else { return }
        w.layoutIfNeeded()
        w.updaterCenter()
        w.present()
        for delay in [0.0, 0.15] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { w.updaterCenter() } }
        }
    }

    /// Choix du dossier Google Drive (dossier synchronisé). `completion(true)` si un dossier a été choisi.
    @MainActor func chooseDriveFolder(_ completion: ((Bool) -> Void)? = nil) {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.message = L.t("drive.prompt")
        p.directoryURL = Prefs.drivePath.map { URL(fileURLWithPath: $0) } ?? DeviceMonitor.suggestedDriveFolder()
        NSApp.activate()
        if p.runModal() == .OK, let u = p.url {
            Prefs.drivePath = u.path
            NotificationCenter.default.post(name: .driveFolderChanged, object: nil)
            DeviceMonitor.shared.refresh()
            completion?(true)
        } else { completion?(false) }
    }
}

extension Notification.Name { static let driveFolderChanged = Notification.Name("mkobo.driveFolderChanged") }

extension NSWindow {
    @MainActor func present() {
        NSApp.activate()
        orderFrontRegardless()
        makeKeyAndOrderFront(nil)
    }
}
