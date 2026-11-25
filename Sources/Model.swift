// mKOBO — modèle : livres, fichiers, sources, tâches d'envoi.
import Foundation

enum Kind: String, CaseIterable, Identifiable, Sendable {
    case book, comic, audio
    var id: String { rawValue }
    var symbol: String { switch self { case .book: "book.closed"; case .comic: "square.grid.2x2"; case .audio: "headphones" } }
    var l10nKey: String { "kind.\(rawValue)" }
}

enum SourceID: String, CaseIterable, Identifiable, Sendable {
    case gutenberg, wikisource, archive, librivox
    var id: String { rawValue }
    var name: String {
        switch self {
        case .gutenberg: "Project Gutenberg"
        case .wikisource: "Wikisource"
        case .archive: "Internet Archive"
        case .librivox: "LibriVox"
        }
    }
    var kinds: [Kind] { switch self { case .gutenberg, .wikisource: [.book]; case .archive: [.book, .comic]; case .librivox: [.audio] } }
    var home: URL { switch self {
        case .gutenberg: URL(string: "https://www.gutenberg.org")!
        case .wikisource: URL(string: "https://wikisource.org")!
        case .archive: URL(string: "https://archive.org")!
        case .librivox: URL(string: "https://librivox.org")! } }
}

/// Fichier téléchargeable d'un livre.
struct FileOption: Identifiable, Hashable, Sendable {
    var id: String { url.absoluteString }
    var format: String          // EPUB, CBZ, PDF, MP3
    var ext: String             // epub, cbz, pdf, zip
    var url: URL
    var size: Int64?
    var koboReadable: Bool { ["epub", "kepub", "cbz", "cbr", "pdf"].contains(ext) }
}

struct Book: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var author: String
    var kind: Kind
    var language: String        // code à 2 lettres, ou ""
    var summary: String = ""
    var year: String = ""
    var source: SourceID
    var coverURL: URL?
    var pageURL: URL?
    var files: [FileOption] = []
    var lazyFiles = false       // la liste des fichiers se récupère à la demande (Internet Archive)
    var popularity = 0
    var duration: String = ""
    var alternatives: [Book] = []

    static func == (a: Book, b: Book) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    /// Clé de regroupement des éditions d'un même titre.
    var mergeKey: String {
        let t = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).filter { $0.isLetter || $0.isNumber }
        return kind.rawValue + ":" + String(t.prefix(32))
    }
    var formatBadge: String { files.first?.format ?? (kind == .comic ? "CBZ" : kind == .audio ? "MP3" : "EPUB") }
    var sizeText: String {
        if let s = files.first?.size, s > 0 { return ByteCountFormatter.string(fromByteCount: s, countStyle: .file) }
        return duration
    }
    /// Lisible sur la Kobo : tout sauf l'audio (la Kobo ne lit que les livres audio de sa boutique).
    var koboCompatible: Bool { kind != .audio }
}

enum Destination: String, Sendable { case kobo, drive }

enum Stage: Int, Sendable { case waiting, resolving, download, convert, copy, done, failed }

struct Job: Identifiable {
    let id = UUID()
    var book: Book
    var dest: Destination
    var stage: Stage = .waiting
    var progress: Double = 0
    var error: String?
    var finalURL: URL?
}
