import XCTest
@testable import NotifyMeHow

final class BannerMetricsTests: XCTestCase {

    private func makeConfig(scale: CGFloat) -> CustomNotificationConfig {
        var config = CustomNotificationConfig()
        config.scaleFactor = scale
        config.width = 344
        config.padding = 13
        config.iconSize = 32
        return config
    }

    func testTextColumnSitsBetweenTheIconAndTheCopyButton() {
        let metrics = BannerMetrics(config: makeConfig(scale: 1), hasIcon: true)

        XCTAssertEqual(metrics.textLeading, 58)  // padding 13 + icon 32 + gap 13
        // 344 wide minus both paddings (26), the icon and its gap (45), the copy button and its gap (28)
        XCTAssertEqual(metrics.textWidth, 245)
        XCTAssertEqual(metrics.minimumHeight, 58)  // icon 32 + padding above and below
    }

    func testEveryMetricScales() {
        let metrics = BannerMetrics(config: makeConfig(scale: 1.5), hasIcon: true)

        XCTAssertEqual(metrics.width, 516)
        XCTAssertEqual(metrics.iconSize, 48)
        XCTAssertEqual(metrics.textLeading, 87)  // 58 at scale 1
        XCTAssertEqual(metrics.lineSpacing, 3)
    }

    func testWithoutAnIconTheTextStartsAtThePadding() {
        let metrics = BannerMetrics(config: makeConfig(scale: 1), hasIcon: false)

        XCTAssertEqual(metrics.textLeading, 13)
        XCTAssertEqual(metrics.textWidth, 290)  // 344 minus paddings (26) and the copy button with its gap (28)
    }

    func testIconSizeIsAStyleSetting() throws {
        var style = NotificationStyle(name: "Icon")
        style.iconSize = 40

        let decoded = try JSONDecoder().decode(NotificationStyle.self, from: JSONEncoder().encode(style))
        let legacy = try JSONDecoder().decode(
            NotificationStyle.self, from: Data(#"{ "id": "12345678-1234-1234-1234-123456789ABC", "name": "Legacy" }"#.utf8))

        XCTAssertEqual(decoded.toConfig().iconSize, 40)
        XCTAssertEqual(legacy.iconSize, 24)
    }
}
