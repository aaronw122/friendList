import SwiftUI
import SpriteKit

struct PhysicsStageView: View {
    let bridge: PhysicsBridge

    @State private var scene: StageScene

    init(bridge: PhysicsBridge) {
        self.bridge = bridge
        let scene = StageScene(size: CGSize(width: Geometry.contentWidth,
                                            height: Geometry.stageHeight))
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .clear
        scene.bridge = bridge
        _scene = State(initialValue: scene)
    }

    var body: some View {
        // resizeFill keeps the scene floor aligned with the window’s actual bottom edge.
        SpriteView(scene: scene, options: [.allowsTransparency])
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { scene.bridge = bridge }
    }
}
