import Foundation
import ServiceManagement

// Registers the single scheduled LaunchAgent (bundled at Contents/Library/LaunchAgents) that
// runs the `--sync` headless entry at 08:00/12:00/20:00. The signed app bundle inherits FDA +
// keychain grants, so the agent process reads chat.db and refreshes tokens without prompts.
enum BackgroundSyncAgent {
    static let label = "com.friendlist.app.sync"
    static let plistName = "\(label).plist"

    static func service() -> SMAppService {
        SMAppService.agent(plistName: plistName)
    }

    // Idempotent: registers only once onboarding is complete and the agent isn't already enabled.
    static func registerIfOnboarded(persistence: PersistenceProviding = AppPersistence()) {
        guard persistence.didOnboard else { return }
        let service = service()
        guard service.status != .enabled else { return }
        try? service.register()
    }
}
