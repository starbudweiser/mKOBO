// mKOBO — bibliothèques gratuites et légales : un fournisseur par source (protocole SourceProvider).
// Gutenberg (API Gutendex), Wikisource (API MediaWiki + export EPUB), Internet Archive (API officielle), LibriVox (API officielle).
import Foundation

enum NetError: LocalizedError {
    case http(Int), format
    var errorDescription: String? { switch self { case .http(let c): "HTTP \(c)"; case .format: "format inattendu" } }
}

enum Net {
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.httpAdditionalHeaders = ["User-Agent": "mKOBO/0.1 (+https://github.com/starbudweiser/mKOBO)"]
        return URLSession(configuration: c)
    }()

    static func url(_ base: String, _ query: [(String, String)]) -> URL {
        var allowed = CharacterSet.urlQueryAllowed; allowed.remove(charactersIn: "&+=#")
        let q = query.map { "\($0.0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.1)" }.joined(separator: "&")
        var c = URLComponents(string: base)!
        if !q.isEmpty { c.percentEncodedQuery = q }
        return c.url!
    }

    static func json(_ url: URL, timeout: TimeInterval = 20) async throws -> [String: Any] {
        var req = URLRequest(url: url); req.timeoutInterval = timeout
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw NetError.http(code) }
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw NetError.format }
        return o
    }
}

protocol SourceProvider: Sendable {
    var id: SourceID { get }
    func search(query: String, langs: Set<String>, kind: Kind?, page: Int) async throws -> [Book]
    func files(for book: Book) async throws -> [FileOption]
}
extension SourceProvider { func files(for book: Book) async throws -> [FileOption] { book.files } }

enum Providers {
    static let all: [SourceProvider] = [GutenbergProvider(), WikisourceProvider(), ArchiveProvider(), LibriVoxProvider(), BEQProvider(), PepperProvider()]
    static func provider(_ id: SourceID) -> SourceProvider { all.first { $0.id == id }! }
}

/// « Hugo, Victor » ou « Verne, Jules, 1828-1905 » → « Victor Hugo », « Jules Verne » (dates de vie retirées).
func naturalName(_ s: String) -> String {
    let parts = s.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && $0.range(of: #"^[\d?]{2,4}\b|^\(?\d{3,4}\s*-"#, options: .regularExpression) == nil }
    return parts.count == 2 ? parts[1] + " " + parts[0] : parts.joined(separator: ", ")
}
/// Retire « by Jules Verne » d'un titre quand c'est l'auteur déjà affiché (titres de Standard Ebooks).
private func cleanTitle(_ title: String, author: String) -> String {
    guard let r = title.range(of: " by ", options: .backwards) else { return title }
    let tail = title[r.upperBound...].lowercased()
    let words = author.lowercased().split(separator: " ").map(String.init).filter { $0.count > 2 }
    return words.contains { tail.contains($0) } ? String(title[..<r.lowerBound]) : title
}
private func person(_ any: Any?) -> String {
    let names = (any as? [String]) ?? [(any as? String) ?? ""]
    return names.first { !$0.localizedCaseInsensitiveContains("standard ebooks") && !$0.isEmpty } ?? names.first ?? ""
}
private func str(_ any: Any?) -> String {
    if let s = any as? String { return s }
    if let a = any as? [Any] { return a.compactMap { $0 as? String }.first ?? "" }
    if let n = any as? NSNumber { return n.stringValue }
    return ""
}
private func stripHTML(_ s: String) -> String {
    s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression).replacingOccurrences(of: "&nbsp;", with: " ")
        .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
}

// MARK: Project Gutenberg (Gutendex)

