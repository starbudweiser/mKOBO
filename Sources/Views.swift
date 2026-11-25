// mKOBO — interface Flat Round Design : barre du haut, panneau latéral, galerie (vignettes / liste), barre d'envoi, fiche, envois, liseuse.
import AppKit
import SwiftUI

struct RootView: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var dev = DeviceMonitor.shared

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.width < M.compactWidth
            VStack(spacing: M.gap) {
                TopBar(compact: compact)
                HStack(spacing: M.gap) {
                    Sidebar(compact: compact).frame(width: compact ? M.panelCompact : M.panel)
                    Group {
                        switch store.screen {
                        case .discover: DiscoverView(compact: compact)
                        case .device: DeviceView()
                        case .jobs: JobsView(inSheet: false)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .surface(radius: M.radius, fill: Theme.win)
                }
            }
            .padding([.horizontal, .bottom], M.gap)
            .padding(.top, 6)
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(Theme.chat.ignoresSafeArea())
        .background(WindowGrabber())
        .frame(minWidth: 600, minHeight: 540)
        .sheet(isPresented: $store.showJobs) { JobsView(inSheet: true).flatRoundSheet() }
        .task(id: store.searchKey) {
            try? await Task.sleep(nanoseconds: store.query.isEmpty ? 50_000_000 : 450_000_000)
            if Task.isCancelled { return }
            await store.search()
        }
    }
}

/// Donne à l'AppDelegate la fenêtre principale (barre de titre transparente, fond de l'appli).
/// Règle Socle « Lancement centré » : au lancement, centrée sur l'écran du pointeur ; la position de la session précédente n'est jamais restaurée.
struct WindowGrabber: NSViewRepresentable {
    private static var centered = false
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.styleMask.insert(.fullSizeContentView)
            w.isMovableByWindowBackground = false
            w.backgroundColor = Theme.ns(0x131316, 0xf5f5f7)
            AppDelegate.shared?.window = w
            if !Self.centered { Self.centered = true; w.socleCenter() }
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: Barre du haut

struct TopBar: View {
    var compact: Bool
    @ObservedObject var store = Store.shared
    @ObservedObject var dev = DeviceMonitor.shared

    var body: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 70, height: 1)
            brandText("mKOBO").font(.system(size: 15, weight: .bold)).fixedSize()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.text2)
                TextField(L.t("search.placeholder"), text: $store.query).textFieldStyle(.plain).font(.system(size: 13))
                if !store.query.isEmpty {
                    Button { store.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.text3) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).frame(height: 32).frame(maxWidth: 440)
            .background(Capsule().fill(Theme.fill))
            .padding(.leading, 6)
            Spacer(minLength: 8)
            koboPill
            drivePill
            Button { AppDelegate.shared?.showSettings() } label: { Image(systemName: "gearshape") }.buttonStyle(PillButtonStyle(round: true, height: 32)).help(L.t("menu.settings"))
        }
        .frame(height: 36)
    }

    private var koboPill: some View {
        HStack(spacing: 7) {
            Circle().fill(dev.device != nil ? Theme.green : Theme.text3).frame(width: 8, height: 8)
            Text(dev.device?.model ?? L.t("pill.koboOff")).font(.system(size: 12, weight: .medium)).lineLimit(1)
            if let d = dev.device, !compact {
                Text("USB · " + L.t("pill.free", ByteCountFormatter.string(fromByteCount: d.free, countStyle: .file))).font(.system(size: 11.5)).foregroundStyle(Theme.text2).lineLimit(1)
            }
        }
        .padding(.horizontal, 11).frame(height: 28).background(Capsule().fill(Theme.fill)).fixedSize()
    }

    private var drivePill: some View {
        Button { if Prefs.drivePath == nil { AppDelegate.shared?.chooseDriveFolder() } else { NSWorkspace.shared.open(URL(fileURLWithPath: Prefs.drivePath!)) } } label: {
            HStack(spacing: 7) {
                Image(systemName: "externaldrive.badge.icloud").font(.system(size: 12))
                if !compact {
                    Text(Prefs.drivePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? L.t("pill.driveNone")).font(.system(size: 12, weight: .medium)).lineLimit(1)
                }
            }
            .padding(.horizontal, 11).frame(height: 28).background(Capsule().fill(Theme.fill)).fixedSize()
        }.buttonStyle(.plain).help(Prefs.drivePath ?? L.t("pill.driveNone"))
    }
}

