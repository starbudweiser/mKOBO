// Icône de mKOBO : squircle plat corail, livre ouvert blanc ; sans ombre ni contour (règle Socle des icônes d'applis).
import AppKit
let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    let sq = NSRect(x: 100, y: 100, width: 824, height: 824)
    NSColor(srgbRed: 1.0, green: 0.42, blue: 0.29, alpha: 1).setFill()
    NSBezierPath(roundedRect: sq, xRadius: 185, yRadius: 185).fill()
    func page(_ flip: Bool) -> NSBezierPath {
        let cx: CGFloat = 512
        let x: (CGFloat) -> CGFloat = { flip ? 2 * cx - $0 : $0 }
        let p = NSBezierPath()
        p.move(to: NSPoint(x: x(cx), y: 330)); p.line(to: NSPoint(x: x(cx), y: 690))
        p.curve(to: NSPoint(x: x(235), y: 735), controlPoint1: NSPoint(x: x(440), y: 730), controlPoint2: NSPoint(x: x(320), y: 745))
        p.line(to: NSPoint(x: x(235), y: 380))
        p.curve(to: NSPoint(x: x(cx), y: 330), controlPoint1: NSPoint(x: x(320), y: 390), controlPoint2: NSPoint(x: x(440), y: 372))
        p.close(); return p
    }
    // livre remonté et réduit pour laisser la place au nom en dessous
    NSGraphicsContext.saveGraphicsState()
    let t = NSAffineTransform(); t.translateX(by: 512, yBy: 612); t.scaleX(by: 0.84, yBy: 0.84); t.translateX(by: -512, yBy: -532); t.concat()
    NSColor.white.setFill()
    page(false).fill(); page(true).fill()
    // reliure : fente corail entre les deux pages
    NSColor(srgbRed: 1.0, green: 0.42, blue: 0.29, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 503, y: 320, width: 18, height: 380)).fill()
    NSGraphicsContext.restoreGraphicsState()
    // nom de l'appli sous le livre (blanc, arrondi, gras)
    var font = NSFont.systemFont(ofSize: 172, weight: .heavy)
    if let d = font.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: 172) { font = f }
    let text = NSAttributedString(string: "mKOBO", attributes: [.font: font, .foregroundColor: NSColor.white, .kern: 2])
    let sz = text.size()
    text.draw(at: NSPoint(x: 512 - sz.width / 2, y: 236))
    return true
}
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