struct GutenbergProvider: SourceProvider {
    let id = SourceID.gutenberg
    func search(query: String, langs: Set<String>, kind: Kind?, page: Int) async throws -> [Book] {
        if let k = kind, k != .book { return [] }
        var q: [(String, String)] = []
        if !query.isEmpty { q.append(("search", query)) }
        if !langs.isEmpty { q.append(("languages", langs.sorted().joined(separator: ","))) }
        if page > 1 { q.append(("page", String(page))) }
        let json = try await Net.json(Net.url("https://gutendex.com/books/", q), timeout: 45)   // la recherche de Gutendex est parfois lente
        return (json["results"] as? [[String: Any]] ?? []).prefix(32).compactMap { r in
            let formats = r["formats"] as? [String: String] ?? [:]
            guard let epub = formats["application/epub+zip"].flatMap(URL.init(string:)) else { return nil }
            let bid = str(r["id"])
            let authors = (r["authors"] as? [[String: Any]] ?? []).map { naturalName(str($0["name"])) }
            return Book(id: "gutenberg:\(bid)", title: str(r["title"]), author: authors.joined(separator: ", "), kind: .book,
                        language: (r["languages"] as? [String])?.first ?? "", summary: (r["summaries"] as? [String])?.first ?? "",
                        source: .gutenberg, coverURL: formats["image/jpeg"].flatMap(URL.init(string:)),
                        pageURL: URL(string: "https://www.gutenberg.org/ebooks/\(bid)"),
                        files: [FileOption(format: "EPUB", ext: "epub", url: epub, size: nil)], popularity: r["download_count"] as? Int ?? 0)
        }
    }
}

// MARK: Wikisource (recherche MediaWiki, EPUB généré par l'outil officiel ws-export)

struct WikisourceProvider: SourceProvider {
    let id = SourceID.wikisource
    func search(query: String, langs: Set<String>, kind: Kind?, page: Int) async throws -> [Book] {
        if let k = kind, k != .book { return [] }
        guard !query.isEmpty else { return [] }
        var out: [Book] = []
        for lang in ["fr", "en", "es", "it"] where langs.isEmpty || langs.contains(lang) {
            let url = Net.url("https://\(lang).wikisource.org/w/api.php", [("action", "query"), ("list", "search"), ("srsearch", query),
                              ("srnamespace", "0"), ("srlimit", "20"), ("sroffset", String((page - 1) * 20)), ("srprop", "snippet"), ("format", "json")])
            guard let json = try? await Net.json(url), let hits = (json["query"] as? [String: Any])?["search"] as? [[String: Any]] else { continue }
            for h in hits {
                let title = str(h["title"])
                guard !title.contains("/"), !title.hasPrefix("Auteur:") else { continue }
                let export = Net.url("https://ws-export.wmcloud.org/", [("format", "epub"), ("lang", lang), ("page", title)])
                out.append(Book(id: "wikisource:\(lang):\(title)", title: title, author: "", kind: .book, language: lang,
                                summary: stripHTML(str(h["snippet"])), source: .wikisource, coverURL: nil,
                                pageURL: URL(string: "https://\(lang).wikisource.org/wiki/" + (title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title)),
                                files: [FileOption(format: "EPUB", ext: "epub", url: export, size: nil)], popularity: h["wordcount"] as? Int ?? 0))
            }
        }
        return out
    }
}

// MARK: Internet Archive (livres et BD en accès libre, hors prêt numérique)

struct ArchiveProvider: SourceProvider {
    let id = SourceID.archive
    private static let langCodes = ["fr": "(fre OR French)", "en": "(eng OR English)", "es": "(spa OR Spanish)", "it": "(ita OR Italian)"]

