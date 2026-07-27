import SpriteKit
import AppKit

/// The persistent falling-objects stage. Objects drop from above the top edge,
/// collide, and settle. The user can grab and fling any object with the cursor.
/// Feel is tuned to the README's Matter.js reference values (SpriteKit units differ).
final class StageScene: SKScene {

    /// Assigned by `PhysicsStageView`; registering closures is safe at any time.
    weak var bridge: PhysicsBridge? {
        didSet { registerBridge() }
    }

    /// Live objects in stable spawn order. `popEveryOther` walks this order.
    private var objects: [SKNode] = []

    // Drag / fling state
    private var grabbed: SKNode?
    private var lastPoint: CGPoint = .zero
    private var lastTime: TimeInterval = 0
    private var flingVelocity: CGVector = .zero

    private let spawnInset: CGFloat = 70

    // MARK: Lifecycle

    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0, y: 0)
        backgroundColor = .clear
        scaleMode = .resizeFill
        // Gentle-but-real fall tuned to the Matter.js gravity-Y 1.05 reference.
        physicsWorld.gravity = CGVector(dx: 0, dy: -8)
        buildWalls()
        registerBridge()
        spawnObjects()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        if size.width > 0, size.height > 0 { buildWalls() }
    }

    // MARK: Walls

    /// Static floor / left / right edges plus a high ceiling well above the top,
    /// so objects can spawn off-screen and fall in.
    private func buildWalls() {
        enumerateChildNodes(withName: "wall") { node, _ in node.removeFromParent() }
        let w = size.width
        let h = size.height
        guard w > 0, h > 0 else { return }
        let ceiling = h + 1600

        func wall(_ a: CGPoint, _ b: CGPoint) {
            let node = SKNode()
            node.name = "wall"
            let body = SKPhysicsBody(edgeFrom: a, to: b)
            body.restitution = 0.4
            body.friction = 0.6
            node.physicsBody = body
            addChild(node)
        }

        wall(CGPoint(x: 0, y: 0), CGPoint(x: w, y: 0))                 // floor
        wall(CGPoint(x: 0, y: 0), CGPoint(x: 0, y: ceiling))          // left
        wall(CGPoint(x: w, y: 0), CGPoint(x: w, y: ceiling))          // right
        wall(CGPoint(x: 0, y: ceiling), CGPoint(x: w, y: ceiling))    // ceiling
    }

    // MARK: Spawning

    /// Clears the world and (re)drops all 14 objects: staggered, off-screen above
    /// the top, random small angle. First at 260ms, then one every 130ms.
    private func spawnObjects() {
        removeAllObjects()
        for (i, spec) in PhysicsObjects.all.enumerated() {
            let delay = 0.26 + Double(i) * 0.13
            run(SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.run { [weak self] in self?.drop(spec) }
            ]))
        }
    }

    private func drop(_ spec: ObjectSpec) {
        guard size.width > 0 else { return }
        let node = PhysicsObjects.makeNode(spec)
        let x = CGFloat.random(in: spawnInset...(size.width - spawnInset))
        let y = size.height + CGFloat.random(in: 120...640)
        // Upright-biased objects (the iMessage bubble) lock level 67% of the time.
        let upright = spec.uprightBias && CGFloat.random(in: 0..<1) < 0.67
        node.position = CGPoint(x: x, y: y)
        node.zRotation = upright ? 0 : CGFloat.random(in: -0.6...0.6)
        node.zPosition = CGFloat(objects.count)
        node.physicsBody?.allowsRotation = !upright
        node.physicsBody?.velocity = .zero
        node.physicsBody?.angularVelocity = upright ? 0 : CGFloat.random(in: -1.2...1.2)
        addChild(node)
        objects.append(node)
    }

    private func removeAllObjects() {
        removeAllActions() // cancel any pending staggered spawns
        for node in objects { node.removeFromParent() }
        objects.removeAll()
        grabbed = nil
    }

    // MARK: Bridge

    private func registerBridge() {
        bridge?.onPopEveryOther = { [weak self] in self?.popEveryOther() }
        bridge?.onDropAll = { [weak self] in self?.spawnObjects() }
        bridge?.onReset = { [weak self] in self?.spawnObjects() }
    }

    /// Remove every other object (index % 2 == 0) with a ~340ms pop:
    /// scale 1 → 1.45 → 1.7 with fade to 0, staggered 55ms apart.
    private func popEveryOther() {
        let toPop = objects.enumerated().filter { $0.offset % 2 == 0 }.map { $0.element }
        for (i, node) in toPop.enumerated() {
            node.physicsBody = nil
            let delay = SKAction.wait(forDuration: Double(i) * 0.055)
            let grow1 = SKAction.scale(to: 1.45, duration: 0.17)
            let grow2 = SKAction.scale(to: 1.7, duration: 0.17)
            let fade = SKAction.fadeOut(withDuration: 0.34)
            let anim = SKAction.group([SKAction.sequence([grow1, grow2]), fade])
            node.run(SKAction.sequence([delay, anim, SKAction.removeFromParent()]))
        }
        objects.removeAll { node in toPop.contains { $0 === node } }
    }

    // MARK: Drag / fling

    private func objectNode(at point: CGPoint) -> SKNode? {
        objects.reversed().first {
            $0.calculateAccumulatedFrame().insetBy(dx: -4, dy: -4).contains(point)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = event.location(in: self)
        guard let node = objectNode(at: p) else { return }
        grabbed = node
        lastPoint = p
        lastTime = event.timestamp
        flingVelocity = .zero
        node.physicsBody?.velocity = .zero
        node.physicsBody?.angularVelocity = 0
    }

    override func mouseDragged(with event: NSEvent) {
        guard let node = grabbed else { return }
        let raw = event.location(in: self)
        // Keep the dragged object inside the walls. The physics edges only stop
        // physics-driven motion; a hand-assigned position would otherwise sail
        // straight through the floor/sides. Clamp so the object's edges — not its
        // center — stop at each wall, using its current accumulated frame to get
        // the half-extents. Top is left free (the ceiling sits far above-screen).
        let frame = node.calculateAccumulatedFrame()
        let leftInset = node.position.x - frame.minX
        let rightInset = frame.maxX - node.position.x
        let bottomInset = node.position.y - frame.minY
        let minX = leftInset
        let maxX = max(minX, size.width - rightInset)
        let p = CGPoint(x: min(max(raw.x, minX), maxX),
                        y: max(raw.y, bottomInset))
        let dt = max(event.timestamp - lastTime, 1.0 / 240.0)
        flingVelocity = CGVector(dx: (p.x - lastPoint.x) / CGFloat(dt),
                                 dy: (p.y - lastPoint.y) / CGFloat(dt))
        node.position = p
        node.physicsBody?.velocity = .zero
        lastPoint = p
        lastTime = event.timestamp
    }

    override func mouseUp(with event: NSEvent) {
        guard let node = grabbed else { return }
        let maxV: CGFloat = 2400
        let v = CGVector(dx: min(max(flingVelocity.dx, -maxV), maxV),
                         dy: min(max(flingVelocity.dy, -maxV), maxV))
        node.physicsBody?.velocity = v
        grabbed = nil
    }

    // Scroll-wheel capture disabled.
    override func scrollWheel(with event: NSEvent) {}
}