// MARK: Panneau latéral

struct Sidebar: View {
    var compact: Bool
    @ObservedObject var store = Store.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 2) {
                    navItem(.discover, "magnifyingglass", Theme.brand, L.t("nav.discover"), "")
                    navItem(.device, "books.vertical", Color(hex: 0x6a5af0), L.t("nav.device"), DeviceMonitor.shared.device == nil ? "" : "\(DeviceMonitor.shared.books.count)")
                    navItem(.jobs, "arrow.up.right", Color(hex: 0x2fb36a), L.t("nav.jobs"), store.jobs.isEmpty ? "" : "\(store.jobs.count)")
                }
                if !compact {
                    section(L.t("side.sources")) {
                        VStack(spacing: 0) { ForEach(SourceID.allCases) { sourceRow($0) } }.padding(6).surface(radius: M.radius, fill: Theme.solid)
                    }
                    section(L.t("side.langs")) {
                        FlowChips {
                            ChipView(text: L.t("lang.all"), on: store.langs.isEmpty) { store.langs = [] }
                            ForEach(["fr", "en", "es", "it"], id: \.self) { code in
                                ChipView(text: L.t("lang." + code), on: store.langs.contains(code)) { store.toggleLang(code) }
                            }
                        }
                    }
                    Text(L.t("side.audioNote")).font(.system(size: 11.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(compact ? 8 : 12)
        }
        .surface(radius: M.radius, fill: Theme.solid)
    }

    private func navItem(_ s: Screen, _ symbol: String, _ color: Color, _ title: String, _ badge: String) -> some View {
        Button { store.screen = s } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 24, height: 24).background(RoundedRectangle(cornerRadius: 24 * 0.27, style: .continuous).fill(color))
                if !compact {
                    Text(title).font(.system(size: 13, weight: store.screen == s ? .semibold : .medium))
                    Spacer()
                    if !badge.isEmpty { Text(badge).font(.system(size: 11.5)).foregroundStyle(Theme.text2) }
                }
            }
            .padding(.horizontal, compact ? 0 : 8).frame(maxWidth: .infinity, alignment: compact ? .center : .leading).frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(store.screen == s ? Theme.fill : .clear))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).help(title)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.4).foregroundStyle(Theme.text2)
            content()
        }
    }

    private func sourceRow(_ s: SourceID) -> some View {
        let on = store.enabled.contains(s)
        return Button { if on { store.enabled.remove(s) } else { store.enabled.insert(s) } } label: {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 4).fill(on ? Theme.accent : Theme.fill2).frame(width: 15, height: 15)
                    .overlay { if on { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white) } }
                Text(s.name).font(.system(size: 12.5)).lineLimit(1)
                Spacer(minLength: 4)
                if on, let err = store.sourceError[s] {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(Theme.orange).help(L.t("side.sourceDown", err))
                } else if on, let n = store.sourceCount[s] {
                    Text("\(n)").font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                }
            }
            .padding(.horizontal, 7).frame(height: 28).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

/// Capsules qui passent à la ligne.
struct FlowChips<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { FlowLayout(spacing: 6) { content } }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 220
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > w, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
        return CGSize(width: w, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}

// MARK: Découvrir (galerie)

