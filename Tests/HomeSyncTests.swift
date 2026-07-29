import XCTest
@testable import FriendList

@MainActor
final class HomeSyncTests: PersistenceTestCase {
    func testReconnectNudgeFiresInsideTwoWeekWindowOnly() {
        let state = makeState()
        let cal = Calendar.current
        let authorized = Date(timeIntervalSince1970: 1_700_000_000)
        state.persistence.authorizationDate = authorized
        let anniversary = cal.date(byAdding: .month, value: 6, to: authorized)!

        let inside = cal.date(byAdding: .day, value: -7, to: anniversary)!
        let before = cal.date(byAdding: .day, value: -30, to: anniversary)!
        let after = cal.date(byAdding: .day, value: 1, to: anniversary)!

        XCTAssertTrue(state.reconnectNudgeActive(now: inside))
        XCTAssertFalse(state.reconnectNudgeActive(now: before))
        XCTAssertFalse(state.reconnectNudgeActive(now: after))
    }

    func testReconnectNudgeInactiveWithoutAuthorizationDate() {
        let state = makeState()
        state.persistence.authorizationDate = nil
        XCTAssertFalse(state.reconnectNudgeActive(now: Date()))
    }

    private func makeState() -> OnboardingState {
        OnboardingState(messages: MessagesFake(uris: []),
                        spotify: SpotifyFake(),
                        persistence: AppPersistence())
    }
}
