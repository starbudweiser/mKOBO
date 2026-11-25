// mKOBO — essais silencieux (jamais de fenêtre au premier plan) :
//   --selftest            interroge chaque source, détecte la Kobo, vérifie les textes ;
//   --capture <png>       écrit une image de la fenêtre (options : --select N, --view list, --screen device|jobs, --query texte).
import AppKit
import Foundation

@MainActor
enum SelfTest {
    static func arg(_ name: String) -> String? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    static func runIfRequested() {
        if CommandLine.arguments.contains("--selftest-send") { Task { await runSend(); exit(0) } }
        if CommandLine.arguments.contains("--selftest") { Task { await run(); exit(0) } }
        if let path = arg("--capture") { capture(path) }
    }

    static func run() async {
        print("Langue : \(L.code) · textes incomplets : \(L.problems())")
        print("Kobo : \(DeviceMonitor.detect().map { "\($0.model) \($0.firmware) sur \($0.volume.path)" } ?? "non branchée") · kepubify : \(Kepubify.path ?? "absent")")
        let q = arg("--query") ?? "verne"
        for p in Providers.all {
            for query in [q, ""] {
                let t = Date()
                do {
                    let r = try await p.search(query: query, langs: ["fr", "en"], kind: nil, page: 1)
                    print("[\(p.id.rawValue)] « \(query) » : \(r.count) résultats en \(String(format: "%.1f", Date().timeIntervalSince(t))) s" + (r.first.map { " — ex. : \($0.title) / \($0.author) (\($0.kind.rawValue), \($0.files.first?.format ?? "fichiers à la demande"))" } ?? ""))
                    if let b = r.first, b.lazyFiles, let f = try? await p.files(for: b) { print("    fichiers de « \(b.title) » : \(f.map { "\($0.format) \($0.size ?? 0)" })") }
                } catch { print("[\(p.id.rawValue)] « \(query) » : ERREUR \(error.localizedDescription)") }
            }
        }
    }

    /// Envoi complet vers un dossier temporaire jouant le rôle du dossier Google Drive : recherche, téléchargement, copie, contrôle.
    static func runSend() async {
        for src in [SourceID.gutenberg, .archive, .librivox] {
            let r = (try? await Providers.provider(src).search(query: "", langs: ["fr"], kind: nil, page: 2)) ?? []
            print("[\(src.rawValue)] page 2 (fr) : \(r.count) résultats — \(r.first?.title ?? "-")")
        }
        let drive = FileManager.default.temporaryDirectory.appendingPathComponent("mkobo-test-drive-\(UUID().uuidString.prefix(6))")
        try? FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        Prefs.drivePath = drive.path
        let store = Store.shared
        var picks: [Book] = []
        for (src, q) in [(SourceID.archive, "twenty thousand leagues"), (.librivox, "")] {
            if let b = (try? await Providers.provider(src).search(query: q, langs: ["en"], kind: nil, page: 1))?.first, src != .librivox || false { picks.append(b) }
        }
        if let b = (try? await Providers.provider(.wikisource).search(query: "Le Horla", langs: ["fr"], kind: nil, page: 1))?.first { picks.append(b) }
        if let b = (try? await Providers.provider(.gutenberg).search(query: "Vingt mille lieues", langs: ["fr"], kind: nil, page: 1))?.first { picks.append(b) }
        else {   // Gutendex indisponible : livre construit à la main (teste le repli sur le miroir si gutenberg.org répond 503)
            picks.append(Book(id: "gutenberg:164", title: "Vingt mille lieues sous les mers", author: "Jules Verne", kind: .book, language: "fr", summary: "", source: .gutenberg, coverURL: nil, pageURL: nil,
                              files: [FileOption(format: "EPUB", ext: "epub", url: URL(string: "https://www.gutenberg.org/ebooks/164.epub3.images")!, size: nil)], popularity: 0))
        }
        for b in picks { store.selection[b.id] = b }
        print("Envoi de \(picks.count) titres vers \(drive.path)")
        store.send(to: .drive)
        for _ in 0..<120 { try? await Task.sleep(nanoseconds: 1_000_000_000); if !store.jobs.contains(where: { $0.stage.rawValue < Stage.done.rawValue }) { break } }
        for j in store.jobs { print("  \(j.book.title) [\(j.book.source.rawValue)] → \(j.stage) \(j.finalURL?.path.replacingOccurrences(of: drive.path, with: "…") ?? j.error ?? "")") }
        let files = (try? FileManager.default.subpathsOfDirectory(atPath: drive.path)) ?? []
        print("Contenu du dossier : \(files)")
    }

    static func capture(_ path: String) {
        let store = Store.shared
        if let q = arg("--query") { store.query = q }
        if CommandLine.arguments.contains("--view") { store.viewMode = arg("--view") ?? "grid" }
        if let s = arg("--screen"), let sc = Screen(rawValue: s) { store.screen = sc }
        if let a = arg("--appearance") { Prefs.theme = a == "light" ? "light" : "dark"; Prefs.applyTheme() }
        if let w = arg("--width").flatMap(Double.init) { Task { try? await Task.sleep(nanoseconds: 1_200_000_000); AppDelegate.shared?.window?.setContentSize(NSSize(width: w, height: arg("--height").flatMap(Double.init) ?? 760)) } }
        Task {
            for _ in 0..<40 { try? await Task.sleep(nanoseconds: 500_000_000); if !store.books.isEmpty && !store.loading { break } }
            if let n = arg("--select").flatMap(Int.init) { for b in store.books.prefix(n) { store.selection[b.id] = b } }
            if CommandLine.arguments.contains("--inspect") { store.inspected = store.visible.first }
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if let w = arg("--window") {
                if w == "settings" { AppDelegate.shared?.showSettings() } else { AppDelegate.shared?.showAbout() }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                let win = NSApp.windows.first { $0.title == (w == "settings" ? L.t("settings.title") : L.t("about.menu")) }
                if let m = AppDelegate.shared?.window, let win {
                    let scr = m.screen?.visibleFrame ?? .zero
                    print("centrage : fenêtre principale écart au centre de l'écran = (\(Int(m.frame.midX - scr.midX)), \(Int(m.frame.midY - scr.midY))) · fenêtre secondaire écart au centre de la fenêtre principale = (\(Int(win.frame.midX - m.frame.midX)), \(Int(win.frame.midY - m.frame.midY)))")
                }
                if let v = win?.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                    v.cacheDisplay(in: v.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path)); print("capture : \(path)"); exit(0)
                }
            }
            guard let view = AppDelegate.shared?.window?.contentView?.superview ?? AppDelegate.shared?.window?.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { print("capture impossible"); exit(1) }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            print("capture : \(path)")
            exit(0)
        }
    }
}