struct DiscoverView: View {
    var compact: Bool
    @ObservedObject var store = Store.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                toolbar
                if store.visible.isEmpty { emptyState } else { ScrollView { gallery.padding(.horizontal, 16).padding(.top, 6).padding(.bottom, store.selection.isEmpty ? 20 : 96) } }
            }
            if !store.selection.isEmpty { SendBar().padding(14).transition(.move(edge: .bottom).combined(with: .opacity)) }
            if let b = store.inspected {
                Color.black.opacity(0.35).onTapGesture { store.inspected = nil }.transition(.opacity)
                HStack(spacing: 0) { Spacer(); Inspector(book: b).frame(width: 380) }.transition(.move(edge: .trailing))
            }
        }
        .animation(M.spring, value: store.selection.isEmpty)
        .animation(M.spring, value: store.inspected?.id)
        .clipShape(RoundedRectangle(cornerRadius: M.radius, style: .continuous))
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                kindTab(nil, L.t("kind.all"))
                ForEach(Kind.allCases) { kindTab($0, L.t($0.l10nKey)) }
            }
            .padding(3).background(Capsule().fill(Theme.fill))
            if store.loading { ProgressView().controlSize(.small) }
            Spacer()
            languageMenu
            HStack(spacing: 2) {
                viewButton("grid", "square.grid.2x2.fill")
                viewButton("list", "list.bullet")
            }
            .padding(3).background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.fill))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    /// Filtre par langue, toujours à portée (le panneau latéral se réduit dans une fenêtre étroite).
    private var languageMenu: some View {
        Menu {
            Button { store.langs = [] } label: { if store.langs.isEmpty { Label(L.t("lang.all"), systemImage: "checkmark") } else { Text(L.t("lang.all")) } }
            Divider()
            ForEach(["fr", "en", "es", "it"], id: \.self) { code in
                Button { store.toggleLang(code) } label: { if store.langs.contains(code) { Label(L.t("lang." + code), systemImage: "checkmark") } else { Text(L.t("lang." + code)) } }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe").font(.system(size: 12))
                Text(store.langs.isEmpty ? L.t("lang.all") : store.langs.sorted().map { $0.uppercased() }.joined(separator: " · ")).font(.system(size: 12.5, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.text2)
            }
            .padding(.horizontal, 12).frame(height: 30).background(Capsule().fill(Theme.fill))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().help(L.t("side.langs"))
    }

    private func kindTab(_ k: Kind?, _ title: String) -> some View {
        let on = store.typeFilter == k
        return Button { store.typeFilter = k } label: {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 12.5, weight: on ? .semibold : .regular))
                Text("\(store.count(k))").font(.system(size: 11.5)).foregroundStyle(Theme.text2)
            }
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(on ? Theme.win : .clear).shadow(color: .black.opacity(on ? 0.12 : 0), radius: 1.5, y: 1))
        }.buttonStyle(.plain)
    }

    private func viewButton(_ mode: String, _ symbol: String) -> some View {
        Button { store.viewMode = mode } label: {
            Image(systemName: symbol).font(.system(size: 12)).frame(width: 30, height: 24)
                .foregroundStyle(store.viewMode == mode ? Color.primary : Theme.text2)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(store.viewMode == mode ? Theme.win : .clear))
        }.buttonStyle(.plain).help(L.t(mode == "grid" ? "view.grid" : "view.list"))
    }

    @ViewBuilder private var gallery: some View {
        if store.viewMode == "grid" {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 148, maximum: 210), spacing: 14, alignment: .top)], alignment: .leading, spacing: 18) {
                ForEach(store.visible) { BookCard(book: $0) }
            }
        } else {
            LazyVStack(spacing: 6) { ForEach(store.visible) { BookRow(book: $0, compact: compact) } }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            if store.loading { ProgressView().controlSize(.large); Text(L.t("empty.loading")).foregroundStyle(Theme.text2) }
            else {
                Image(systemName: "books.vertical").font(.system(size: 34)).foregroundStyle(Theme.text3)
                Text(store.query.isEmpty ? L.t(store.typeFilter == .comic ? "empty.comicHint" : "empty.none") : L.t("empty.noresult", store.query)).foregroundStyle(Theme.text2)
                    .multilineTextAlignment(.center).frame(maxWidth: 380)
                ForEach(store.sourceError.sorted { $0.key.rawValue < $1.key.rawValue }, id: \.key) { s, e in
                    Text(L.t("side.sourceDown2", s.name, e)).font(.system(size: 11.5)).foregroundStyle(Theme.orange)
                }
            }
            Spacer()
        }.frame(maxWidth: .infinity)
    }
}

// MARK: Couvertures, cartes et lignes

struct CoverView: View {
    var book: Book
    var selected = false
    var checkbox = true
    var small = false

