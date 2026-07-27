import SwiftUI

// MARK: - Shared loader building blocks (used by Scanning + Creating)

/// 46×46 ring: 4pt track in spinnerTrack with a top arc in accent,
/// rotating 360°/0.8s linear forever.
struct LoaderSpinner: View {
    @State private var spinning = false
    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.spinnerTrack, lineWidth: 4)
            Circle()
                .trim(from: 0, to: 0.25)
                .stroke(Palette.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(spinning ? 360 : 0))
        }
        .frame(width: 46, height: 46)
        .onAppear {
            withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                spinning = true
            }
        }
    }
}

/// 300×6 progress bar, radius 3, track spinnerTrack, fill accent, width animates over 400ms ease.
struct LoaderProgressBar: View {
    let pct: Double
    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Palette.spinnerTrack)
                .frame(width: 300, height: 6)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Palette.accent)
                .frame(width: 300 * max(0, min(1, pct)), height: 6)
                .animation(.easeInOut(duration: 0.4), value: pct)
        }
    }
}

/// Centered loader column shared by Scanning + Creating.
struct LoaderScaffold: View {
    let heading: String
    let label: String
    let pct: Double
    /// nil omits the song counter line entirely (Creating).
    var counter: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            LoaderSpinner()
            Text(heading)
                .font(UIFont2.ui(22, 800))
                .tracking(-0.03 * 22)
                .foregroundStyle(Palette.ink)
                .padding(.top, 20)
            Text(label)
                .font(UIFont2.ui(13.5))
                .foregroundStyle(Palette.body)
                .frame(minHeight: 20) // reserve height so it doesn't jump between messages
                .padding(.top, 12)
            LoaderProgressBar(pct: pct)
                .padding(.top, 10)
            if let counter {
                Text(counter)
                    .font(UIFont2.mono(12))
                    .foregroundStyle(Palette.faint)
                    .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Scanning (step 3)

/// Step 3 shows two states on one step: the scanning spinner, then a result
/// screen with the song count and Continue. Staying on a single step keeps the
/// state machine, navigation, and progress bar unchanged.
struct ScanningView: View {
    @Environment(OnboardingState.self) private var state
    @State private var ran = false
    @State private var done = false

    var body: some View {
        ZStack {
            if done {
                ScanResultView(found: state.found, chatName: state.selectedChatName)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                LoaderScaffold(
                    heading: "Reading \(state.selectedChatName)",
                    label: state.scanLabel,
                    pct: state.scanPct,
                    counter: "\(state.found) songs found"
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: done)
        .task { await runScan() }
    }

    @MainActor
    private func runScan() async {
        guard !ran else { return } // guard against re-running if the view reappears
        ran = true

        await state.performScan()      // real chat.db read + link extraction
        try? await Task.sleep(for: .milliseconds(400))  // let the final count land
        // Don't flip to the result if the user swiped back mid-scan.
        guard !Task.isCancelled, state.step == 3 else { return }
        done = true                    // settle into the "found X songs" screen
    }
}

// MARK: - Scan result ("We found X songs")

/// The payoff screen: reports the deduped song count before the Spotify ask.
/// A zero result routes back to the picker instead of building an empty playlist.
private struct ScanResultView: View {
    @Environment(OnboardingState.self) private var state
    let found: Int
    let chatName: String

    private var hasSongs: Bool { found > 0 }

    var body: some View {
        VStack(spacing: 0) {
            // Centered payoff fills the space above the footer.
            centerBlock
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Continue lives in the standard footer (bottom-right), matching the
            // picker/other steps; the global "Back" link sits bottom-left.
            SheetFooter(
                backTitle: nil,
                onBack: nil,
                primaryTitle: hasSongs ? "Continue" : "Pick another chat",
                primaryEnabled: true,
                onPrimary: { hasSongs ? state.advance() : state.back() }
            )
        }
    }

    @ViewBuilder private var centerBlock: some View {
        if hasSongs {
            VStack(spacing: 0) {
                Text("\(found)")
                    .font(UIFont2.ui(144, 800))
                    .tracking(-0.04 * 144)
                    .foregroundStyle(Palette.accent)
                    .shadow(color: .white.opacity(0.9), radius: 0, y: 2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                // Chat name italic to mark it as a group-chat name.
                (
                    Text(found == 1 ? "song found in " : "songs found in ")
                        .font(UIFont2.ui(22, 800))
                        .foregroundStyle(Palette.ink)
                    + Text(chatName)
                        .font(UIFont2.ui(22, 800))
                        .italic()
                        .foregroundStyle(Palette.ink)
                )
                .tracking(-0.03 * 22)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            }
        } else {
            VStack(spacing: 0) {
                Text("No songs yet")
                    .font(UIFont2.ui(28, 800))
                    .tracking(-0.03 * 28)
                    .foregroundStyle(Palette.ink)

                (
                    Text("We didn't find any Spotify links in ")
                        .font(UIFont2.ui(15, 500))
                        .foregroundStyle(Palette.body)
                    + Text(chatName)
                        .font(UIFont2.ui(15, 500))
                        .italic()
                        .foregroundStyle(Palette.body)
                    + Text(". Try a chat where people share tracks.")
                        .font(UIFont2.ui(15, 500))
                        .foregroundStyle(Palette.body)
                )
                .lineSpacing(6)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            }
        }
    }
}
