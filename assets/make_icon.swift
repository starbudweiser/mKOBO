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
    NSColor.white.setFill()
    page(false).fill(); page(true).fill()
    // reliure : fente corail entre les deux pages
    NSColor(srgbRed: 1.0, green: 0.42, blue: 0.29, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 503, y: 320, width: 18, height: 380)).fill()
    return true
}
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
