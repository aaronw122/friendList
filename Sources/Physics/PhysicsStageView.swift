import SwiftUI
import SpriteKit

/// SwiftUI wrapper for the persistent SpriteKit physics stage.
/// Transparent so the desk gradient behind shows through.
struct PhysicsStageView: View {
    let bridge: PhysicsBridge

    @State private var scene: StageScene

    init(bridge: PhysicsBridge) {
        self.bridge = bridge
        let scene = StageScene(size: CGSize(width: Geometry.contentWidth,
                                            height: Geometry.stageHeight))
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .clear
        scene.bridge = bridge // registers onPopEveryOther / onDropAll / onReset
        _scene = State(initialValue: scene)
    }

    var body: some View {
        // Fill the whole stage area (scaleMode .resizeFill keeps the floor at the
        // real bottom edge) so objects settle against the bottom of the window.
        SpriteView(scene: scene, options: [.allowsTransparency])
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { scene.bridge = bridge }
    }
}
