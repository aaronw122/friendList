import SwiftUI

struct OnboardingContainer: View {
    @State private var state = OnboardingState()
    @State private var physics = PhysicsBridge()
    @State private var visibleStep = 1
    @State private var outgoingStep: Int?
    @State private var incomingOffset: CGFloat = 0
    @State private var outgoingOffset: CGFloat = 0
    @State private var transitionID = 0

    init() {
        let state = OnboardingState()
        _state = State(initialValue: state)
        _visibleStep = State(initialValue: state.step)
    }

    var body: some View {
        ZStack {
            Palette.deskGradient.ignoresSafeArea()

            PhysicsStageView(bridge: physics)
                .opacity(state.step >= 2 ? 0 : 1)
                .allowsHitTesting(state.step < 2)
                .animation(.easeInOut(duration: 0.35), value: state.step >= 2)
                .zIndex(0)

            ForEach(renderedSteps, id: \.self) { step in
                screen(for: step)
                    .offset(y: step == outgoingStep ? outgoingOffset : incomingOffset)
                    .allowsHitTesting(outgoingStep == nil)
                    .zIndex(step == outgoingStep ? 10 : 11)
            }

            // Hides the sliding screens behind the title bar.
            Rectangle()
                .fill(Palette.deskTop)
                .frame(height: 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
                .zIndex(500)

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
                .allowsHitTesting(outgoingStep == nil)
                .zIndex(100)
            }
        }
        .frame(width: Geometry.contentWidth, height: Geometry.contentHeight)
        .environment(state)
        .environment(\.physicsBridge, physics)
        .onChange(of: state.step) { _, newStep in beginTransition(to: newStep) }
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    guard state.canGoBack else { return }
                    guard outgoingStep == nil else { return }
                    let dx = value.translation.width, dy = value.translation.height
                    if dx > 80 && abs(dx) > abs(dy) * 1.3 { state.back() }
                }
        )
    }

    private func beginTransition(to newStep: Int) {
        let previous = visibleStep
        guard newStep != previous else { return }
        let height = Geometry.contentHeight
        let exitOverscan: CGFloat = 64
        let goingBack = state.goingBack
        transitionID += 1
        let id = transitionID

        var still = Transaction(); still.disablesAnimations = true
        withTransaction(still) {
            outgoingStep = previous
            outgoingOffset = 0
            incomingOffset = goingBack ? -height : height
            visibleStep = newStep
        }

        Task { @MainActor in
            await Task.yield()
            guard transitionID == id else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                incomingOffset = 0
            }
            withAnimation(.easeInOut(duration: 0.30)) {
                outgoingOffset = goingBack
                    ? height + exitOverscan
                    : -(height + exitOverscan)
            } completion: {
                guard transitionID == id else { return }
                var done = Transaction(); done.disablesAnimations = true
                withTransaction(done) {
                    outgoingStep = nil
                    outgoingOffset = 0
                }
            }
        }
    }

    private var renderedSteps: [Int] {
        if let outgoingStep { return [visibleStep, outgoingStep] }
        return [visibleStep]
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
