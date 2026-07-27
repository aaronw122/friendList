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

            phaseContent
                .id(state.step)
                .zIndex(10 - Double(state.step))
                .transition(.asymmetric(
                    insertion: .identity,
                    removal: .move(edge: .top)))

            if state.step >= 2 {
                SheetTopProgressBar(fraction: state.progressFraction)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .zIndex(100)
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

    @ViewBuilder private var phaseContent: some View {
        switch state.step {
        case 0:
            HomeView()
        case 1:
            WelcomeView()
        default:
            stepScreen
                .frame(width: Geometry.sheetWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var stepScreen: some View {
        switch state.step {
        case 2: PickChatView()
        case 3: ScanningView()
        case 4: SpotifyKeysView()
        case 5: OAuthConsentView()
        case 6: CustomizeView()
        case 7: CreatingView()
        case 8: AllSetView()
        default: Color.clear
        }
    }
}
