// mKOBO — Flat Round Design (famille Flat Mat de Socle, plus arrondie et plus colorée) : couleurs, rayons, surfaces mates.
// Mesures de mFRAMES (Theme.swift) ; maquettes validées le 25/11/2026 (maquettes/maquettes-detail.html, arrondis 12).
import AppKit
import SwiftUI

enum M {
    static let panel: CGFloat = 250
    static let panelCompact: CGFloat = 62
    static let gap: CGFloat = 8
    static let radius: CGFloat = 12
    static let sheetRadius: CGFloat = 26
    static let topRow: CGFloat = 46
    static let rowHeight: CGFloat = 36
    static let compactWidth: CGFloat = 900
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static var spring: Animation { reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 1) }
}

enum Theme {
    static func dyn(_ dark: UInt32, _ light: UInt32) -> Color { Color(nsColor: ns(dark, light)) }
    static func ns(_ dark: UInt32, _ light: UInt32) -> NSColor {
        NSColor(name: nil) { a in
            let v = a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
        }
    }
    static let chat = dyn(0x131316, 0xf5f5f7)          // fond de fenêtre
    static let win = dyn(0x1c1c1f, 0xffffff)           // carte de contenu
    static let solid = dyn(0x232327, 0xffffff)         // surface posée
    static let solid2 = dyn(0x2c2c31, 0xffffff)        // surface flottante
    static let stage = dyn(0x0c0c0e, 0xe6e6ea)         // fond des médias
    static let fill = Color.primary.opacity(0.08)
    static let fill2 = Color.primary.opacity(0.15)
    static let sep = Color(nsColor: .separatorColor)
    static let text2 = Color(nsColor: .secondaryLabelColor)
    static let text3 = Color(nsColor: .tertiaryLabelColor)
    static let accent = Color.accentColor
    static let green = Color(nsColor: .systemGreen)
    static let red = Color(nsColor: .systemRed)
    static let orange = dyn(0xff9f0a, 0xc46a00)
    /// Couleur de marque : la lettre minuscule du nom « mKOBO » (règle « Nom de l'appli »).
    static let brandNS = ns(0xff6b4a, 0xe8473b)
    static let brand = Color(nsColor: brandNS)
    static let palette: [Color] = [Color(hex: 0x5e5ce6), Color(hex: 0xff9f0a), Color(hex: 0xff453a), Color(hex: 0x30b0c7), Color(hex: 0xbf5af2), Color(hex: 0x30d158)]
}

extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255) }
}

/// Texte où la lettre minuscule du nom « mKOBO » prend la couleur de marque (fenêtres et textes, jamais les menus déroulants).
func brandText(_ s: String) -> Text {
    var a = AttributedString(s)
    var from = a.startIndex
    while let r = a[from...].range(of: "mKOBO") {
        a[r.lowerBound ..< a.index(r.lowerBound, offsetByCharacters: 1)].foregroundColor = Theme.brand
        from = r.upperBound
    }
    return Text(a)
}

private struct SurfaceModifier: ViewModifier {
    var radius: CGFloat
    var floating: Bool
    var fill: Color
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background { floating ? AnyView(shape.fill(fill).shadow(color: .black.opacity(0.22), radius: 16, y: 12)) : AnyView(shape.fill(fill)) }
            .overlay { shape.strokeBorder(Theme.sep, lineWidth: 0.5).allowsHitTesting(false) }
    }
}

extension View {
    /// Surface mate arrondie : posée (panneau, capsules) ou flottante (feuille, barre d'envoi, bulles), avec son ombre.
    func surface(radius: CGFloat = M.radius, floating: Bool = false, fill: Color? = nil) -> some View {
        modifier(SurfaceModifier(radius: radius, floating: floating, fill: fill ?? (floating ? Theme.solid2 : Theme.solid)))
    }
}

/// Bouton en pilule (remplissage discret), principal (couleur d'accent) ou rond.
struct PillButtonStyle: ButtonStyle {
    var prominent = false
    var round = false
    var height: CGFloat = 34
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, round ? 0 : 16)
            .frame(width: round ? height : nil, height: height)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(prominent ? Theme.accent : (configuration.isPressed ? Theme.fill2 : Theme.fill)))
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Étiquette teintée (fond de la couleur à 16 %, texte en couleur pleine).
struct StatusPill: View {
    var text: String
    var color: Color
    var body: some View {
        Text(text).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(color).lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 2).background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.opacity(0.16)))
    }
}

/// Capsule de choix (filtre) : active = accent plein avec coche.
struct ChipView: View {
    var text: String
    var on: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if on { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                Text(text).font(.system(size: 12, weight: on ? .semibold : .regular))
            }
            .padding(.horizontal, 11).padding(.vertical, 5)
            .foregroundStyle(on ? Color.white : Color.primary)
            .background(Capsule().fill(on ? Theme.accent : Theme.fill))
        }.buttonStyle(.plain)
    }
}

extension Kind {
    var color: Color { switch self { case .book: Color(hex: 0x5e5ce6); case .comic: Color(hex: 0xff9f0a); case .audio: Color(hex: 0x30b0c7) } }
}
