// mKOBO — envoi : téléchargement, conversion KEPUB (kepubify s'il est présent), dépôt sur la Kobo ou dans le dossier Google Drive.
import AppKit
import Foundation

enum JobError: LocalizedError {
    case noFile, noKobo, noDrive, badFile, copy(String), kepub(String)
    var errorDescription: String? {
        switch self {
        case .noFile: L.t("err.nofile")
        case .noKobo: L.t("err.nokobo")
        case .noDrive: L.t("err.nodrive")
        case .badFile: L.t("err.badfile")
        case .copy(let s): L.t("err.copy", s)
        case .kepub(let s): L.t("err.kepub", s)
        }
    }
}

/// Téléchargements avec progression (URLSession à délégué).
final class Downloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = Downloader()
    private var session: URLSession!
    private let lock = NSLock()
    private var handlers: [Int: (progress: (Double) -> Void, cont: CheckedContinuation<URL, Error>, ext: String)] = [:]

    override init() {
        super.init()
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 90
        c.timeoutIntervalForResource = 3600
        c.httpAdditionalHeaders = ["User-Agent": "mKOBO/0.1 (+https://github.com/starbudweiser/mKOBO)"]
        session = URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }

    /// Project Gutenberg : si gutenberg.org est en maintenance (503), repli sur le miroir officiel pglaf.org.
    static func gutenbergMirror(_ url: URL) -> URL? {
        guard url.host?.hasSuffix("gutenberg.org") == true else { return nil }
        let id = url.path.range(of: #"(?<=ebooks/)\d+|(?<=epub/)\d+"#, options: .regularExpression).map { String(url.path[$0]) }
        guard let id, !id.isEmpty, id.allSatisfy(\.isNumber) else { return nil }
        return URL(string: "https://gutenberg.pglaf.org/cache/epub/\(id)/pg\(id)-images.epub")
    }

    func download(_ url: URL, ext: String, progress: @escaping (Double) -> Void) async throws -> URL {
        do { return try await fetch(url, ext: ext, progress: progress) }
        catch {
            guard let mirror = Self.gutenbergMirror(url) else { throw error }
            return try await fetch(mirror, ext: ext, progress: progress)
        }
    }

    private func fetch(_ url: URL, ext: String, progress: @escaping (Double) -> Void) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let t = session.downloadTask(with: url)
            lock.lock(); handlers[t.taskIdentifier] = (progress, cont, ext); lock.unlock()
            t.resume()
        }
    }

    private func take(_ id: Int) -> (progress: (Double) -> Void, cont: CheckedContinuation<URL, Error>, ext: String)? {
        lock.lock(); defer { lock.unlock() }
        return handlers.removeValue(forKey: id)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        lock.lock(); let h = handlers[downloadTask.taskIdentifier]; lock.unlock()
        h?.progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let h = take(downloadTask.taskIdentifier) else { return }
        let code = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { h.cont.resume(throwing: NetError.http(code)); return }
        do {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mKOBO", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(UUID().uuidString + "." + h.ext)
            try FileManager.default.moveItem(at: location, to: dest)
            h.cont.resume(returning: dest)
        } catch { h.cont.resume(throwing: error) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let h = take(task.taskIdentifier) else { return }
        h.cont.resume(throwing: error)
    }
}

enum Kepubify {
    /// Outil de conversion EPUB → KEPUB : dans l'appli, ou installé (Homebrew).
    static var path: String? {
        let candidates = [Bundle.main.resourcePath.map { $0 + "/kepubify" }, "/opt/homebrew/bin/kepubify", "/usr/local/bin/kepubify"].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func convert(_ input: URL) async throws -> URL {
        guard let tool = path else { throw JobError.kepub("kepubify") }
        return try await Task.detached {
            let out = FileManager.default.temporaryDirectory.appendingPathComponent("mKOBO/k-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            let p = Process(), pipe = Pipe()
            p.executableURL = URL(fileURLWithPath: tool); p.arguments = ["-o", out.path, input.path]
            p.standardOutput = pipe; p.standardError = pipe
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            guard p.terminationStatus == 0,
                  let f = (try? FileManager.default.contentsOfDirectory(at: out, includingPropertiesForKeys: nil))?.first(where: { $0.lastPathComponent.hasSuffix(".kepub.epub") })
            else { throw JobError.kepub(String(decoding: data, as: UTF8.self).prefix(160).description) }
            return f
        }.value
    }
}

enum Naming {
    static func clean(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
        let t = s.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".")))
        return String(t.prefix(110))
    }
    static func fileName(_ b: Book, ext: String) -> String {
        let base = Prefs.nameWithAuthor && !b.author.isEmpty ? "\(b.author) - \(b.title)" : b.title
        return clean(base) + "." + ext
    }
}

extension Store {
    /// Choix du fichier à envoyer : EPUB d'abord, puis BD, puis PDF ; l'audio n'a qu'un fichier.
    static func pick(_ files: [FileOption], for dest: Destination) -> FileOption? {
        for ext in ["epub", "cbz", "cbr", "pdf", "zip"] { if let f = files.first(where: { $0.ext == ext }), dest == .drive || f.koboReadable { return f } }
        return dest == .drive ? files.first : nil
    }

