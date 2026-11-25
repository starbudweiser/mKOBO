// mKOBO — état de l'appli : recherche dans les sources, sélection, envois.
import Foundation
import SwiftUI

enum Screen: String { case discover, device, jobs }

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var query = ""
    @Published private(set) var books: [Book] = []
    @Published private(set) var loading = false
    @Published private(set) var sourceError: [SourceID: String] = [:]
    @Published private(set) var sourceCount: [SourceID: Int] = [:]
    @Published var enabled: Set<SourceID> = Prefs.sources { didSet { Prefs.sources = enabled } }
    @Published var langs: Set<String> = Prefs.langs { didSet { Prefs.langs = langs } }
    @Published var typeFilter: Kind?
    @Published var viewMode: String = Prefs.viewMode { didSet { Prefs.viewMode = viewMode } }
    @Published var selection: [String: Book] = [:]
    @Published var inspected: Book?
    @Published var screen: Screen = .discover
    @Published var jobs: [Job] = []
    @Published var showJobs = false
    var runner: Task<Void, Never>?

    private var raw: [SourceID: [Book]] = [:]

    /// Clé qui déclenche une nouvelle recherche (dans la vue : `.task(id:)`).
    var searchKey: String { query + "|" + enabled.map(\.rawValue).sorted().joined() + "|" + langs.sorted().joined() }

    /// Résultats retenus par le filtre de langue (aucune langue cochée = toutes ; un titre sans langue connue reste visible).
    private var inLangs: [Book] { langs.isEmpty ? books : books.filter { $0.language.isEmpty || langs.contains($0.language) } }
    var visible: [Book] { typeFilter.map { k in inLangs.filter { $0.kind == k } } ?? inLangs }
    func count(_ k: Kind?) -> Int { k.map { k in inLangs.filter { $0.kind == k }.count } ?? inLangs.count }
    func toggleLang(_ code: String) { if langs.contains(code) { langs.remove(code) } else { langs.insert(code) } }

    func search() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        loading = true
        sourceError = [:]; raw = [:]; sourceCount = [:]
        let langs = self.langs
        let providers = Providers.all.filter { enabled.contains($0.id) }
        await withTaskGroup(of: (SourceID, [Book]?, String?).self) { group in
            for p in providers {
                group.addTask {
                    do { return (p.id, try await p.search(query: q, langs: langs, kind: nil), nil) }
                    catch { return (p.id, nil, error is CancellationError ? nil : error.localizedDescription) }
                }
            }
            for await (id, result, err) in group {
                if Task.isCancelled { group.cancelAll(); return }
                if let result { raw[id] = result; sourceCount[id] = result.count }
                if let err { sourceError[id] = err }
                rebuild()
            }
        }
        if !Task.isCancelled { loading = false }
    }

    /// Fusionne les sources : un titre trouvé ailleurs devient une « autre édition », les sources alternent pour que chacune apparaisse.
    private func rebuild() {
        let lists = SourceID.allCases.compactMap { raw[$0] }.map { $0.sorted { $0.popularity > $1.popularity } }
        var ordered: [Book] = []
        var i = 0
        while ordered.count < lists.reduce(0, { $0 + $1.count }) { for l in lists where i < l.count { ordered.append(l[i]) }; i += 1 }
        var seen: [String: Int] = [:]
        var out: [Book] = []
        for b in ordered {
            if let at = seen[b.mergeKey] { out[at].alternatives.append(b) } else { seen[b.mergeKey] = out.count; out.append(b) }
        }
        books = out
    }

    func toggle(_ b: Book) { if selection[b.id] != nil { selection[b.id] = nil } else { selection[b.id] = b } }

    /// Récupère la liste des fichiers d'un titre de l'Internet Archive (taille, formats) pour la fiche.
    func resolveFiles(_ b: Book) async -> Book {
        guard b.lazyFiles, let files = try? await Providers.provider(b.source).files(for: b) else { return b }
        var nb = b; nb.files = files; nb.lazyFiles = false
        if let i = books.firstIndex(where: { $0.id == b.id }) { books[i].files = files; books[i].lazyFiles = false }
        if selection[b.id] != nil { selection[b.id] = nb }
        return nb
    }
}
