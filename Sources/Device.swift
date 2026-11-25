// mKOBO — réglages, détection de la liseuse Kobo (volume USB) et lecture de son contenu.
import AppKit
import Foundation

enum Prefs {
    private static let d = UserDefaults.standard
    static var koboFolder: String { get { d.string(forKey: "koboFolder") ?? "mKOBO" } set { d.set(newValue, forKey: "koboFolder") } }
    static var classifyByAuthor: Bool { get { d.object(forKey: "classify") as? Bool ?? true } set { d.set(newValue, forKey: "classify") } }
    static var nameWithAuthor: Bool { get { d.object(forKey: "nameAuthor") as? Bool ?? true } set { d.set(newValue, forKey: "nameAuthor") } }
    static var kepub: Bool { get { d.object(forKey: "kepub") as? Bool ?? true } set { d.set(newValue, forKey: "kepub") } }
    static var ejectAfter: Bool { get { d.bool(forKey: "eject") } set { d.set(newValue, forKey: "eject") } }
    static var drivePath: String? { get { d.string(forKey: "drivePath") } set { d.set(newValue, forKey: "drivePath") } }
    static var theme: String { get { d.string(forKey: "theme") ?? "auto" } set { d.set(newValue, forKey: "theme") } }
    static var viewMode: String { get { d.string(forKey: "viewMode") ?? "grid" } set { d.set(newValue, forKey: "viewMode") } }
    static var sources: Set<SourceID> {
        get { (d.string(forKey: "sources")).map { Set($0.split(separator: ",").compactMap { SourceID(rawValue: String($0)) }) } ?? Set(SourceID.allCases) }
        set { d.set(newValue.map(\.rawValue).sorted().joined(separator: ","), forKey: "sources") }
    }
    static var langs: Set<String> {
        get { (d.string(forKey: "langs")).map { Set($0.split(separator: ",").map(String.init)) } ?? ["fr", "en"] }
        set { d.set(newValue.sorted().joined(separator: ","), forKey: "langs") }
    }
    static func applyTheme() {
        switch theme { case "dark": NSApp.appearance = NSAppearance(named: .darkAqua); case "light": NSApp.appearance = NSAppearance(named: .aqua); default: NSApp.appearance = nil }
    }
}

struct DeviceBook: Identifiable, Hashable {
    var id: String { url.path }
    var name: String
    var url: URL
    var size: Int64
    var date: Date
}

struct KoboDevice: Equatable {
    var volume: URL
    var model: String
    var firmware: String
    var free: Int64
    var total: Int64
}

/// Surveille le branchement de la Kobo (un volume qui contient « .kobo/version ») et lit son contenu.
@MainActor
final class DeviceMonitor: ObservableObject {
    static let shared = DeviceMonitor()
    @Published private(set) var device: KoboDevice?
    @Published private(set) var books: [DeviceBook] = []
    @Published private(set) var driveFiles: [DeviceBook] = []
    private var timer: Timer?

    nonisolated static let bookExts: Set<String> = ["epub", "cbz", "cbr", "pdf", "kepub"]

    func start() {
        refresh()
        for n in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }

    func refresh() {
        let found = Self.detect()
        if found != device { device = found; books = [] }
        if let found { Task { books = await Self.scan(found.volume) } }
        if let p = Prefs.drivePath { Task { driveFiles = await Self.scan(URL(fileURLWithPath: p), allFiles: true) } } else { driveFiles = [] }
    }

    nonisolated static func detect() -> KoboDevice? {
        let keys: [URLResourceKey] = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        for v in FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? [] {
            let versionFile = v.appendingPathComponent(".kobo/version")
            guard let text = try? String(contentsOf: versionFile, encoding: .utf8) else { continue }
            let f = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: ",")
            let serial = f.first ?? ""
            let models = ["N428": "Kobo Libra Colour", "N418": "Kobo Libra 2", "N873": "Kobo Libra H2O", "N605": "Kobo Clara 2E", "N367": "Kobo Clara HD", "N306": "Kobo Nia", "N709": "Kobo Clara BW", "N708": "Kobo Clara Colour", "N506": "Kobo Elipsa"]
            let model = models[String(serial.prefix(4))] ?? "Kobo"
            let fw = f.first { $0.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil && $0.split(separator: ".").first.map { Int($0)! > 3 } == true } ?? ""
            let rv = try? v.resourceValues(forKeys: Set(keys))
            return KoboDevice(volume: v, model: model, firmware: fw, free: Int64(rv?.volumeAvailableCapacityForImportantUsage ?? 0), total: Int64(rv?.volumeTotalCapacity ?? 0))
        }
        return nil
    }

    nonisolated static func scan(_ root: URL, allFiles: Bool = false) async -> [DeviceBook] {
        await Task.detached(priority: .utility) {
            var out: [DeviceBook] = []
            let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]
            guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
            while let u = en.nextObject() as? URL {
                if out.count > 3000 { break }
                let rv = try? u.resourceValues(forKeys: Set(keys))
                if rv?.isDirectory == true { continue }
                if !allFiles, !bookExts.contains(u.pathExtension.lowercased()) { continue }
                out.append(DeviceBook(name: u.deletingPathExtension().lastPathComponent, url: u, size: Int64(rv?.fileSize ?? 0), date: rv?.contentModificationDate ?? .distantPast))
            }
            return out.sorted { $0.date > $1.date }
        }.value
    }

    func eject() {
        guard let d = device else { return }
        try? NSWorkspace.shared.unmountAndEjectDevice(at: d.volume)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.refresh() }
    }

    /// Dossier Google Drive probable (Google Drive pour ordinateur ou CloudMounter) : proposé au premier choix.
    static func suggestedDriveFolder() -> URL? {
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/CloudStorage")
        let drives = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
        return drives.first { $0.lastPathComponent.localizedCaseInsensitiveContains("GoogleDrive") }
    }
}
