import SwiftUI

struct OnboardingContainer: View {
    @State private var state = OnboardingState()
    @State private var physics = PhysicsBridge()

    var body: some View {
        ZStack {
            Palette.deskGradient.ignoresSafeArea()

            PhysicsStageView(bridge: physics)
                .opacity(state.step >= 2 ? 0 : 1)
                .allowsHitTesting(state.step < 2)
                .animation(.easeInOut(duration: 0.35), value: state.step >= 2)
                .zIndex(0)

            screen(for: state.step)
                .id(state.step)
                .transition(pushTransition)
                .zIndex(10)

            if state.step >= 2 {
                SheetTopProgressBar(fraction: state.progressFraction)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .zIndex(1000)
            }

            if state.canGoBack {
                HStack {
                    LinkButton(title: "Back", size: 13, color: Palette.body) { state.back() }
                    Spacer(minLength: 0)
                }
                .padding(.leading, SheetLayout.hInset)
                .frame(width: Geometry.sheetWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, SheetLayout.footerInset + 12)
                .zIndex(100)
            }
        }
        .frame(width: Geometry.contentWidth, height: Geometry.contentHeight)
        .environment(state)
        .environment(\.physicsBridge, physics)
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    guard state.canGoBack else { return }
                    let dx = value.translation.width, dy = value.translation.height
                    if dx > 80 && abs(dx) > abs(dy) * 1.3 { state.back() }
                }
        )
    }

    // Vertical push: forward pushes up, back pushes down; go()'s spring drives it.
    private var pushTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: state.goingBack ? .top : .bottom),
            removal:   .move(edge: state.goingBack ? .bottom : .top)
        )
    }

    @ViewBuilder private func screen(for step: Int) -> some View {
        switch step {
        case 0:
            HomeView()
        case 1:
            WelcomeView()
        default:
            stepScreen(for: step)
                .frame(width: Geometry.sheetWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private func stepScreen(for step: Int) -> some View {
        switch step {
        case 2: PermissionsView()
        case 3: PickChatView()
        case 4: ScanningView()
        case 5: SpotifyKeysView()
        case 6: OAuthConsentView()
        case 7: CustomizeView()
        case 8: CreatingView()
        case 9: AllSetView()
        default: Color.clear
        }
    }
}
