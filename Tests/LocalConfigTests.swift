import XCTest
@testable import NotifyMeHow

final class LocalConfigTests: XCTestCase {

    func testLocalConfigDecodesTheExportFormat() throws {
        let json = """
        {
            "version": 1,
            "settings": {
                "positionCorner": "topRight", "positionOffsetX": 20, "positionOffsetY": 20,
                "scaleFactor": 1, "autoStartMonitoring": true, "launchAtLogin": true
            },
            "styles": [{ "id": "12345678-1234-1234-1234-123456789ABC", "name": "Local", "width": 480 }],
            "rules": [],
            "defaultBehavior": "showCustom"
        }
        """

        let config = try Settings.decodeLocalConfig(Data(json.utf8))

        XCTAssertEqual(config.styles.map(\.name), ["Local"])
        XCTAssertEqual(config.styles.first?.width, 480)
        XCTAssertEqual(config.defaultBehavior, "showCustom")
    }

    func testLocalConfigRejectsTheLegacyFlatSettingsFormat() {
        let legacy = #"{ "positionCorner": "topRight", "scaleFactor": 1.5 }"#

        XCTAssertThrowsError(try Settings.decodeLocalConfig(Data(legacy.utf8)))
    }

    func testImagePathsExpandTheHomeDirectory() {
        XCTAssertEqual(
            NotificationStyle.resolvedImagePath("~/.config/notifymehow/slack.png"),
            NSHomeDirectory() + "/.config/notifymehow/slack.png"
        )
        XCTAssertEqual(NotificationStyle.resolvedImagePath("/absolute/icon.png"), "/absolute/icon.png")
    }
}
