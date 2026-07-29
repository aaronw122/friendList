import Foundation
import ServiceManagement

// The bundled LaunchAgent inherits the signed app's FDA and keychain grants.
enum BackgroundSyncAgent {
    static let label = "com.friendlist.app.sync"
    static let plistName = "\(label).plist"

    static func service() -> SMAppService {
        SMAppService.agent(plistName: plistName)
    }

    static func registerIfOnboarded(persistence: PersistenceProviding = AppPersistence()) {
        guard persistence.didOnboard else { return }
        let service = service()
        guard service.status != .enabled else { return }
        try? service.register()
    }
}