    func destinationFolder(_ dest: Destination, _ book: Book) throws -> URL {
        var root: URL
        switch dest {
        case .kobo:
            guard let d = DeviceMonitor.shared.device else { throw JobError.noKobo }
            root = d.volume.appendingPathComponent(Naming.clean(Prefs.koboFolder.isEmpty ? "mKOBO" : Prefs.koboFolder), isDirectory: true)
        case .drive:
            guard let p = Prefs.drivePath, FileManager.default.fileExists(atPath: p) else { throw JobError.noDrive }
            root = URL(fileURLWithPath: p, isDirectory: true)
        }
        if Prefs.classifyByAuthor { root.appendPathComponent(Naming.clean(book.author.isEmpty ? L.t("job.unknownAuthor") : book.author), isDirectory: true) }
        do { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) } catch { throw JobError.copy(error.localizedDescription) }
        return root
    }

    func send(to dest: Destination) {
        let picked = selection.values.sorted { $0.title < $1.title }
        let eligible = picked.filter { dest == .drive || $0.koboCompatible }
        guard !eligible.isEmpty else { return }
        jobs.removeAll { $0.stage == .done || $0.stage == .failed }
        jobs += eligible.map { Job(book: $0, dest: dest) }
        selection = [:]
        showJobs = true
        startRunner()
    }

    func retry(_ id: UUID) { update(id) { $0.stage = .waiting; $0.error = nil; $0.progress = 0 }; startRunner() }
    func clearFinished() { jobs.removeAll { $0.stage == .done || $0.stage == .failed } }

    private func update(_ id: UUID, _ change: (inout Job) -> Void) {
        if let i = jobs.firstIndex(where: { $0.id == id }) { change(&jobs[i]) }
    }

    private func startRunner() {
        guard runner == nil else { return }
        runner = Task {
            while let job = jobs.first(where: { $0.stage == .waiting }) { await run(job) }
            runner = nil
        }
    }

    /// BD en images : télécharge chaque page puis les range dans un CBZ (001.jpg, 002.jpg…).
    private func buildComic(_ pages: [URL], id: UUID, temps: inout [URL]) async throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mKOBO-cbz-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        temps.append(dir)
        for (i, u) in pages.enumerated() {
            let tmp = try await Downloader.shared.download(u, ext: "jpg") { _ in }
            try FileManager.default.moveItem(at: tmp, to: dir.appendingPathComponent(String(format: "%03d.", i + 1) + (u.pathExtension.isEmpty ? "jpg" : u.pathExtension)))
            update(id) { $0.progress = Double(i + 1) / Double(pages.count) }
        }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".cbz")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        p.currentDirectoryURL = dir
        p.arguments = ["-q", "-0", "-r", out.path, "."]
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw JobError.badFile }
        return out
    }

    private func run(_ job: Job) async {
        let id = job.id
        update(id) { $0.stage = .resolving }
        var temps: [URL] = []
        defer { temps.forEach { try? FileManager.default.removeItem(at: $0) } }
        do {
            var files = job.book.files
            if job.book.lazyFiles { files = try await Providers.provider(job.book.source).files(for: job.book) }
            guard let opt = Self.pick(files, for: job.dest) else { throw JobError.noFile }
            update(id) { $0.stage = .download }
            var file: URL
            if opt.url.isFileURL {   // fichier déjà téléchargé depuis la boutique
                let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + opt.ext)
                try FileManager.default.copyItem(at: opt.url, to: copy)
                file = copy
            } else if opt.parts.isEmpty {
                file = try await Downloader.shared.download(opt.url, ext: opt.ext) { p in Task { @MainActor in self.update(id) { $0.progress = p } } }
            } else {
                file = try await buildComic(opt.parts, id: id, temps: &temps)
            }
            temps.append(file)
            if opt.ext == "epub" || opt.ext == "cbz" || opt.ext == "zip" || opt.ext == "cbr" {
                let head = try FileHandle(forReadingFrom: file).read(upToCount: 4) ?? Data()
                if opt.ext != "cbr", head.prefix(2) != Data("PK".utf8) { throw JobError.badFile }
            }
            var ext = opt.ext
            if job.dest == .kobo, opt.ext == "epub", Prefs.kepub, Kepubify.path != nil {
                update(id) { $0.stage = .convert; $0.progress = 0 }
                file = try await Kepubify.convert(file); temps.append(file); ext = "kepub.epub"
            }
            update(id) { $0.stage = .copy; $0.progress = 0.5 }
            let folder = try destinationFolder(job.dest, job.book)
            let target = folder.appendingPathComponent(Naming.fileName(job.book, ext: ext))
            do {
                if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
                try FileManager.default.copyItem(at: file, to: target)
            } catch { throw JobError.copy(error.localizedDescription) }
            let a = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
            let b = (try? FileManager.default.attributesOfItem(atPath: target.path)[.size] as? Int64) ?? -1
            guard a == b else { throw JobError.copy(L.t("err.size")) }
            update(id) { $0.stage = .done; $0.progress = 1; $0.finalURL = target }
        } catch {
            update(id) { $0.stage = .failed; $0.error = error.localizedDescription }
        }
        let koboLeft = jobs.contains { $0.dest == .kobo && $0.stage.rawValue < Stage.done.rawValue }
        if job.dest == .kobo, Prefs.ejectAfter, !koboLeft, jobs.contains(where: { $0.dest == .kobo && $0.stage == .done }) { DeviceMonitor.shared.eject() }
        DeviceMonitor.shared.refresh()
    }
}
