import XCTest
@testable import FriendList

final class MessagesReaderMergeTests: XCTestCase {
    private func row(rowID: Int64, guid: String, identifier: String,
                     displayName: String = "", messageCount: Int = 0, lastDate: Int64 = 0) -> MessagesReader.ChatRow {
        MessagesReader.ChatRow(rowID: rowID, guid: guid, identifier: identifier,
                               displayName: displayName, messageCount: messageCount, lastDate: lastDate)
    }

    func testMergesRowsSharingChatIdentifier() {
        let merged = MessagesReader.mergeSiblings([
            row(rowID: 1, guid: "iMessage;+;chat123", identifier: "chat123", messageCount: 100, lastDate: 50),
            row(rowID: 2, guid: "SMS;+;chat123", identifier: "chat123", messageCount: 40, lastDate: 80),
        ])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].rowIDs, [1, 2])
        XCTAssertEqual(merged[0].messageCount, 140)
        XCTAssertEqual(merged[0].lastDate, 80)
    }

    func testCanonicalGuidPrefersIMessageSibling() {
        let merged = MessagesReader.mergeSiblings([
            row(rowID: 2, guid: "SMS;+;chat123", identifier: "chat123"),
            row(rowID: 1, guid: "iMessage;+;chat123", identifier: "chat123"),
        ])

        XCTAssertEqual(merged[0].canonical.guid, "iMessage;+;chat123")
    }

    func testCanonicalGuidDeterministicWithoutIMessageSibling() {
        let merged = MessagesReader.mergeSiblings([
            row(rowID: 2, guid: "SMS;+;chat123", identifier: "chat123"),
            row(rowID: 1, guid: "RCS;+;chat123", identifier: "chat123"),
        ])

        XCTAssertEqual(merged[0].canonical.guid, "RCS;+;chat123")
    }

    func testDistinctIdentifiersStaySeparate() {
        let merged = MessagesReader.mergeSiblings([
            row(rowID: 1, guid: "iMessage;+;chatA", identifier: "chatA"),
            row(rowID: 2, guid: "iMessage;+;chatB", identifier: "chatB"),
        ])

        XCTAssertEqual(merged.count, 2)
    }

    func testEmptyIdentifierFallsBackToGuidKey() {
        let merged = MessagesReader.mergeSiblings([
            row(rowID: 1, guid: "iMessage;+;chatA", identifier: ""),
            row(rowID: 2, guid: "SMS;+;chatB", identifier: ""),
        ])

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.map(\.rowIDs), [[1], [2]])
    }

    func testDisplayNameFallsBackToNamedSibling() {
        let merged = MessagesReader.mergeSiblings([
            row(rowID: 1, guid: "iMessage;+;chat123", identifier: "chat123", displayName: ""),
            row(rowID: 2, guid: "SMS;+;chat123", identifier: "chat123", displayName: "the boys"),
        ])

        XCTAssertEqual(merged[0].displayName, "the boys")
    }
}
