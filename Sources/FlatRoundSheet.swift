// Flat Round Design — feuilles et bulles : les surfaces opaques de Socle, jamais la matière du système.
//
// Fichier de Socle (Socle/swift/FlatRoundSheet.swift), copié par sync_apps.sh dans les applis Flat Round qui en
// ont une copie. Ne pas le modifier dans une appli : modifier Socle, puis lancer sync_apps.sh.
//
// Pourquoi : une feuille ou une bulle SwiftUI prend par défaut une matière translucide, teintée par le fond
// d'écran (vert, orange…), et ses groupes de formulaire prennent alors une teinte qui n'est dans aucune palette.
// Les panneaux de l'appli, eux, sont mats : à côté les uns des autres, les sombres ne s'alignent plus.
//
//     .sheet(item: $x) { X().flatRoundSheet() }
//     .popover(isPresented: $p) { Y().flatRoundPopover() }
import AppKit
import SwiftUI

enum FlatRoundSurface {
    private static func dynamic(_ dark: UInt32, _ light: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let v = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
        })
    }

    /// Carte de contenu : `#1c1c1f` en sombre, `#ffffff` en clair. Le fond d'une feuille et d'une bulle.
    static let card = dynamic(0x1c1c1f, 0xffffff)
    /// Rayon d'une feuille.
    static let sheetRadius: CGFloat = 26
}

extension View {
    /// Une feuille a le fond de la carte de contenu, opaque, et le rayon 26 : ses groupes de formulaire sont alors
    /// du même gris que ceux de la fenêtre qu'elle recouvre.
    func flatRoundSheet() -> some View {
        presentationBackground(FlatRoundSurface.card)
            .presentationCornerRadius(FlatRoundSurface.sheetRadius)
    }

    /// Une bulle (popover) a le même fond opaque que la carte de contenu.
    func flatRoundPopover() -> some View {
        background(FlatRoundSurface.card)
    }
}
