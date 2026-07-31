import SwiftUI

@main
struct FriendListMain {
    static func main() {
        if CommandLine.arguments.contains("--reregister-sync") {
            BackgroundSyncAgent.forceReregister()
        }
        if HeadlessSync.isRequested(in: CommandLine.arguments) {
            HeadlessSync.run()
        }
        FriendListApp.main()
    }
}

struct FriendListApp: App {
    var body: some Scene {
        WindowGroup {
            rootView
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: Geometry.contentWidth, height: Geometry.contentHeight)
    }

    @ViewBuilder
    private var rootView: some View {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            Color.clear
        } else {
            OnboardingContainer()
                .frame(width: Geometry.contentWidth, height: Geometry.contentHeight)
                .background(Palette.deskGradient)
                .task { BackgroundSyncAgent.registerIfOnboarded() }
        }
    }
}
