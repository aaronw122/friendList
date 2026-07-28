import SwiftUI

final class PhysicsBridge {
    var onPopEveryOther: () -> Void = {}
    var onDropAll: () -> Void = {}
    var onReset: () -> Void = {}

    func popEveryOther() { onPopEveryOther() }
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
