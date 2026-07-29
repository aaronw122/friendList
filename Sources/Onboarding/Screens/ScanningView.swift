import SwiftUI

// MARK: - Shared loader building blocks (used by Scanning + Creating)

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

struct LoaderScaffold: View {
    let heading: String
    let label: String
    let pct: Double
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
                .frame(minHeight: 20)
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

struct ScanningView: View {
    @Environment(OnboardingState.self) private var state
    @State private var ran = false
    @State private var done = false

    var body: some View {
        ZStack {
            if done, let message = state.scanError {
                ScanErrorView(message: message, onRetry: retry)
                    .transition(.opacity)
            } else if done {
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
        guard !ran else { return }
        ran = true

        await state.performScan()
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled, state.step == 4 else { return }
        done = true
    }

    private func retry() {
        ran = false
        done = false
        Task { await runScan() }
    }
}

// MARK: - Scan error ("Couldn't read this chat")

private struct ScanErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Text("Couldn't read this chat")
                    .font(UIFont2.ui(28, 800))
                    .tracking(-0.03 * 28)
                    .foregroundStyle(Palette.ink)

                Text(message)
                    .font(UIFont2.ui(15, 500))
                    .foregroundStyle(Palette.body)
                    .lineSpacing(6)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            SheetFooter(
                backTitle: nil,
                onBack: nil,
                primaryTitle: "Try again",
                primaryEnabled: true,
                onPrimary: onRetry
            )
        }
    }
}

// MARK: - Scan result ("We found X songs")

private struct ScanResultView: View {
    @Environment(OnboardingState.self) private var state
    let found: Int
    let chatName: String

    private var hasSongs: Bool { found > 0 }

    var body: some View {
        VStack(spacing: 0) {
            centerBlock
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if state.shortLinkCount > 0 {
                Text("Skipped \(state.shortLinkCount) spotify.link short \(state.shortLinkCount == 1 ? "link" : "links") we can't match yet")
                    .font(UIFont2.ui(12))
                    .foregroundStyle(Palette.muted)
                    .padding(.bottom, 10)
            }

            SheetFooter(
                backTitle: nil,
                onBack: nil,
                primaryTitle: hasSongs ? "Continue" : "Pick another chat",
                primaryEnabled: true,
                onPrimary: {
                    if hasSongs {
                        Task { await state.continueAfterScan() }
                    } else {
                        state.back()
                    }
                }
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