    func search(query: String, langs: Set<String>, kind: Kind?, page: Int) async throws -> [Book] {
        if kind == .audio { return [] }
        // Livres : EPUB en accès libre. BD : seulement les titres d'avant 1931 (domaine public probable) et seulement sur une recherche,
        // jamais en accueil : l'Internet Archive héberge aussi des BD récentes déposées par des internautes.
        let comicsQuery = "(format:\"Comic Book ZIP\" AND date:[1800-01-01 TO 1930-12-31])"
        var fmt = query.isEmpty ? "format:EPUB" : "(format:EPUB OR \(comicsQuery))"
        if kind == .book { fmt = "format:EPUB" } else if kind == .comic { if query.isEmpty { return [] }; fmt = comicsQuery }
        var q = "mediatype:texts AND NOT collection:(inlibrary OR printdisabled) AND NOT access-restricted-item:true AND " + fmt
        if query.isEmpty { q += " AND collection:standardebooks" }
        let ls = langs.compactMap { Self.langCodes[$0] }
        if !ls.isEmpty { q += " AND language:(" + ls.joined(separator: " OR ") + ")" }
        let clean = query.replacingOccurrences(of: "\"", with: " ").replacingOccurrences(of: "(", with: " ").replacingOccurrences(of: ")", with: " ")
        if !clean.trimmingCharacters(in: .whitespaces).isEmpty { q += " AND (title:(\(clean)) OR creator:(\(clean)))" }
        var items: [(String, String)] = [("q", q), ("rows", "40"), ("page", String(page)), ("sort[]", "downloads desc"), ("output", "json")]
        for f in ["identifier", "title", "creator", "language", "format", "downloads", "description", "year"] { items.append(("fl[]", f)) }
        let json = try await Net.json(Net.url("https://archive.org/advancedsearch.php", items))
        if let e = json["error"] { throw NSError(domain: "archive.org", code: 1, userInfo: [NSLocalizedDescriptionKey: str(e)]) }
        return ((json["response"] as? [String: Any])?["docs"] as? [[String: Any]] ?? []).map { d in
            let ident = str(d["identifier"])
            let formats = d["format"] as? [String] ?? []
            let isComic = formats.contains("Comic Book ZIP") && !formats.contains("EPUB")
            let lang = str(d["language"]).lowercased()
            let code = ["fre": "fr", "french": "fr", "fra": "fr", "eng": "en", "english": "en", "spa": "es", "spanish": "es", "ita": "it", "italian": "it"][lang] ?? ""
            let who = naturalName(person(d["creator"]))
            return Book(id: "archive:\(ident)", title: cleanTitle(str(d["title"]), author: who), author: who, kind: isComic ? .comic : .book, language: code,
                        summary: stripHTML(str(d["description"])), year: str(d["year"]), source: .archive,
                        coverURL: URL(string: "https://archive.org/services/img/\(ident)"), pageURL: URL(string: "https://archive.org/details/\(ident)"),
                        files: [], lazyFiles: true, popularity: d["downloads"] as? Int ?? 0)
        }
    }

    func files(for book: Book) async throws -> [FileOption] {
        guard book.lazyFiles else { return book.files }
        let ident = book.id.replacingOccurrences(of: "archive:", with: "")
        let json = try await Net.json(URL(string: "https://archive.org/metadata/\(ident)")!)
        let files = json["files"] as? [[String: Any]] ?? []
        var out: [FileOption] = []
        for (format, ext) in [("EPUB", "epub"), ("Comic Book ZIP", "cbz"), ("Comic Book RAR", "cbr")] {
            if let f = files.first(where: { str($0["format"]) == format }), let name = f["name"] as? String,
               let u = URL(string: "https://archive.org/download/\(ident)/" + (name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name)) {
                out.append(FileOption(format: ext.uppercased(), ext: ext, url: u, size: Int64(str(f["size"]))))
            }
        }
        return out
    }
}

// MARK: LibriVox (livres audio gratuits lus par des bénévoles)

struct LibriVoxProvider: SourceProvider {
    let id = SourceID.librivox

    private func fetch(_ extra: [(String, String)]) async throws -> [[String: Any]] {
        let url = Net.url("https://librivox.org/api/feed/audiobooks", [("format", "json"), ("limit", "40"), ("extended", "1")] + extra)
        do { return (try await Net.json(url))["books"] as? [[String: Any]] ?? [] } catch NetError.http(404) { return [] }
    }

