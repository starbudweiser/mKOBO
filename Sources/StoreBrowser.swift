// mKOBO — navigateur intégré (WebKit) pour la boutique Kobo : tiroir qui glisse depuis le bas, identifiants du Trousseau, téléchargements.
// Inspiré du tiroir de CAREERDeSK. Cookies conservés d'une ouverture à l'autre ; les identifiants ne sont enregistrés qu'avec l'accord de l'utilisateur.
import AppKit
import Security
import SwiftUI
import WebKit

// MARK: Trousseau (un élément par site, propre à l'appli)

enum LoginKeychain {
    private static var service: String { Bundle.main.bundleIdentifier ?? "fr.stephan.mkobo" }
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    static func read(_ account: String) -> String? {
        var item: CFTypeRef?
        var q = query(account); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let d = item as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func write(_ account: String, _ value: String?) {
        SecItemDelete(query(account) as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var q = query(account); q[kSecValueData as String] = data
        SecItemAdd(q as CFDictionary, nil)
    }
    /// Domaine de rattachement : account.kobo.com et www.kobo.com partagent l'identifiant de kobo.com.
    static func domain(ofHost host: String) -> String {
        let parts = host.lowercased().split(separator: ".").map(String.init)
        if parts.count >= 3, ["co", "com", "org", "gov", "ac"].contains(parts[parts.count - 2]), parts.last!.count == 2 { return parts.suffix(3).joined(separator: ".") }
        return parts.suffix(2).joined(separator: ".")
    }
}

// MARK: Modèle du navigateur

@MainActor
final class KoboBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    /// Les sites voient un Safari récent : la plupart des refus viennent d'une détection du navigateur.
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Safari/605.1.15"

    let webView: WKWebView
    @Published var url = ""
    @Published var loading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var offer: Login?          // identifiant saisi sur la page, que l'utilisateur peut enregistrer
    @Published var hasSaved = false
    @Published var download: Download?
    private var files: [ObjectIdentifier: URL] = [:]
    private var popup: WKWebView?

    struct Login: Codable, Equatable { var user: String; var password: String }
    struct Download: Equatable { var name: String; var file: URL?; var failed = false }

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        // Monde de scripts à part : les scripts des sites ne voient ni le code ni l'identifiant rempli.
        config.userContentController.addUserScript(WKUserScript(source: Self.captureScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = Self.userAgent
        webView.allowsBackForwardNavigationGestures = true
        super.init()
        config.userContentController.add(LoginReceiver(self), contentWorld: .defaultClient, name: "login")
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    func load(_ address: String) {
        var text = address.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        if !text.contains("://") { text = "https://" + text }
        if let target = URL(string: text) { webView.load(URLRequest(url: target)) }
    }

    // MARK: Identifiants

    private static let captureScript = """
    (() => {
      const field = () => [...document.querySelectorAll('input[type=password]')].find(e => e.offsetParent && e.value);
      const user = (pw) => {
        const inputs = [...document.querySelectorAll('input')].filter(e => e.offsetParent && e !== pw
          && ['text','email','tel',''].includes((e.getAttribute('type') || '').toLowerCase()));
        const before = inputs.filter(e => pw.compareDocumentPosition(e) & Node.DOCUMENT_POSITION_PRECEDING);
        return (before.pop() || inputs[0] || {}).value || '';
      };
      const send = () => { const pw = field(); if (pw) webkit.messageHandlers.login.postMessage({user: user(pw), password: pw.value}); };
      document.addEventListener('submit', send, true);
      document.addEventListener('click', e => { if (e.target.closest('button, input[type=submit]')) send(); }, true);
      document.addEventListener('keydown', e => { if (e.key === 'Enter' && e.target.type === 'password') send(); }, true);
    })();
    """

    private var key: String? { webView.url?.host.map { "login:" + LoginKeychain.domain(ofHost: $0) } }
    private var saved: Login? { key.flatMap(LoginKeychain.read).flatMap { try? JSONDecoder().decode(Login.self, from: Data($0.utf8)) } }

    func save(_ login: Login) {
        guard let key, let data = try? JSONEncoder().encode(login) else { return }
        LoginKeychain.write(key, String(decoding: data, as: UTF8.self))
        offer = nil; hasSaved = true
    }

    func forget() { if let key { LoginKeychain.write(key, nil) }; hasSaved = false }

    /// Remplit le formulaire de connexion affiché ; l'utilisateur valide lui-même.
    func fill() {
        guard let login = saved, let json = try? JSONEncoder().encode(login) else { return }
        let script = """
        (() => { const c = \(String(decoding: json, as: UTF8.self));
          const set = (e, v) => { Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(e, v);
            e.dispatchEvent(new Event('input', {bubbles: true})); e.dispatchEvent(new Event('change', {bubbles: true})); };
          const pw = [...document.querySelectorAll('input[type=password]')].find(e => e.offsetParent && !e.value);
          if (!pw) return;
          const inputs = [...document.querySelectorAll('input')].filter(e => e.offsetParent && e !== pw
            && ['text','email','tel',''].includes((e.getAttribute('type') || '').toLowerCase()));
          const name = inputs.filter(e => pw.compareDocumentPosition(e) & Node.DOCUMENT_POSITION_PRECEDING).pop();
          if (name && !name.value) set(name, c.user);
          set(pw, c.password); })();
        """
        webView.evaluateJavaScript(script, in: nil, in: .defaultClient) { _ in }
    }

    fileprivate func received(_ body: Any) {
        guard let dict = body as? [String: String], let password = dict["password"], !password.isEmpty else { return }
        let login = Login(user: dict["user"] ?? "", password: password)
        if saved != login { offer = login }
    }

    private func sync() {
        url = webView.url?.absoluteString ?? url
        hasSaved = saved != nil
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }

    // MARK: Téléchargements et fenêtres ouvertes par les pages

    nonisolated func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        MainActor.assumeIsolated {
            if action.shouldPerformDownload { return decisionHandler(.download) }
            if webView === popup, let scheme = action.request.url?.scheme, ["http", "https"].contains(scheme) {
                self.webView.load(action.request); popup = nil
                return decisionHandler(.cancel)
            }
            decisionHandler(.allow)
        }
    }

    nonisolated func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
        MainActor.assumeIsolated {
            let disposition = (response.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")
            let attachment = disposition?.lowercased().hasPrefix("attachment") == true
            let hidden = webView === popup && response.response.mimeType != "text/html"
            decisionHandler(attachment || hidden || (response.isForMainFrame && !response.canShowMIMEType) ? .download : .allow)
        }
    }

    nonisolated func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { MainActor.assumeIsolated { download.delegate = self } }
    nonisolated func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { MainActor.assumeIsolated { download.delegate = self } }

    nonisolated func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping @MainActor @Sendable (URL?) -> Void) {
        MainActor.assumeIsolated {
            // Dossier temporaire d'abord : l'autorisation macOS pour Téléchargements figerait sinon toute l'appli.
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mKOBO-dl-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = suggestedFilename.isEmpty ? "telechargement" : (suggestedFilename as NSString).lastPathComponent
            let target = folder.appendingPathComponent(name)
            self.download = Download(name: name, file: nil)
            files[ObjectIdentifier(download)] = target
            completionHandler(target)
        }
    }

    nonisolated func downloadDidFinish(_ download: WKDownload) {
        MainActor.assumeIsolated {
            guard let file = files.removeValue(forKey: ObjectIdentifier(download)) else { return }
            popup = nil
            Task {
                let kept = await Task.detached { Self.keep(file) }.value ?? choose(file)
                self.download = Download(name: (kept ?? file).lastPathComponent, file: kept, failed: kept == nil)
            }
        }
    }

    nonisolated func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        MainActor.assumeIsolated {
            let file = files.removeValue(forKey: ObjectIdentifier(download))
            self.download = Download(name: file?.lastPathComponent ?? "?", file: nil, failed: true)
            popup = nil
        }
    }

