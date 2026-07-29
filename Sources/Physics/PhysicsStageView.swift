import SwiftUI
import SpriteKit

struct PhysicsStageView: View {
    let bridge: PhysicsBridge
    var isPaused = false

    // StateObject creates the scene once, so the bridge stays bound to the live scene across body re-evaluations.
    @StateObject private var holder = StageSceneHolder()

    var body: some View {
        // resizeFill keeps the scene floor aligned with the window’s actual bottom edge.
        SpriteView(scene: holder.scene, isPaused: isPaused, options: [.allowsTransparency])
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { holder.scene.bridge = bridge }
    }
}

private final class StageSceneHolder: ObservableObject {
    let scene: StageScene

    init() {
        scene = StageScene(size: CGSize(width: Geometry.contentWidth,
                                        height: Geometry.stageHeight))
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .clear
    }
}
