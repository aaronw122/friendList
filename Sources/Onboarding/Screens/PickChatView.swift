import SwiftUI

/// Step 3 — Pick a group chat. Renders in a 600pt-wide centered column on the
/// plain gradient (no white sheet). Full Disk Access is handled upstream on the
/// Permissions step, so this shows a search field + a chat list that fills the
/// available height and scrolls.
struct PickChatView: View {
    @Environment(OnboardingState.self) private var state

    var body: some View {
        @Bindable var state = state

        VStack(spacing: 0) {
            // Fixed top block: heading, subhead, (search).
            VStack(alignment: .leading, spacing: 0) {
                Text("Pick a group chat")
                    .font(UIFont2.ui(26, 800))
                    .tracking(-0.03 * 26)
                    .foregroundStyle(Palette.ink)

                Text("Just one to start. You can add more chats whenever you like.")
                    .font(UIFont2.ui(14))
                    .foregroundStyle(Palette.body)
                    .padding(.top, 7)

                if state.access {
                    searchField(text: $state.chatSearch)
                        .padding(.top, 20)
                }
            }
            .padding(.horizontal, SheetLayout.hInset)
            .padding(.top, SheetLayout.topInset)

            if state.access {
                // Flexible scrolling list — grows to ~5pt above the footer.
                chatList
                    .padding(.horizontal, SheetLayout.hInset)
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, 5)
            } else {
                permissionCard
                    .padding(.horizontal, SheetLayout.hInset)
                    .padding(.top, 20)
                Spacer(minLength: 0)
            }

            SheetFooter(
                backTitle: nil,
                onBack: nil,
                primaryTitle: "Continue",
                primaryEnabled: state.pickedID != nil,
                onPrimary: { state.advance() }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { state.probeAccessOnAppear() }
        .onDisappear { state.cancelAccessPolling() }
    }

    // MARK: Permission state (no Full Disk Access yet)

    private var permissionCard: some View {
        VStack(spacing: 0) {
            Text("friendList needs Full Disk Access to read Messages")
                .font(UIFont2.ui(14, 600))
                .foregroundStyle(Palette.permTitle)
                .multilineTextAlignment(.center)

            Text("macOS will ask you to confirm in System Settings.")
                .font(UIFont2.ui(12.5))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 6)

            PrimaryButton(title: "Grant access", metrics: .compact, action: { state.requestAccess() })
                .padding(.top, 16)

            Text("If the list stays empty after enabling friendList, quit and reopen the app.")
                .font(UIFont2.ui(11.5))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
        .padding(26)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    Palette.permBorder,
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                )
        )
    }

    // MARK: Search field (after access granted)

    private func searchField(text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.faint)

            TextField("Search chats", text: text)
                .textFieldStyle(.plain)
                .font(UIFont2.ui(14))
                .foregroundStyle(Palette.fieldInk)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Palette.field)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1)
        )
    }

    // MARK: Chat list (after access granted)

    private var chatList: some View {
        ScrollView {
            VStack(spacing: 0) {
                let chats = state.visibleChats
                ForEach(Array(chats.enumerated()), id: \.element.id) { index, chat in
                    chatRow(chat)
                    if index < chats.count - 1 {
                        Rectangle()
                            .fill(Palette.divider)
                            .frame(height: 1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chatRow(_ chat: ChatSample) -> some View {
        let selected = chat.id == state.pickedID
        return HStack(spacing: 11) {
            radio(selected: selected)

            Text(chat.name)
                .font(UIFont2.ui(14, 700))
                .foregroundStyle(Palette.rowName)

            if chat.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.faint)
            }

            Spacer(minLength: 8)

            Text("\(chat.links) \(chat.links == 1 ? "song" : "songs")")
                .font(UIFont2.mono(11))
                .foregroundStyle(Palette.faint)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Palette.tint : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { state.pickedID = chat.id }
    }

    private func radio(selected: Bool) -> some View {
        Circle()
            .strokeBorder(
                selected ? Palette.accent : Color(hex: "D8D2C6"),
                lineWidth: selected ? 5 : 2
            )
            .frame(width: 15, height: 15)
    }
}
