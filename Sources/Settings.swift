// mKOBO — réglages et fenêtre « À propos ».
import AppKit
import SwiftUI

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
        Form {
            Section(L.t("settings.appearance")) {
                Picker(L.t("settings.theme"), selection: $theme) {
                    Text(L.t("settings.theme.auto")).tag("auto"); Text(L.t("settings.theme.light")).tag("light"); Text(L.t("settings.theme.dark")).tag("dark")
                }.pickerStyle(.segmented).onChange(of: theme) { _, _ in Prefs.applyTheme() }
                Picker(L.t("settings.icon"), selection: $iconMode) {
                    ForEach(IconMode.allCases) { Text($0.label).tag($0.rawValue) }
                }.pickerStyle(.segmented).onChange(of: iconMode) { _, v in Presence.shared.set(IconMode(rawValue: v) ?? .dock) }
            }
            Section(L.t("settings.kobo")) {
                TextField(L.t("settings.koboFolder"), text: $koboFolder)
                Toggle(L.t("settings.classify"), isOn: $classify)
                Toggle(L.t("settings.nameAuthor"), isOn: $nameAuthor)
                Toggle(L.t("settings.kepub"), isOn: $kepub).disabled(Kepubify.path == nil)
                if Kepubify.path == nil { Text(L.t("settings.kepubMissing")).font(.caption).foregroundStyle(.secondary) }
                Toggle(L.t("settings.eject"), isOn: $eject)
            }
            Section(L.t("settings.drive")) {
                LabeledContent(L.t("settings.driveFolder")) {
                    HStack {
                        Text(drivePath ?? L.t("settings.none")).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Button(L.t("settings.choose")) { AppDelegate.shared?.chooseDriveFolder { _ in drivePath = Prefs.drivePath } }
                    }
                }
                Text(L.t("settings.driveHelp")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L.t("settings.updates")) {
                Toggle(L.t("settings.autoUpdate"), isOn: $autoUpdate)
                Button(L.t("settings.updateNow")) { UpdateEngine.shared.checkNow() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 640)
        .onReceive(NotificationCenter.default.publisher(for: .driveFolderChanged)) { _ in drivePath = Prefs.drivePath }
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
        .frame(width: 330).padding(.horizontal, 28).padding(.top, 34).padding(.bottom, 26)
    }
}