    func search(query: String, langs: Set<String>, kind: Kind?, page: Int) async throws -> [Book] {
        if let k = kind, k != .audio { return [] }
        var rows: [[String: Any]]
        let off: [(String, String)] = page > 1 ? [("offset", String((page - 1) * 40))] : []
        if query.isEmpty { rows = try await fetch(off) }
        else {
            async let byTitle = fetch([("title", "^" + query)] + off)
            async let byAuthor = fetch([("author", "^" + query)] + off)
            rows = try await byTitle
            let seen = Set(rows.map { str($0["id"]) })
            rows += (try await byAuthor).filter { !seen.contains(str($0["id"])) }
        }
        let names = ["fr": "french", "en": "english", "es": "spanish", "it": "italian"]
        return rows.compactMap { b in
            let lang = str(b["language"]).lowercased()
            if !langs.isEmpty, !langs.contains(where: { names[$0] == lang }) { return nil }
            guard let zip = URL(string: str(b["url_zip_file"])) else { return nil }
            let authors = (b["authors"] as? [[String: Any]] ?? []).map { (str($0["first_name"]) + " " + str($0["last_name"])).trimmingCharacters(in: .whitespaces) }
            let ia = str(b["url_iarchive"]).components(separatedBy: "/").last ?? ""
            return Book(id: "librivox:\(str(b["id"]))", title: str(b["title"]), author: authors.joined(separator: ", "), kind: .audio,
                        language: names.first { $0.value == lang }?.key ?? "", summary: stripHTML(str(b["description"])), year: str(b["copyright_year"]),
                        source: .librivox, coverURL: ia.isEmpty ? nil : URL(string: "https://archive.org/services/img/\(ia)"),
                        pageURL: URL(string: str(b["url_librivox"])), files: [FileOption(format: "MP3", ext: "zip", url: zip, size: nil)],
                        popularity: 0, duration: str(b["totaltime"]))
        }
    }
}


// MARK: Bibliothèque électronique du Québec (collection « À tous les vents », EPUB du domaine public, en français)
// Pas d'API : l'index du site (une page HTML) est lu, converti en liste et gardé une semaine dans les caches ; la recherche se fait en local.

struct BEQProvider: SourceProvider {
    let id = SourceID.beq
    private static let base = "https://beq.ebooksgratuits.com/"
    fileprivate struct Entry: Codable { var title: String, author: String, file: String }

    private static var cacheURL: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("beq-index.json") }

    private static func decodeEntities(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"")
        if let re = try? NSRegularExpression(pattern: "&#(\\d+);") {
            for m in re.matches(in: out, range: NSRange(out.startIndex..., in: out)).reversed() {
                if let r = Range(m.range, in: out), let n = Range(m.range(at: 1), in: out), let code = UInt32(out[n]), let u = Unicode.Scalar(code) { out.replaceSubrange(r, with: String(Character(u))) }
            }
        }
        return out
    }

    fileprivate static func parse(_ html: String) -> [Entry] {
        var author = ""
        var out: [Entry] = []
        let epub = try? NSRegularExpression(pattern: #"href="\.\./vents-epub/([^"]+\.epub)""#)
        for chunk in html.components(separatedBy: "<p ").dropFirst() {
            if let m = epub?.firstMatch(in: chunk, range: NSRange(chunk.startIndex..., in: chunk)), let fr = Range(m.range(at: 1), in: chunk) {
                // titre = texte qui suit la dernière image d'icône du paragraphe
                let tail = chunk.components(separatedBy: "</a>").last ?? ""
                var title = decodeEntities(stripHTML(tail)).replacingOccurrences(of: "♥", with: "").trimmingCharacters(in: CharacterSet(charactersIn: " .\u{00A0}"))
                if let r = title.range(of: ", par ") { title = String(title[..<r.lowerBound]) }
                if !title.isEmpty { out.append(Entry(title: title, author: author, file: String(chunk[fr]))) }
            } else if let b = chunk.range(of: "<b>"), let e = chunk.range(of: "</b>", range: b.upperBound..<chunk.endIndex) {
                let head = decodeEntities(stripHTML(String(chunk[b.upperBound..<e.lowerBound])))
                if let colon = head.range(of: " :") { author = naturalName(String(head[..<colon.lowerBound]).trimmingCharacters(in: .whitespaces)) }
            }
        }
        return out
    }

    private func index() async throws -> [Entry] {
        let cache = Self.cacheURL
        if let a = try? FileManager.default.attributesOfItem(atPath: cache.path), let d = a[.modificationDate] as? Date, Date().timeIntervalSince(d) < 7 * 86400,
           let data = try? Data(contentsOf: cache), let list = try? JSONDecoder().decode([Entry].self, from: data), !list.isEmpty { return list }
        let (data, resp) = try await Net.session.data(from: URL(string: Self.base + "vents/index.htm")!)
        if let code = (resp as? HTTPURLResponse)?.statusCode, code != 200 { throw NetError.http(code) }
        let html = String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
        let list = Self.parse(html)
        guard !list.isEmpty else { throw NetError.format }
        try? JSONEncoder().encode(list).write(to: cache)
        return list
    }

    func search(query: String, langs: Set<String>, kind: Kind?, page: Int) async throws -> [Book] {
        if let k = kind, k != .book { return [] }
        if !langs.isEmpty && !langs.contains("fr") { return [] }   // collection entièrement en français
        func fold(_ s: String) -> String { s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil) }
        let words = fold(query).split(separator: " ").map(String.init)
        let hits = try await index().filter { e in
            let hay = fold(e.title + " " + e.author)
            return words.allSatisfy { hay.contains($0) }
        }
        let slice = hits.dropFirst((page - 1) * 40).prefix(40)
        return slice.compactMap { e in
            guard let u = URL(string: Self.base + "vents-epub/" + (e.file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? e.file)) else { return nil }
            return Book(id: "beq:" + e.file, title: e.title, author: e.author, kind: .book, language: "fr", summary: "", source: .beq, coverURL: nil,
                        pageURL: URL(string: Self.base + "vents/index.htm"), files: [FileOption(format: "EPUB", ext: "epub", url: u, size: nil)], popularity: 0)
        }
    }
}