    private static let pairs: [(UInt32, UInt32)] = [(0x2b4c7e, 0x0f1f3a), (0x0f7c8c, 0x06344a), (0xf08a24, 0xb0302b), (0x7a3e9d, 0x2b1a4a), (0x3f8f5a, 0x16402a),
                                                   (0xc76b8f, 0x5b2a4a), (0x5a4632, 0x1e1610), (0x6b5fa8, 0x211b40), (0xd23c3c, 0x2c4f9e), (0x4a4a52, 0x141418)]
    private var gradient: LinearGradient {
        let h = abs(book.title.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) })
        let p = Self.pairs[h % Self.pairs.count]
        return LinearGradient(colors: [Color(hex: p.0), Color(hex: p.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: small ? 5 : M.radius, style: .continuous)
        Rectangle().fill(gradient)
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay { titleOverlay }
            .overlay {
                if let u = book.coverURL {
                    AsyncImage(url: u) { phase in
                        if case .success(let img) = phase { img.resizable().scaledToFill() } else { Color.clear }
                    }
                }
            }
            .overlay { if !small { badges } }
            .clipShape(shape)
            .overlay { if selected { shape.inset(by: -3).strokeBorder(Theme.accent, lineWidth: 3) } }
            .shadow(color: .black.opacity(small ? 0 : 0.22), radius: 8, y: 4)
    }

    private var badges: some View {
        VStack {
            HStack(alignment: .top) {
                if checkbox {
                    Circle().fill(selected ? Color.white : Color.black.opacity(0.45)).frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .overlay { if selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(.black) } }
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                }
                Spacer()
                Text(book.formatBadge).font(.system(size: 9.5, weight: .bold)).tracking(0.3).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.55)))
            }
            Spacer()
            if book.kind == .audio {
                HStack { Spacer(); Image(systemName: "headphones").font(.system(size: 12, weight: .semibold)).foregroundStyle(.black.opacity(0.75))
                    .frame(width: 26, height: 26).background(Circle().fill(.white.opacity(0.9))) }
            }
        }.padding(8)
    }

    @ViewBuilder private var titleOverlay: some View {
        if !small {
            VStack(alignment: .leading) {
                Spacer()
                Text(book.title).font(.system(size: 14, weight: .semibold, design: .serif)).foregroundStyle(.white).lineLimit(4).multilineTextAlignment(.leading)
                if !book.author.isEmpty { Text(book.author.uppercased()).font(.system(size: 9.5, weight: .medium)).tracking(0.3).foregroundStyle(.white.opacity(0.8)).lineLimit(1).padding(.top, 2) }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 30)
        }
    }
}

struct BookCard: View {
    var book: Book
    @ObservedObject var store = Store.shared

    var body: some View {
        let sel = store.selection[book.id] != nil
        VStack(alignment: .leading, spacing: 0) {
            CoverView(book: book, selected: sel).contentShape(Rectangle()).onTapGesture { store.toggle(book) }
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title).font(.system(size: 13, weight: .semibold)).lineLimit(1).help(book.title)
                Text([book.author, book.source.name].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(1)
                HStack(spacing: 5) {
                    if !book.language.isEmpty { StatusPill(text: book.language.uppercased(), color: Theme.text2) }
                    if !book.sizeText.isEmpty { StatusPill(text: book.sizeText, color: Theme.text2) }
                    compat(book)
                }.padding(.top, 3)
            }
            .padding(.top, 8).padding(.horizontal, 2).contentShape(Rectangle()).onTapGesture { store.inspected = book }
        }
    }
}

@MainActor @ViewBuilder func compat(_ b: Book, short: Bool = false) -> some View {
    if b.koboCompatible { StatusPill(text: L.t(short ? "tag.koboShort" : "tag.kobo"), color: Theme.green) }
    else { StatusPill(text: L.t(short ? "tag.driveShort" : "tag.driveOnly"), color: Theme.orange) }
}

struct BookRow: View {
    var book: Book
    var compact: Bool
    @ObservedObject var store = Store.shared

