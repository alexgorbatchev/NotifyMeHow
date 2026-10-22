import XCTest
@testable import NotifyMeHow

final class BannerLayoutTests: XCTestCase {

    // MARK: - Style layout fields

    func testStyleWithoutLayoutFieldsDecodesToTheOriginalBannerMetrics() throws {
        let json = """
        { "id": "12345678-1234-1234-1234-123456789ABC", "name": "Legacy" }
        """

        let style = try JSONDecoder().decode(NotificationStyle.self, from: Data(json.utf8))

        XCTAssertEqual(style.width, 420)
        XCTAssertEqual(style.padding, 20)
        XCTAssertEqual(style.cornerRadius, 14)
        XCTAssertEqual(style.titleFontSize, 20)
        XCTAssertEqual(style.subtitleFontSize, 10)
        XCTAssertEqual(style.bodyFontSize, 12)
        XCTAssertEqual(style.hasShadow, true)
    }

    func testStyleLayoutFieldsRoundTripAndReachTheConfig() throws {
        var style = NotificationStyle(name: "Layout")
        style.width = 480
        style.padding = 16
        style.cornerRadius = 8
        style.titleFontSize = 14
        style.subtitleFontSize = 9
        style.bodyFontSize = 11
        style.hasShadow = false

        let decoded = try JSONDecoder().decode(NotificationStyle.self, from: JSONEncoder().encode(style))
        let config = decoded.toConfig()

        XCTAssertEqual(config.width, 480)
        XCTAssertEqual(config.padding, 16)
        XCTAssertEqual(config.cornerRadius, 8)
        XCTAssertEqual(config.titleFontSize, 14)
        XCTAssertEqual(config.subtitleFontSize, 9)
        XCTAssertEqual(config.bodyFontSize, 11)
        XCTAssertEqual(config.hasShadow, false)
    }

    // MARK: - Stack positioning

    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1050)

    func testBottomBannersStackUpwardFromTheBottomOffset() {
        let position = NotificationPosition(corner: .bottomCenter, offsetX: 0, offsetY: 16)

        let first = NotificationStackLayout.origin(
            for: CGSize(width: 600, height: 100), position: position, screenFrame: screen,
            precedingHeights: [], firstHeight: nil)
        let second = NotificationStackLayout.origin(
            for: CGSize(width: 600, height: 80), position: position, screenFrame: screen,
            precedingHeights: [100], firstHeight: 100)

        XCTAssertEqual(first, CGPoint(x: 660, y: 16))
        XCTAssertEqual(second, CGPoint(x: 660, y: 16 + 100 + NotificationStackLayout.gap))
    }

    func testTopBannersStackDownwardFromTheTopOffset() {
        let position = NotificationPosition(corner: .topRight, offsetX: 20, offsetY: 20)

        let second = NotificationStackLayout.origin(
            for: CGSize(width: 400, height: 100), position: position, screenFrame: screen,
            precedingHeights: [120], firstHeight: 120)

        XCTAssertEqual(second, CGPoint(x: 1500, y: 1050 - 20 - 100 - 120 - NotificationStackLayout.gap))
    }

    func testBannersAreClampedInsideTheScreen() {
        let position = NotificationPosition(corner: .bottomLeft, offsetX: 0, offsetY: 0)

        let origin = NotificationStackLayout.origin(
            for: CGSize(width: 400, height: 500), position: position, screenFrame: screen,
            precedingHeights: [500, 500], firstHeight: 500)

        XCTAssertEqual(origin.y, 1050 - 500)
    }
}
