import SwiftUI

@main
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
        }
    }
}