// MARK: Pepper&Carrot (BD de fantasy de David Revoy, licence libre CC-BY 4.0 ; pages assemblées en CBZ à l'envoi)

struct PepperProvider: SourceProvider {
    let id = SourceID.pepper
    private static let base = "https://www.peppercarrot.com/0_sources/"

    func search(query: String, langs: Set<String>, kind: Kind?, page: Int) async throws -> [Book] {
        if let k = kind, k != .comic { return [] }
        if page > 1 { return [] }
        let lang = ["fr", "en", "es", "it"].first { langs.isEmpty || langs.contains($0) } ?? "fr"
        guard let data = try? await Net.session.data(from: URL(string: Self.base + "episodes-v1.json")!).0,
              let episodes = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw NetError.format }
        func fold(_ s: String) -> String { s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil) }
        let words = fold(query).split(separator: " ").map(String.init)
        return episodes.compactMap { e in
            guard let name = e["name"] as? String, let pages = e["pages"] as? [String: String] else { return nil }
            let parts = name.split(separator: "_", maxSplits: 1).map(String.init)
            let number = Int(parts.first?.dropFirst(2) ?? "") ?? 0
            let title = "Pepper&Carrot " + String(format: "%02d", number) + " — " + (parts.count > 1 ? parts[1].replacingOccurrences(of: "-", with: " ") : name)
            guard words.allSatisfy({ fold(title + " David Revoy").contains($0) }) else { return nil }
            let numbered = pages.keys.compactMap { Int($0) }.sorted().compactMap { pages[String($0)] }
            let ordered = ([pages["title"]] + numbered.map { Optional($0) } + [pages["credits"]]).compactMap { $0 }
            let urls = ordered.compactMap { URL(string: Self.base + name + "/low-res/" + lang + "_" + $0) }
            guard let first = urls.first else { return nil }
            return Book(id: "pepper:\(name):\(lang)", title: title, author: "David Revoy", kind: .comic, language: lang,
                        summary: "BD libre de David Revoy (licence CC-BY 4.0) — peppercarrot.com", year: "", source: .pepper,
                        coverURL: pages["cover"].flatMap { URL(string: Self.base + name + "/low-res/" + $0) },
                        pageURL: URL(string: "https://www.peppercarrot.com/" + lang + "/webcomic/" + name.replacingOccurrences(of: "_", with: "__") + ".html"),
                        files: [FileOption(format: "CBZ", ext: "cbz", url: first, size: nil, parts: urls)], popularity: 1000 - number)
        }
    }
}