    var body: some View {
        let sel = store.selection[book.id] != nil
        HStack(spacing: 12) {
            Image(systemName: sel ? "checkmark.circle.fill" : "circle").font(.system(size: 17)).foregroundStyle(sel ? Theme.accent : Theme.text3).frame(width: 24)
            CoverView(book: book, small: true).frame(width: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(book.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text([book.author, book.source.name].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if !compact {
                HStack(spacing: 5) { Image(systemName: book.kind.symbol); Text(L.t(book.kind.l10nKey)) }.font(.system(size: 11.5)).foregroundStyle(book.kind.color).frame(width: 84, alignment: .leading)
                Text("\(book.formatBadge) \(book.sizeText.isEmpty ? "" : "· " + book.sizeText)").font(.system(size: 12)).foregroundStyle(Theme.text2).frame(width: 130, alignment: .leading)
                Text(book.language.uppercased()).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.text2).frame(width: 28)
            }
            compat(book, short: compact).frame(width: compact ? 66 : 120, alignment: .trailing)
            Button { store.inspected = book } label: { Image(systemName: "info.circle") }.buttonStyle(.plain).foregroundStyle(Theme.text2).help(L.t("row.details"))
        }
        .padding(.horizontal, 12).frame(height: 56)
        .background(RoundedRectangle(cornerRadius: M.radius, style: .continuous).fill(Theme.solid))
        .overlay { if sel { RoundedRectangle(cornerRadius: M.radius, style: .continuous).strokeBorder(Theme.accent, lineWidth: 2) } }
        .contentShape(Rectangle()).onTapGesture { store.toggle(book) }
    }
}

// MARK: Barre d'envoi

struct SendBar: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var dev = DeviceMonitor.shared
    @AppStorage("kepub") private var kepub = true

    var body: some View {
        let items = Array(store.selection.values)
        let n = items.count
        let audio = items.filter { !$0.koboCompatible }.count
        let known = items.compactMap { $0.files.first?.size }.reduce(0, +)
        let label = VStack(alignment: .leading, spacing: 1) {
            Text(L.t(n > 1 ? "send.countMany" : "send.countOne", n)).font(.system(size: 13, weight: .bold)).lineLimit(1)
            Text(audio > 0 ? L.t("send.audioNote", audio) : (known > 0 ? ByteCountFormatter.string(fromByteCount: known, countStyle: .file) + " · " : "") + L.t("send.allReadable"))
                .font(.system(size: 11.5)).foregroundStyle(Theme.text2).lineLimit(1)
        }
        let kepubSwitch = Toggle(L.t("send.kepub"), isOn: Kepubify.path == nil ? .constant(false) : $kepub).toggleStyle(.switch).controlSize(.small)
            .font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(1).fixedSize()
            .disabled(Kepubify.path == nil).help(Kepubify.path == nil ? L.t("send.kepubMissing") : L.t("send.kepubHelp"))
        let clear = Button { store.selection = [:] } label: { Image(systemName: "xmark") }.buttonStyle(PillButtonStyle(round: true)).help(L.t("send.clear"))
        let koboOff = dev.device == nil || items.allSatisfy { !$0.koboCompatible }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                label; kepubSwitch; Spacer(minLength: 6); clear
                Button { driveSend() } label: { Label(L.t("send.drive"), systemImage: "externaldrive.badge.icloud").lineLimit(1).fixedSize() }.buttonStyle(PillButtonStyle())
                Button { store.send(to: .kobo) } label: { Text(dev.device == nil ? L.t("pill.koboOff") : L.t("send.kobo") + " ▸").lineLimit(1).fixedSize() }
                    .buttonStyle(PillButtonStyle(prominent: true)).disabled(koboOff)
            }
            HStack(spacing: 10) {
                label; Spacer(minLength: 4); clear
                Button { driveSend() } label: { Image(systemName: "externaldrive.badge.icloud") }.buttonStyle(PillButtonStyle(round: true)).help(L.t("send.drive"))
                Button { store.send(to: .kobo) } label: { Text(dev.device == nil ? L.t("tag.koboOffShort") : L.t("send.koboShort") + " ▸").lineLimit(1).fixedSize() }
                    .buttonStyle(PillButtonStyle(prominent: true)).disabled(koboOff)
            }
        }
        .padding(.leading, 18).padding(.trailing, 12).frame(height: 58)
        .surface(radius: M.radius + 4, floating: true)
    }

    private func driveSend() {
        if Prefs.drivePath == nil { AppDelegate.shared?.chooseDriveFolder { if $0 { store.send(to: .drive) } } } else { store.send(to: .drive) }
    }
}

// MARK: Fiche d'un titre

struct Inspector: View {
    var book: Book
    @ObservedObject var store = Store.shared
    @State private var resolved: Book?

