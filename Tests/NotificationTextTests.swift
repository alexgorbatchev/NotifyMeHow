import XCTest
@testable import NotifyMeHow

final class NotificationTextTests: XCTestCase {

    func testTitleAndBodyWithoutSubtitleKeepTheirRoles() {
        var content = NotificationContent()
        content.assignTexts([
            NotificationText(identifier: "title", value: "Alex"),
            NotificationText(identifier: "body", value: "Short message.")
        ])

        XCTAssertEqual(content.title, "Alex")
        XCTAssertEqual(content.subtitle, "")
        XCTAssertEqual(content.body, "Short message.")
    }

    func testAllThreeRolesAreAssignedByIdentifier() {
        var content = NotificationContent()
        content.assignTexts([
            NotificationText(identifier: "body", value: "Body"),
            NotificationText(identifier: "subtitle", value: "Subtitle"),
            NotificationText(identifier: "title", value: "Title")
        ])

        XCTAssertEqual(content.title, "Title")
        XCTAssertEqual(content.subtitle, "Subtitle")
        XCTAssertEqual(content.body, "Body")
    }

    func testTextsWithoutIdentifiersFallBackToTheirOrder() {
        var content = NotificationContent()
        content.assignTexts([
            NotificationText(identifier: nil, value: "First"),
            NotificationText(identifier: nil, value: "Second"),
            NotificationText(identifier: nil, value: "Third")
        ])

        XCTAssertEqual(content.title, "First")
        XCTAssertEqual(content.subtitle, "Second")
        XCTAssertEqual(content.body, "Third")
    }
}
