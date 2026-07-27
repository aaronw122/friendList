import SwiftUI

/// Root composition: ONE persistent desk-and-objects background for every phase.
/// Each phase's content renders directly on it — no white sheet, no floating panel.
/// Navigating sweeps the current screen out and slides the next one in, like a
/// normal app flow. The physics objects stay present on every screen.
struct OnboardingContainer: View {
    @State private var state = OnboardingState()
    @State private var physics = PhysicsBridge()

    var body: some View {
        ZStack {
            Palette.deskGradient.ignoresSafeArea()

            // Physics stage — objects show only on Welcome (1) and Home (0).
            // The moment you hit Continue into the steps (2–8) they fade away.
            // Hidden stage ignores hits so content + swipe-back work over it.
            PhysicsStageView(bridge: physics)
                .opacity(state.step >= 2 ? 0 : 1)
                .allowsHitTesting(state.step < 2)
                .animation(.easeInOut(duration: 0.35), value: state.step >= 2)
                .zIndex(0)   // below content

            // Window-shade transition: the outgoing screen slides up off the top,
            // revealing the next one underneath. zIndex decreases with step (within
            // a band between physics and chrome) so the outgoing screen stays on top.
            phaseContent
                .id(state.step)
                .zIndex(10 - Double(state.step))
                .transition(.asymmetric(
                    insertion: .identity,
                    removal: .move(edge: .top)))

            // Thin progress strip for the onboarding steps (2–8), at the top edge.
            if state.step >= 2 {
                SheetTopProgressBar(fraction: state.progressFraction)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .zIndex(100)   // above content
            }

            // Global Back — available on every onboarding step (2–8), bottom-left,
            // aligned to the content column so it pairs with each screen's CTA.
            if state.canGoBack {
                HStack {
                    LinkButton(title: "Back", size: 13, color: Palette.body) { state.back() }
                    Spacer(minLength: 0)
                }
                .padding(.leading, SheetLayout.hInset)
                .frame(width: Geometry.sheetWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, SheetLayout.footerInset + 12)
                .zIndex(100)   // above content
            }
        }
        .frame(width: Geometry.contentWidth, height: Geometry.contentHeight)
        .environment(state)
        .environment(\.physicsBridge, physics)
        // Swipe right to go back, at any point in the flow.
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
            // Onboarding steps render in a centered 600pt column on the same
            // background (no sheet).
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