    var body: some View {
        let b = resolved ?? book
        let sel = store.selection[b.id] != nil
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                CoverView(book: b, checkbox: false).frame(width: 118)
                VStack(alignment: .leading, spacing: 6) {
                    Text(b.title).font(.system(size: 17, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                    if !b.author.isEmpty { Text(b.author).font(.system(size: 12.5)).foregroundStyle(Theme.text2) }
                    HStack(spacing: 5) {
                        StatusPill(text: L.t(b.kind.l10nKey), color: b.kind.color)
                        if !b.language.isEmpty { StatusPill(text: b.language.uppercased(), color: Theme.text2) }
                        if !b.year.isEmpty { StatusPill(text: b.year, color: Theme.text2) }
                    }
                    Text(L.t("fiche.source", b.source.name)).font(.system(size: 12)).foregroundStyle(Theme.text2)
                    compat(b)
                }
                Spacer(minLength: 0)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !b.summary.isEmpty { Text(b.summary).font(.system(size: 12.5)).foregroundStyle(Theme.text2).lineSpacing(2).fixedSize(horizontal: false, vertical: true) }
                    VStack(alignment: .leading, spacing: 6) {
                        header(L.t("fiche.files"))
                        if b.files.isEmpty { HStack { ProgressView().controlSize(.small); Text(L.t("empty.loading")).font(.system(size: 12)).foregroundStyle(Theme.text2) } }
                        ForEach(b.files) { f in
                            HStack {
                                Image(systemName: "doc").foregroundStyle(Theme.text2)
                                Text(f.format).font(.system(size: 12.5, weight: .semibold))
                                Spacer()
                                if let s = f.size { Text(ByteCountFormatter.string(fromByteCount: s, countStyle: .file)).font(.system(size: 12)).foregroundStyle(Theme.text2) }
                                if f.ext == "epub", Prefs.kepub, Kepubify.path != nil { StatusPill(text: L.t("fiche.kepubAuto"), color: Theme.accent) }
                            }.padding(.horizontal, 12).frame(height: 38).background(RoundedRectangle(cornerRadius: M.radius, style: .continuous).fill(Theme.fill))
                        }
                    }
                    if !b.alternatives.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            header(L.t("fiche.others"))
                            ForEach(b.alternatives) { a in
                                HStack { Text(a.source.name).font(.system(size: 12.5)); Spacer(); Text(a.formatBadge).font(.system(size: 12)).foregroundStyle(Theme.text2) }
                                    .padding(.horizontal, 12).frame(height: 34).background(RoundedRectangle(cornerRadius: M.radius, style: .continuous).fill(Theme.fill))
                                    .contentShape(Rectangle()).onTapGesture { store.inspected = a }
                            }
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                if let u = b.pageURL { Button { NSWorkspace.shared.open(u) } label: { Label(L.t("fiche.page"), systemImage: "arrow.up.right") }.buttonStyle(PillButtonStyle()) }
                Spacer()
                Button { store.toggle(b) } label: { Text(sel ? "✓ " + L.t("fiche.selected") : L.t("fiche.select")) }.buttonStyle(PillButtonStyle())
            }
        }
        .padding(18).frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.solid)
        .overlay(alignment: .topTrailing) {
            Button { store.inspected = nil } label: { Image(systemName: "xmark") }.buttonStyle(PillButtonStyle(round: true, height: 26)).padding(12)
        }
        .task(id: book.id) { resolved = nil; resolved = await store.resolveFiles(book) }
    }

    private func header(_ s: String) -> some View { Text(s.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.4).foregroundStyle(Theme.text2) }
}

// MARK: Envois

struct JobsView: View {
    var inSheet: Bool
    @ObservedObject var store = Store.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L.t("jobs.title")).font(.system(size: 17, weight: .bold))
                Spacer()
                if store.jobs.contains(where: { $0.stage == .done || $0.stage == .failed }) { Button(L.t("jobs.clear")) { store.clearFinished() }.buttonStyle(PillButtonStyle()) }
                if inSheet { Button(L.t("jobs.close")) { store.showJobs = false }.buttonStyle(PillButtonStyle(prominent: true)) }
            }
            if store.jobs.isEmpty {
                Spacer(); Text(L.t("jobs.empty")).foregroundStyle(Theme.text2).frame(maxWidth: .infinity); Spacer()
            } else {
                ScrollView { VStack(spacing: 6) { ForEach(store.jobs) { JobRow(job: $0) } } }
            }
        }
        .padding(inSheet ? 22 : 18)
        .frame(width: inSheet ? 560 : nil, height: inSheet ? 440 : nil)
    }
}

struct JobRow: View {
    var job: Job
    @ObservedObject var store = Store.shared
    private let steps: [(Stage, String)] = [(.download, "jobs.step.download"), (.convert, "jobs.step.convert"), (.copy, "jobs.step.copy")]

