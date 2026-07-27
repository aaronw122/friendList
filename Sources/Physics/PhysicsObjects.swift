import SpriteKit
import AppKit

// MARK: - NSColor hex helper

private extension NSColor {
    convenience init(hexString: String, alpha: CGFloat = 1) {
        let s = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let b = CGFloat(rgb & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
}

// MARK: - Object spec

/// A single stage object: its physics footprint plus a factory for its
/// vector-ish visual (an `SKNode` whose children are centered on the origin).
struct ObjectSpec {
    let name: String
    let size: CGSize
    /// true → circular collision body; false → rectangular body.
    let round: Bool
    let makeVisual: () -> SKNode
    /// true → on each drop, a 67% chance the object locks upright (falls level,
    /// no spin) so it lands readable; the other 33% it tumbles like the rest.
    /// Used for the iMessage bubble ("you need to hear this").
    var uprightBias: Bool = false
}

/// Builds the 14 stage objects and their SpriteKit bodies.
/// Visuals are composed from `SKShapeNode`/`SKLabelNode` children — approximations
/// of the CSS prototype, matching size, shape category, and dominant color.
enum PhysicsObjects {

    // Body tuning (README engine settings)
    static let restitution: CGFloat = 0.52
    static let friction: CGFloat = 0.35
    static let linearDamping: CGFloat = 0.02   // ~ air friction 0.008 feel

    /// Stable spawn order — also the order `popEveryOther` walks.
    static var all: [ObjectSpec] {
        [
            ObjectSpec(name: "vinyl",     size: CGSize(width: 98, height: 98),  round: true,  makeVisual: vinyl),
            ObjectSpec(name: "cd",        size: CGSize(width: 80, height: 80),  round: true,  makeVisual: cd),
            ObjectSpec(name: "cassette",  size: CGSize(width: 118, height: 74), round: false, makeVisual: cassette),
            ObjectSpec(name: "headphones",size: CGSize(width: 92, height: 80),  round: false, makeVisual: headphones),
            ObjectSpec(name: "chain",     size: CGSize(width: 104, height: 24), round: false, makeVisual: chain),
            ObjectSpec(name: "smiley",    size: CGSize(width: 62, height: 62),  round: true,  makeVisual: smiley),
            ObjectSpec(name: "note",      size: CGSize(width: 48, height: 62),  round: false, makeVisual: note),
            ObjectSpec(name: "star",      size: CGSize(width: 58, height: 58),  round: false, makeVisual: star),
            ObjectSpec(name: "heart",     size: CGSize(width: 52, height: 46),  round: false, makeVisual: heart),
            ObjectSpec(name: "pick",      size: CGSize(width: 50, height: 56),  round: false, makeVisual: pick),
            ObjectSpec(name: "ticket",    size: CGSize(width: 118, height: 56), round: false, makeVisual: ticket),
            ObjectSpec(name: "linkcard",  size: CGSize(width: 136, height: 60), round: false, makeVisual: linkCard),
            ObjectSpec(name: "imessage",  size: CGSize(width: 196, height: 46), round: false, makeVisual: imessage, uprightBias: true),
            ObjectSpec(name: "jerry",     size: CGSize(width: 96, height: 96),  round: true,  makeVisual: jerry),
        ]
    }

    // MARK: Node factory

    /// Wraps a spec's visual in a container carrying the physics body.
    static func makeNode(_ spec: ObjectSpec) -> SKNode {
        let container = SKNode()
        container.name = spec.name
        container.addChild(spec.makeVisual())

        let body: SKPhysicsBody
        if spec.round {
            body = SKPhysicsBody(circleOfRadius: spec.size.width / 2)
        } else {
            body = SKPhysicsBody(rectangleOf: spec.size)
        }
        body.restitution = restitution
        body.friction = friction
        body.linearDamping = linearDamping
        body.allowsRotation = true   // finalized per-drop in StageScene.drop
        container.physicsBody = body
        return container
    }

    // MARK: Shape helpers

    private static func roundedRect(_ size: CGSize, radius: CGFloat, color: NSColor) -> SKShapeNode {
        let n = SKShapeNode(rectOf: size, cornerRadius: radius)
        n.fillColor = color
        n.strokeColor = .clear
        n.lineWidth = 0
        return n
    }

    private static func disc(_ r: CGFloat, color: NSColor, stroke: NSColor = .clear, lineW: CGFloat = 0) -> SKShapeNode {
        let n = SKShapeNode(circleOfRadius: r)
        n.fillColor = color
        n.strokeColor = stroke
        n.lineWidth = lineW
        return n
    }

    private static func shape(_ path: CGPath, fill: NSColor, stroke: NSColor = .clear, lineW: CGFloat = 0) -> SKShapeNode {
        let n = SKShapeNode(path: path)
        n.fillColor = fill
        n.strokeColor = stroke
        n.lineWidth = lineW
        n.lineCap = .round
        n.lineJoin = .round
        return n
    }

    // MARK: Object builders

    private static func vinyl() -> SKNode {
        let g = SKNode()
        g.addChild(disc(49, color: NSColor(hexString: "211E28")))
        g.addChild(disc(40, color: .clear, stroke: NSColor(white: 1, alpha: 0.06), lineW: 1))
        g.addChild(disc(30, color: .clear, stroke: NSColor(white: 1, alpha: 0.06), lineW: 1))
        g.addChild(disc(16, color: NSColor(hexString: "9B85F2")))
        g.addChild(disc(4, color: .white))
        return g
    }

    private static func cd() -> SKNode {
        let g = SKNode()
        g.addChild(disc(40, color: NSColor(hexString: "DFE4EE")))
        // iridescent hint: faint tinted arcs
        g.addChild(disc(34, color: .clear, stroke: NSColor(hexString: "C6B6F0", alpha: 0.5), lineW: 4))
        g.addChild(disc(26, color: .clear, stroke: NSColor(hexString: "B6D6E8", alpha: 0.5), lineW: 4))
        g.addChild(disc(12, color: .white))
        g.addChild(disc(5, color: NSColor(hexString: "CBD2DE")))
        return g
    }

    private static func cassette() -> SKNode {
        let g = SKNode()
        g.addChild(roundedRect(CGSize(width: 118, height: 74), radius: 10, color: NSColor(hexString: "EFB63F")))
        g.addChild(roundedRect(CGSize(width: 78, height: 32), radius: 6, color: NSColor(hexString: "F3ECD8")))
        let spoolL = disc(9, color: NSColor(hexString: "3B352E")); spoolL.position = CGPoint(x: -20, y: 4)
        let spoolR = disc(9, color: NSColor(hexString: "3B352E")); spoolR.position = CGPoint(x: 20, y: 4)
        g.addChild(spoolL); g.addChild(spoolR)
        let base = roundedRect(CGSize(width: 118, height: 14), radius: 4, color: NSColor(hexString: "D89E2F"))
        base.position = CGPoint(x: 0, y: -30)
        g.addChild(base)
        return g
    }

    private static func headphones() -> SKNode {
        let g = SKNode()
        let arc = CGMutablePath()
        arc.addArc(center: CGPoint(x: 0, y: -8), radius: 34,
                   startAngle: .pi * 0.08, endAngle: .pi * 0.92, clockwise: false)
        g.addChild(shape(arc, fill: .clear, stroke: NSColor(hexString: "4B4550"), lineW: 13))
        let cupL = roundedRect(CGSize(width: 20, height: 30), radius: 8, color: NSColor(hexString: "5B5466"))
        cupL.position = CGPoint(x: -32, y: -22)
        let cupR = roundedRect(CGSize(width: 20, height: 30), radius: 8, color: NSColor(hexString: "5B5466"))
        cupR.position = CGPoint(x: 32, y: -22)
        g.addChild(cupL); g.addChild(cupR)
        return g
    }

    private static func chain() -> SKNode {
        let g = SKNode()
        let golds = [NSColor(hexString: "E9BE4A"), NSColor(hexString: "F0CB63")]
        for i in 0..<4 {
            let ring = disc(10, color: .clear, stroke: golds[i % 2], lineW: 5)
            ring.position = CGPoint(x: -33 + CGFloat(i) * 22, y: 0)
            g.addChild(ring)
        }
        return g
    }

    private static func smiley() -> SKNode {
        let g = SKNode()
        g.addChild(disc(31, color: NSColor(hexString: "F4A0C0")))
        let ink = NSColor(hexString: "5A2C42")
        let eyeL = disc(3, color: ink); eyeL.position = CGPoint(x: -9, y: 7)
        let eyeR = disc(3, color: ink); eyeR.position = CGPoint(x: 9, y: 7)
        g.addChild(eyeL); g.addChild(eyeR)
        let smile = CGMutablePath()
        smile.addArc(center: CGPoint(x: 0, y: -2), radius: 12,
                     startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: false)
        g.addChild(shape(smile, fill: .clear, stroke: ink, lineW: 3))
        return g
    }

    private static func note() -> SKNode {
        // Eighth note: tilted oval head, stem off the head's right edge, curved flag.
        let g = SKNode()
        let ink = NSColor(hexString: "37333C")

        // Stem — rises from the right side of the head.
        let stem = roundedRect(CGSize(width: 4.5, height: 48), radius: 2.2, color: ink)
        stem.position = CGPoint(x: 4, y: 4)
        g.addChild(stem)

        // Flag — curved hook off the top of the stem.
        let flag = CGMutablePath()
        flag.move(to: CGPoint(x: 6, y: 28))
        flag.addQuadCurve(to: CGPoint(x: 18, y: 2), control: CGPoint(x: 25, y: 23))
        flag.addQuadCurve(to: CGPoint(x: 6, y: 13), control: CGPoint(x: 13, y: 8))
        flag.closeSubpath()
        g.addChild(shape(flag, fill: ink))

        // Note head — tilted filled oval at the lower left, connected to the stem base.
        let head = SKShapeNode(ellipseOf: CGSize(width: 22, height: 15))
        head.fillColor = ink
        head.strokeColor = .clear
        head.position = CGPoint(x: -6, y: -20)
        head.zRotation = -0.32
        g.addChild(head)

        return g
    }

    private static func star() -> SKNode {
        let g = SKNode()
        g.addChild(shape(starPath(radius: 29), fill: NSColor(hexString: "F3C63F")))
        return g
    }

    private static func heart() -> SKNode {
        let g = SKNode()
        g.addChild(shape(heartPath(w: 52, h: 46), fill: NSColor(hexString: "EF6079")))
        return g
    }

    private static func pick() -> SKNode {
        let g = SKNode()
        // teal gradient approximated with a solid mid-tone
        g.addChild(shape(pickPath(w: 50, h: 56), fill: NSColor(hexString: "64B7A3")))
        return g
    }

    private static func ticket() -> SKNode {
        let g = SKNode()
        g.addChild(roundedRect(CGSize(width: 118, height: 56), radius: 5, color: NSColor(hexString: "F0E3C4")))
        // perforated/torn-edge notches just inside all four edges
        let notchColor = NSColor(hexString: "E6D9B8")
        let halfW: CGFloat = 59, halfH: CGFloat = 28, inset: CGFloat = 4
        let cols = 8, rows = 3
        for i in 0...cols {
            let x = -halfW + inset + (CGFloat(i) / CGFloat(cols)) * (2 * halfW - 2 * inset)
            for y in [halfH - inset, -halfH + inset] {
                let dot = SKShapeNode(circleOfRadius: 2)
                dot.fillColor = notchColor; dot.strokeColor = .clear
                dot.position = CGPoint(x: x, y: y)
                g.addChild(dot)
            }
        }
        for j in 1..<rows {
            let y = -halfH + inset + (CGFloat(j) / CGFloat(rows)) * (2 * halfH - 2 * inset)
            for x in [halfW - inset, -halfW + inset] {
                let dot = SKShapeNode(circleOfRadius: 2)
                dot.fillColor = notchColor; dot.strokeColor = .clear
                dot.position = CGPoint(x: x, y: y)
                g.addChild(dot)
            }
        }
        // dashed tear line
        let dash = CGMutablePath()
        dash.move(to: CGPoint(x: 18, y: 26)); dash.addLine(to: CGPoint(x: 18, y: -26))
        let tear = SKShapeNode(path: dash.copy(dashingWithPhase: 0, lengths: [3, 3]))
        tear.strokeColor = NSColor(hexString: "C7B689"); tear.lineWidth = 1.5
        g.addChild(tear)
        let label = SKLabelNode(text: "ADMIT ONE")
        label.fontName = "Menlo-Bold"
        label.fontSize = 7
        label.fontColor = NSColor(hexString: "8A7C56")
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.zRotation = .pi / 2
        label.position = CGPoint(x: 20, y: 0)
        g.addChild(label)
        return g
    }

    private static func linkCard() -> SKNode {
        let g = SKNode()
        g.addChild(roundedRect(CGSize(width: 136, height: 60), radius: 9, color: .white))
        let thumb = roundedRect(CGSize(width: 44, height: 44), radius: 7, color: NSColor(hexString: "EF9A9A"))
        thumb.position = CGPoint(x: -42, y: 0)
        g.addChild(thumb)
        let bar1 = roundedRect(CGSize(width: 60, height: 8), radius: 4, color: NSColor(hexString: "D8D4CE"))
        bar1.position = CGPoint(x: 18, y: 8)
        let bar2 = roundedRect(CGSize(width: 42, height: 8), radius: 4, color: NSColor(hexString: "E4E1DB"))
        bar2.position = CGPoint(x: 9, y: -8)
        g.addChild(bar1); g.addChild(bar2)
        return g
    }

    private static func imessage() -> SKNode {
        let g = SKNode()
        g.addChild(roundedRect(CGSize(width: 196, height: 46), radius: 23, color: NSColor(hexString: "1B8DFF")))
        // tail hooking off bottom-right
        let tail = CGMutablePath()
        tail.move(to: CGPoint(x: 78, y: -14))
        tail.addLine(to: CGPoint(x: 96, y: -23))
        tail.addLine(to: CGPoint(x: 82, y: -6))
        tail.closeSubpath()
        g.addChild(shape(tail, fill: NSColor(hexString: "1B8DFF")))
        let label = SKLabelNode(text: "you need to hear this")
        label.fontName = "HelveticaNeue-Medium"
        label.fontSize = 15
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        g.addChild(label)
        return g
    }

    private static func jerry() -> SKNode {
        let g = SKNode()
        let target: CGFloat = 96  // visible head size

        if let img = NSImage(named: "JerryGarcia") {
            // Transparent head cutout — the PNG's own alpha, NO circle / white ring / sticker bg.
            // Crop to the solid-head bounding box (normalized, origin bottom-left) so the head
            // fills the object instead of floating in transparent padding.
            let headRect = CGRect(x: 0.1279, y: 0.3060, width: 0.7188, height: 0.4922)
            let tex = SKTexture(rect: headRect, in: SKTexture(image: img))
            let s = tex.size()
            let scale = target / max(s.width, s.height)
            let sprite = SKSpriteNode(texture: tex)
            sprite.size = CGSize(width: s.width * scale, height: s.height * scale)
            g.addChild(sprite)
            return g
        }

        // Fallback — tie-dye radial-gradient disc + white ring (asset unavailable).
        let bands: [(CGFloat, NSColor)] = [
            (48, NSColor(hexString: "C84AA0")),
            (40, NSColor(hexString: "E8663F")),
            (32, NSColor(hexString: "F3C63F")),
            (24, NSColor(hexString: "5FC559")),
            (16, NSColor(hexString: "3F8FE8")),
            (8,  NSColor(hexString: "9B85F2")),
        ]
        for (r, c) in bands { g.addChild(disc(r, color: c)) }
        g.addChild(disc(47, color: .clear, stroke: .white, lineW: 4))
        return g
    }

    // MARK: Path builders

    private static func starPath(radius R: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let inner = R * 0.42
        for i in 0..<10 {
            let r = i % 2 == 0 ? R : inner
            let a = CGFloat(i) * .pi / 5 - .pi / 2
            let pt = CGPoint(x: cos(a) * r, y: sin(a) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    private static func heartPath(w: CGFloat, h: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let lobeR = w * 0.25
        let lobeY = h * 0.18
        p.move(to: CGPoint(x: 0, y: -h * 0.42))
        p.addCurve(to: CGPoint(x: -w * 0.5, y: lobeY),
                   control1: CGPoint(x: -w * 0.28, y: -h * 0.42),
                   control2: CGPoint(x: -w * 0.5, y: -h * 0.08))
        p.addArc(center: CGPoint(x: -w * 0.25, y: lobeY), radius: lobeR, startAngle: .pi, endAngle: 0, clockwise: false)
        p.addArc(center: CGPoint(x: w * 0.25, y: lobeY), radius: lobeR, startAngle: .pi, endAngle: 0, clockwise: false)
        p.addCurve(to: CGPoint(x: 0, y: -h * 0.42),
                   control1: CGPoint(x: w * 0.5, y: -h * 0.08),
                   control2: CGPoint(x: w * 0.28, y: -h * 0.42))
        p.closeSubpath()
        return p
    }

    private static func pickPath(w: CGFloat, h: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: -h / 2)) // bottom point
        p.addQuadCurve(to: CGPoint(x: -w / 2, y: h * 0.22), control: CGPoint(x: -w * 0.5, y: -h * 0.22))
        p.addQuadCurve(to: CGPoint(x: 0, y: h / 2), control: CGPoint(x: -w * 0.4, y: h * 0.55))
        p.addQuadCurve(to: CGPoint(x: w / 2, y: h * 0.22), control: CGPoint(x: w * 0.4, y: h * 0.55))
        p.addQuadCurve(to: CGPoint(x: 0, y: -h / 2), control: CGPoint(x: w * 0.5, y: -h * 0.22))
        p.closeSubpath()
        return p
    }
}
