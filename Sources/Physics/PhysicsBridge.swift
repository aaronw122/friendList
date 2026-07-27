import SwiftUI

/// Decoupling seam between SwiftUI and the SpriteKit scene.
/// The scene registers its closures on load; screens/container call the methods.
/// This lets the physics files and the screen files be built independently.
final class PhysicsBridge {
    var onPopEveryOther: () -> Void = {}
    var onDropAll: () -> Void = {}
    var onReset: () -> Void = {}

    /// On Continue: pop every other solid object (index % 2 == 0), staggered.
    func popEveryOther() { onPopEveryOther() }
    /// Entering Home / "Create a new one": re-drop every object from the ceiling.
    func dropAll() { onDropAll() }
    func reset() { onReset() }
}

private struct PhysicsBridgeKey: EnvironmentKey {
    static let defaultValue = PhysicsBridge()
}

extension EnvironmentValues {
    var physicsBridge: PhysicsBridge {
        get { self[PhysicsBridgeKey.self] }
        set { self[PhysicsBridgeKey.self] = newValue }
    }
}