    /// Range le fichier dans Téléchargements, sans écraser un fichier du même nom.
    private nonisolated static func keep(_ file: URL) -> URL? {
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let base = file.lastPathComponent as NSString
        var target = folder.appendingPathComponent(base as String), rank = 1
        while FileManager.default.fileExists(atPath: target.path) {
            rank += 1
            target = folder.appendingPathComponent(base.pathExtension.isEmpty ? "\(base) \(rank)" : "\(base.deletingPathExtension) \(rank).\(base.pathExtension)")
        }
        return (try? FileManager.default.moveItem(at: file, to: target)) == nil ? nil : target
    }

    /// Téléchargements refusé par macOS : l'utilisateur choisit où enregistrer.
    private func choose(_ file: URL) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.lastPathComponent
        guard panel.runModal() == .OK, let target = panel.url else { return nil }
        try? FileManager.default.removeItem(at: target)
        return (try? FileManager.default.moveItem(at: file, to: target)) == nil ? nil : target
    }

    nonisolated func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        MainActor.assumeIsolated {
            if let scheme = action.request.url?.scheme, ["http", "https"].contains(scheme), !action.shouldPerformDownload {
                self.webView.load(action.request)
                return nil
            }
            let window = WKWebView(frame: .zero, configuration: configuration)
            window.customUserAgent = Self.userAgent
            window.navigationDelegate = self; window.uiDelegate = self
            popup = window
            return window
        }
    }

    nonisolated func webViewDidClose(_ webView: WKWebView) { MainActor.assumeIsolated { if webView === popup { popup = nil } } }

    nonisolated func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable () -> Void) {
        MainActor.assumeIsolated { let a = NSAlert(); a.messageText = message; a.addButton(withTitle: "OK"); _ = a.runModal(); completionHandler() }
    }

    nonisolated func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (Bool) -> Void) {
        MainActor.assumeIsolated { let a = NSAlert(); a.messageText = message; a.addButton(withTitle: "OK"); a.addButton(withTitle: L.t("browser.no")); completionHandler(a.runModal() == .alertFirstButtonReturn) }
    }

    nonisolated func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void) {
        MainActor.assumeIsolated { let p = NSOpenPanel(); p.allowsMultipleSelection = parameters.allowsMultipleSelection; completionHandler(p.runModal() == .OK ? p.urls : nil) }
    }

    nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { MainActor.assumeIsolated { loading = true; sync() } }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            loading = false; sync(); fill()
            Task { try? await Task.sleep(nanoseconds: 1_500_000_000); fill() }   // formulaires construits après le chargement
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { MainActor.assumeIsolated { loading = false; sync() } }
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { MainActor.assumeIsolated { loading = false; sync() } }
}

