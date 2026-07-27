import SwiftUI

@main
struct FriendListApp: App {
    var body: some Scene {
        WindowGroup {
            OnboardingContainer()
                .frame(width: Geometry.contentWidth, height: Geometry.contentHeight)
                .background(Palette.deskGradient)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: Geometry.contentWidth, height: Geometry.contentHeight)
    }
}
