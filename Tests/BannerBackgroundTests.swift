import XCTest
@testable import NotifyMeHow

final class BannerBackgroundTests: XCTestCase {

    func testStylesWithoutABackgroundSettingStaySolid() throws {
        let json = #"{ "id": "12345678-1234-1234-1234-123456789ABC", "name": "Legacy" }"#

        let style = try JSONDecoder().decode(NotificationStyle.self, from: Data(json.utf8))

        XCTAssertEqual(style.toConfig().background, .solid)
        XCTAssertEqual(style.toConfig().glassTintOpacity, 0)
    }

    func testGlassBackgroundAndTintReachTheConfig() throws {
        var style = NotificationStyle(name: "Glass")
        style.background = "clearGlass"
        style.glassTintOpacity = 0.4

        let decoded = try JSONDecoder().decode(NotificationStyle.self, from: JSONEncoder().encode(style))

        XCTAssertEqual(decoded.toConfig().background, .clearGlass)
        XCTAssertEqual(decoded.toConfig().glassTintOpacity, 0.4, accuracy: 0.0001)
    }

    func testUnknownBackgroundFallsBackToSolid() {
        var style = NotificationStyle(name: "Typo")
        style.background = "frosted"

        XCTAssertEqual(style.toConfig().background, .solid)
    }

    func testOnlyGlassBannersBlurWhileFading() {
        XCTAssertFalse(BannerBackground.solid.usesBlurTransition)
        if #available(macOS 26.0, *) {
            XCTAssertTrue(BannerBackground.glass.usesBlurTransition)
            XCTAssertTrue(BannerBackground.clearGlass.usesBlurTransition)
        } else {
            XCTAssertFalse(BannerBackground.glass.usesBlurTransition)
        }
    }

    func testDerivedStylesInheritTheBackground() {
        var base = NotificationStyle(name: "Base")
        base.background = "glass"
        base.glassTintOpacity = 0.3
        var child = NotificationStyle(name: "Child")
        child.titleFontSize = 30
        child = child.inheriting(from: base)
        child.overriddenFields = [.titleFontSize]

        let resolved = NotificationStyle.resolved(child, in: [base, child])

        XCTAssertEqual(resolved.background, "glass")
        XCTAssertEqual(resolved.glassTintOpacity, 0.3)
    }
}