/// Relais des messages de la page vers le navigateur (sans retenir celui-ci).
private final class LoginReceiver: NSObject, WKScriptMessageHandler {
    private weak var browser: KoboBrowser?
    init(_ browser: KoboBrowser) { self.browser = browser }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body
        Task { @MainActor in browser?.received(body) }
    }
}

// MARK: Vues

struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// Tiroir « Boutique » : glisse depuis le bas par-dessus la fenêtre, la page reste ouverte quand il est replié.
struct StoreDrawer: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var browser: KoboBrowser
    @State private var dragY: CGFloat = 0
    @State private var address = ""

    private var shape: UnevenRoundedRectangle { UnevenRoundedRectangle(topLeadingRadius: M.sheetRadius, topTrailingRadius: M.sheetRadius) }

    var body: some View {
        VStack(spacing: 0) {
            grip
            navigation
            if let offer = browser.offer {
                callout(L.t("browser.saveOffer"), [(L.t("browser.save"), true, { browser.save(offer) }), (L.t("browser.no"), false, { browser.offer = nil })])
            }
            if let d = browser.download { downloadBar(d) }
            Divider()
            WebViewHost(webView: browser.webView)
        }
        .background(Theme.win)
        .clipShape(shape)
        .overlay(shape.stroke(Color.primary.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 24, y: -6)
        .offset(y: max(0, dragY))
        .onAppear { address = browser.url }
        .onChange(of: browser.url) { _, v in address = v }
    }

    private var grip: some View {
        ZStack {
            Capsule().fill(Color.primary.opacity(0.25)).frame(width: 40, height: 4)
            HStack {
                Button { withAnimation(StoreDrawer.close) { store.showBrowser = false } } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.plain).foregroundStyle(Theme.text2).help(L.t("browser.fold"))
                Spacer()
            }.padding(.horizontal, 14)
        }
        .frame(height: 26).frame(maxWidth: .infinity).contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 8)
            .onChanged { dragY = $0.translation.height }
            .onEnded { v in
                if v.translation.height > 70 { withAnimation(StoreDrawer.close) { store.showBrowser = false } }
                withAnimation(StoreDrawer.open) { dragY = 0 }
            })
    }

    private var navigation: some View {
        HStack(spacing: 8) {
            Button { browser.webView.goBack() } label: { Image(systemName: "chevron.left") }.buttonStyle(PillButtonStyle(round: true, height: 28)).disabled(!browser.canGoBack)
            Button { browser.webView.goForward() } label: { Image(systemName: "chevron.right") }.buttonStyle(PillButtonStyle(round: true, height: 28)).disabled(!browser.canGoForward)
            Button { if browser.loading { browser.webView.stopLoading() } else { browser.webView.reload() } } label: { Image(systemName: browser.loading ? "xmark" : "arrow.clockwise") }.buttonStyle(PillButtonStyle(round: true, height: 28))
            TextField(L.t("browser.address"), text: $address).textFieldStyle(.plain).font(.system(size: 12.5))
                .padding(.horizontal, 12).frame(height: 28).background(Capsule().fill(Theme.fill))
                .onSubmit { browser.load(address) }
            if browser.hasSaved {
                Button { browser.forget() } label: { Image(systemName: "key.slash") }.buttonStyle(PillButtonStyle(round: true, height: 28)).help(L.t("browser.forget"))
            }
        }
        .padding(.horizontal, 14).frame(height: 40)
    }

    private func callout(_ text: String, _ actions: [(String, Bool, () -> Void)]) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "key").foregroundStyle(Theme.text2)
            Text(text).font(.system(size: 12)).lineLimit(2)
            Spacer(minLength: 8)
            ForEach(actions.indices, id: \.self) { i in
                Button(actions[i].0, action: actions[i].2).buttonStyle(PillButtonStyle(prominent: actions[i].1, height: 26))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6).background(Theme.fill)
    }

    @ViewBuilder private func downloadBar(_ d: KoboBrowser.Download) -> some View {
        HStack(spacing: 8) {
            Image(systemName: d.failed ? "exclamationmark.triangle" : "arrow.down.circle").foregroundStyle(d.failed ? Theme.red : Theme.text2)
            Text(d.failed ? L.t("browser.dlFailed", d.name) : d.file == nil ? L.t("browser.dlBusy", d.name) : L.t("browser.dlDone", d.name)).font(.system(size: 12)).lineLimit(1)
            Spacer(minLength: 8)
            if let f = d.file {
                if Store.sendableExts.contains(f.pathExtension.lowercased()) {
                    Button(L.t("browser.dlSend")) { store.sendLocal(f) }.buttonStyle(PillButtonStyle(prominent: true, height: 26))
                }
                Button(L.t("browser.dlReveal")) { NSWorkspace.shared.activateFileViewerSelecting([f]) }.buttonStyle(PillButtonStyle(height: 26))
            }
            Button { browser.download = nil } label: { Image(systemName: "xmark") }.buttonStyle(PillButtonStyle(round: true, height: 26))
        }
        .padding(.horizontal, 14).padding(.vertical, 6).background(Theme.fill)
    }

    static let open = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.46)
    static let close = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.34)
}

/// Languette en bas de la fenêtre quand le tiroir est replié et qu'une page est ouverte.
struct StoreDrawerTab: View {
    @ObservedObject var store = Store.shared
    var body: some View {
        Button { withAnimation(StoreDrawer.open) { store.showBrowser = true } } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.up").font(.system(size: 9, weight: .bold))
                Text(L.t("browser.tab")).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Color.white).padding(.horizontal, 14).frame(height: 20).background(Theme.accent)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10))
        }.buttonStyle(.plain).help(L.t("browser.unfold"))
    }
}
