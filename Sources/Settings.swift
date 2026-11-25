// mKOBO — réglages et fenêtre « À propos ».
import AppKit
import SwiftUI

/// Choix à pastilles (thème, présence) : capsule de fond, choix actif sur la carte de contenu.
struct PillPicker<T: Hashable>: View {
    @Binding var selection: T
    var options: [(T, String)]
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, title in
                let on = selection == value
                Button { selection = value } label: {
                    Text(title).font(.system(size: 12.5, weight: on ? .semibold : .regular)).lineLimit(1)
                        .padding(.horizontal, 14).frame(height: 26)
                        .background(Capsule().fill(on ? Theme.win : .clear).shadow(color: .black.opacity(on ? 0.12 : 0), radius: 1.5, y: 1))
                }.buttonStyle(.plain)
            }
        }.padding(3).background(Capsule().fill(Theme.fill))
    }
}

struct SettingsView: View {
    @AppStorage("theme") private var theme = "auto"
    @AppStorage("iconMode") private var iconMode = "dock"
    @AppStorage("koboFolder") private var koboFolder = "mKOBO"
    @AppStorage("classify") private var classify = true
    @AppStorage("nameAuthor") private var nameAuthor = true
    @AppStorage("kepub") private var kepub = true
    @AppStorage("eject") private var eject = false
    @AppStorage("autoUpdate") private var autoUpdate = true
    @State private var drivePath = Prefs.drivePath

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                group(L.t("settings.appearance")) {
                    row(L.t("settings.theme")) {
                        PillPicker(selection: $theme, options: [("auto", L.t("settings.theme.auto")), ("light", L.t("settings.theme.light")), ("dark", L.t("settings.theme.dark"))])
                            .onChange(of: theme) { _, _ in Prefs.applyTheme() }
                    }
                    row(L.t("settings.icon")) {
                        PillPicker(selection: $iconMode, options: IconMode.allCases.map { ($0.rawValue, $0.label) })
                            .onChange(of: iconMode) { _, v in Presence.shared.set(IconMode(rawValue: v) ?? .dock) }
                    }
                }
                group(L.t("settings.kobo")) {
                    row(L.t("settings.koboFolder")) {
                        TextField("mKOBO", text: $koboFolder).textFieldStyle(.plain).multilineTextAlignment(.trailing)
                            .padding(.horizontal, 12).frame(width: 190, height: 28).background(Capsule().fill(Theme.fill))
                    }
                    row(L.t("settings.classify")) { Toggle("", isOn: $classify).labelsHidden().toggleStyle(.switch) }
                    row(L.t("settings.nameAuthor")) { Toggle("", isOn: $nameAuthor).labelsHidden().toggleStyle(.switch) }
                    row(L.t("settings.kepub"), note: Kepubify.path == nil ? L.t("settings.kepubMissing") : nil) {
                        Toggle("", isOn: Kepubify.path == nil ? .constant(false) : $kepub).labelsHidden().toggleStyle(.switch).disabled(Kepubify.path == nil)
                    }
                    row(L.t("settings.eject")) { Toggle("", isOn: $eject).labelsHidden().toggleStyle(.switch) }
                }
                group(L.t("settings.drive")) {
                    row(L.t("settings.driveFolder"), note: L.t("settings.driveHelp")) {
                        HStack(spacing: 8) {
                            Text(drivePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? L.t("settings.none")).font(.system(size: 12.5)).foregroundStyle(Theme.text2)
                                .lineLimit(1).truncationMode(.middle).frame(maxWidth: 170, alignment: .trailing).help(drivePath ?? "")
                            Button(L.t("settings.choose")) { AppDelegate.shared?.chooseDriveFolder { _ in drivePath = Prefs.drivePath } }.buttonStyle(PillButtonStyle(height: 28))
                        }
                    }
                }
                group(L.t("settings.updates")) {
                    row(L.t("settings.autoUpdate")) { Toggle("", isOn: $autoUpdate).labelsHidden().toggleStyle(.switch) }
                    row(L.t("settings.updateNow")) { Button(L.t("settings.updateNow")) { UpdateEngine.shared.checkNow() }.buttonStyle(PillButtonStyle(height: 28)) }
                }
            }
            .padding(.horizontal, 22).padding(.top, 44).padding(.bottom, 22)
        }
        .frame(width: 560, height: 720)
        .background(Theme.chat)
        .onReceive(NotificationCenter.default.publisher(for: .driveFolderChanged)) { _ in drivePath = Prefs.drivePath }
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.4).foregroundStyle(Theme.text2).padding(.leading, 6)
            VStack(spacing: 0) { content() }.padding(.horizontal, 14).surface(radius: M.radius, fill: Theme.win)
        }
    }

    private func row<C: View>(_ title: String, note: String? = nil, @ViewBuilder _ control: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(title).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                control()
            }
            if let note { Text(note).font(.system(size: 11.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(.vertical, 10).frame(minHeight: 44)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.sep).frame(height: 0.5) }
    }
}

struct AboutView: View {
    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 84, height: 84)
            brandText("mKOBO").font(.system(size: 17, weight: .bold))
            Text(L.t("about.version", info["CFBundleShortVersionString"] as? String ?? "?", info["CFBundleVersion"] as? String ?? "?")).font(.system(size: 12)).foregroundStyle(.secondary)
            Text(L.t("app.tagline")).font(.system(size: 12)).multilineTextAlignment(.center).padding(.top, 6)
            Text(L.t("about.authors")).font(.system(size: 12, weight: .bold)).padding(.top, 4)
            Text(L.t("about.license")).font(.system(size: 12))
            Text(L.t("about.disclaimer")).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text(L.t("about.collection")).font(.system(size: 11)).foregroundStyle(.secondary)
            Link("♥ " + L.t("about.support"), destination: URL(string: "https://github.com/sponsors/starbudweiser")!).font(.system(size: 12, weight: .medium))
        }
        .frame(width: 330).padding(.horizontal, 28).padding(.top, 34).padding(.bottom, 26).background(Theme.chat)
    }
}
