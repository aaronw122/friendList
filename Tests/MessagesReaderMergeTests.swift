import XCTest
@testable import FriendList

final class MessagesReaderMergeTests: XCTestCase {
    private func row(rowid: Int64, guid: String, identifier: String,
                     display: String = "", msgCount: Int = 0, last: Int64 = 0) -> MessagesReader.ChatRow {
        MessagesReader.ChatRow(rowid: rowid, guid: guid, identifier: identifier,
                               display: display, msgCount: msgCount, last: last)
    }

    func testMergesRowsSharingChatIdentifier() {
        let merged = MessagesReader.mergeSiblings([
            row(rowid: 1, guid: "iMessage;+;chat123", identifier: "chat123", msgCount: 100, last: 50),
            row(rowid: 2, guid: "SMS;+;chat123", identifier: "chat123", msgCount: 40, last: 80),
        ])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].rowIDs, [1, 2])
        XCTAssertEqual(merged[0].msgCount, 140)
        XCTAssertEqual(merged[0].last, 80)
    }

    func testCanonicalGuidPrefersIMessageSibling() {
        let merged = MessagesReader.mergeSiblings([
            row(rowid: 2, guid: "SMS;+;chat123", identifier: "chat123"),
            row(rowid: 1, guid: "iMessage;+;chat123", identifier: "chat123"),
        ])

        XCTAssertEqual(merged[0].canonical.guid, "iMessage;+;chat123")
    }

    func testCanonicalGuidDeterministicWithoutIMessageSibling() {
        let merged = MessagesReader.mergeSiblings([
            row(rowid: 2, guid: "SMS;+;chat123", identifier: "chat123"),
            row(rowid: 1, guid: "RCS;+;chat123", identifier: "chat123"),
        ])

        XCTAssertEqual(merged[0].canonical.guid, "RCS;+;chat123")
    }

    func testDistinctIdentifiersStaySeparate() {
        let merged = MessagesReader.mergeSiblings([
            row(rowid: 1, guid: "iMessage;+;chatA", identifier: "chatA"),
            row(rowid: 2, guid: "iMessage;+;chatB", identifier: "chatB"),
        ])

        XCTAssertEqual(merged.count, 2)
    }

    func testEmptyIdentifierFallsBackToGuidKey() {
        let merged = MessagesReader.mergeSiblings([
            row(rowid: 1, guid: "iMessage;+;chatA", identifier: ""),
            row(rowid: 2, guid: "SMS;+;chatB", identifier: ""),
        ])

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.map(\.rowIDs), [[1], [2]])
    }

    func testDisplayNameFallsBackToNamedSibling() {
        let merged = MessagesReader.mergeSiblings([
            row(rowid: 1, guid: "iMessage;+;chat123", identifier: "chat123", display: ""),
            row(rowid: 2, guid: "SMS;+;chat123", identifier: "chat123", display: "the boys"),
        ])

        XCTAssertEqual(merged[0].display, "the boys")
    }
}