    var body: some View {
        HStack(spacing: 12) {
            CoverView(book: job.book, small: true).frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(job.book.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    StatusPill(text: job.dest == .kobo ? "Kobo" : "Drive", color: job.dest == .kobo ? Theme.accent : Theme.orange)
                }
                if job.stage == .failed {
                    Text(job.error ?? "").font(.system(size: 11.5)).foregroundStyle(Theme.red).lineLimit(2)
                } else {
                    HStack(spacing: 6) {
                        ForEach(steps, id: \.0.rawValue) { st, key in
                            let done = job.stage.rawValue > st.rawValue, cur = job.stage == st
                            Text((done ? "✓ " : "") + L.t(key)).font(.system(size: 10.5, weight: cur ? .semibold : .regular))
                                .foregroundStyle(done ? Theme.green : (cur ? Theme.accent : Theme.text2))
                            if st != .copy { Text("›").font(.system(size: 10.5)).foregroundStyle(Theme.text3) }
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            switch job.stage {
            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green).font(.system(size: 18))
            case .failed: Button(L.t("jobs.retry")) { store.retry(job.id) }.buttonStyle(PillButtonStyle(height: 28))
            case .waiting: Text(L.t("jobs.waiting")).font(.system(size: 11.5)).foregroundStyle(Theme.text2)
            default: ProgressView(value: job.progress).frame(width: 110)
            }
        }
        .padding(.horizontal, 12).frame(height: 58)
        .background(RoundedRectangle(cornerRadius: M.radius, style: .continuous).fill(Theme.fill))
    }
}

// MARK: Ma liseuse

struct DeviceView: View {
    @ObservedObject var dev = DeviceMonitor.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let d = dev.device { deviceCard(d) } else { disconnected.frame(minHeight: 360) }
                if dev.device != nil {
                    fileList(L.t("device.onKobo"), dev.books)
                }
                if Prefs.drivePath != nil { fileList(L.t("device.onDrive"), dev.driveFiles) }
            }.padding(18)
        }
    }

    private func deviceCard(_ d: KoboDevice) -> some View {
        HStack(spacing: 18) {
            RoundedRectangle(cornerRadius: 9).fill(Theme.stage).frame(width: 58, height: 80)
                .overlay(RoundedRectangle(cornerRadius: 3).fill(LinearGradient(colors: [Color(hex: 0xd8cfc0), Color(hex: 0xb9c7d6)], startPoint: .topLeading, endPoint: .bottomTrailing)).padding(.init(top: 6, leading: 6, bottom: 14, trailing: 6)))
            VStack(alignment: .leading, spacing: 4) {
                Text(d.model).font(.system(size: 17, weight: .bold))
                Text(L.t("device.line", d.firmware.isEmpty ? "—" : d.firmware, dev.books.count)).font(.system(size: 12)).foregroundStyle(Theme.text2)
                ProgressView(value: Double(d.total - d.free), total: Double(max(d.total, 1))).tint(Theme.accent).padding(.top, 6)
                Text(L.t("device.space", ByteCountFormatter.string(fromByteCount: d.free, countStyle: .file), ByteCountFormatter.string(fromByteCount: d.total, countStyle: .file)))
                    .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
            }
            Button { dev.eject() } label: { Label(L.t("device.eject"), systemImage: "eject") }.buttonStyle(PillButtonStyle(prominent: true))
        }
        .padding(16).surface(radius: M.radius + 4, fill: Theme.solid)
    }

    private var disconnected: some View {
        VStack(spacing: 10) {
            Image(systemName: "cable.connector").font(.system(size: 34)).foregroundStyle(Theme.text3)
            Text(L.t("device.plug")).font(.system(size: 17, weight: .bold))
            Text(L.t("device.plugHelp")).font(.system(size: 12)).foregroundStyle(Theme.text2).multilineTextAlignment(.center).frame(maxWidth: 380)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.vertical, 30)
    }

    private func fileList(_ title: String, _ files: [DeviceBook]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(title.uppercased()) · \(files.count)").font(.system(size: 10.5, weight: .semibold)).tracking(0.4).foregroundStyle(Theme.text2)
            VStack(spacing: 0) {
                ForEach(files.prefix(60)) { f in
                    HStack {
                        Image(systemName: "doc.text").foregroundStyle(Theme.text2)
                        Text(f.name).font(.system(size: 12.5)).lineLimit(1)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: f.size, countStyle: .file)).font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                    }.padding(.horizontal, 12).frame(height: 34)
                }
                if files.isEmpty { Text(L.t("device.empty")).font(.system(size: 12)).foregroundStyle(Theme.text2).padding(12) }
            }.surface(radius: M.radius, fill: Theme.solid)
        }
    }
}
