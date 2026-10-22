import XCTest
@testable import NotifyMeHow

final class StyleInheritanceTests: XCTestCase {

    private let baseId = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private let childId = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
    private let grandchildId = UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!

    private func makeBase() -> NotificationStyle {
        var base = NotificationStyle(name: "Base")
        base.id = baseId
        base.titleFontSize = 14
        base.backgroundColorHex = "15181F"
        base.customIconPath = "~/base.png"
        return base
    }

    private func decodeStyle(_ json: String) throws -> NotificationStyle {
        return try JSONDecoder().decode(NotificationStyle.self, from: Data(json.utf8))
    }

    func testDerivedStyleInheritsUnsetFieldsAndKeepsItsOverrides() throws {
        let child = try decodeStyle("""
        { "id": "\(childId)", "name": "Child", "baseStyleId": "\(baseId)", "appColorHex": "85B8D5" }
        """)

        let resolved = NotificationStyle.resolved(child, in: [makeBase(), child])

        XCTAssertEqual(resolved.id, childId)
        XCTAssertEqual(resolved.name, "Child")
        XCTAssertEqual(resolved.appColorHex, "85B8D5")
        XCTAssertEqual(resolved.titleFontSize, 14)
        XCTAssertEqual(resolved.backgroundColorHex, "15181F")
        XCTAssertEqual(resolved.customIconPath, "~/base.png")
    }

    func testExplicitNullOverridesAnInheritedOptionalValue() throws {
        let child = try decodeStyle("""
        { "id": "\(childId)", "name": "Child", "baseStyleId": "\(baseId)", "customIconPath": null }
        """)

        XCTAssertNil(NotificationStyle.resolved(child, in: [makeBase(), child]).customIconPath)
    }

    func testInheritanceChainsThroughIntermediateStyles() throws {
        let child = try decodeStyle("""
        { "id": "\(childId)", "name": "Child", "baseStyleId": "\(baseId)", "titleFontSize": 18 }
        """)
        let grandchild = try decodeStyle("""
        { "id": "\(grandchildId)", "name": "Grandchild", "baseStyleId": "\(childId)", "bodyFontSize": 9 }
        """)

        let resolved = NotificationStyle.resolved(grandchild, in: [makeBase(), child, grandchild])

        XCTAssertEqual(resolved.bodyFontSize, 9)
        XCTAssertEqual(resolved.titleFontSize, 18)
        XCTAssertEqual(resolved.backgroundColorHex, "15181F")
    }

    func testCyclicBasesResolveWithoutLooping() throws {
        var first = try decodeStyle("""
        { "id": "\(baseId)", "name": "First", "baseStyleId": "\(childId)", "titleFontSize": 11 }
        """)
        first.baseStyleId = childId
        let second = try decodeStyle("""
        { "id": "\(childId)", "name": "Second", "baseStyleId": "\(baseId)", "bodyFontSize": 7 }
        """)

        let resolved = NotificationStyle.resolved(first, in: [first, second])

        XCTAssertEqual(resolved.titleFontSize, 11)
        XCTAssertEqual(resolved.bodyFontSize, 7)
    }

    func testDerivedStyleEncodesOnlyItsOverrides() throws {
        var child = NotificationStyle.resolved(makeBase(), in: [makeBase()])
        child.id = childId
        child.name = "Child"
        child.appColorHex = "85B8D5"
        child.customIconPath = nil
        child = child.inheriting(from: makeBase())

        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(child)) as! [String: Any]

        XCTAssertEqual(Set(json.keys), ["id", "name", "baseStyleId", "appColorHex", "customIconPath"])
        XCTAssertTrue(json["customIconPath"] is NSNull)
        XCTAssertEqual(json["baseStyleId"] as? String, baseId.uuidString)
    }

    func testFlatteningDependentsKeepsTheirResolvedAppearance() throws {
        let child = try decodeStyle("""
        { "id": "\(childId)", "name": "Child", "baseStyleId": "\(baseId)", "appColorHex": "85B8D5" }
        """)

        let remaining = StylesManager.removingStyle(withId: baseId, from: [makeBase(), child])

        XCTAssertEqual(remaining.count, 1)
        XCTAssertNil(remaining[0].baseStyleId)
        XCTAssertEqual(remaining[0].titleFontSize, 14)
        XCTAssertEqual(remaining[0].appColorHex, "85B8D5")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(remaining[0])) as! [String: Any]
        XCTAssertEqual(json["titleFontSize"] as? Double, 14)
    }

    func testBaseChainMembershipStopsAtCycles() throws {
        let child = try decodeStyle("""
        { "id": "\(childId)", "name": "Child", "baseStyleId": "\(baseId)" }
        """)
        var looping = makeBase()
        looping.baseStyleId = childId
        let styles = [makeBase(), child]

        XCTAssertTrue(NotificationStyle.inherits(child, from: baseId, in: styles))
        XCTAssertFalse(NotificationStyle.inherits(makeBase(), from: childId, in: styles))
        XCTAssertTrue(NotificationStyle.inherits(child, from: childId, in: [looping, child]))
    }

    func testExportDataCarriesTheDefaultStyle() throws {
        let settings = Settings.SettingsExport(
            positionCorner: "topRight", positionOffsetX: 20, positionOffsetY: 20,
            scaleFactor: 1, autoStartMonitoring: true, launchAtLogin: false)
        let export = Settings.ExportData(
            settings: settings, styles: [makeBase()], rules: [], defaultBehavior: "showCustom",
            defaultStyleId: baseId)

        let decoded = try JSONDecoder().decode(Settings.ExportData.self, from: JSONEncoder().encode(export))

        XCTAssertEqual(decoded.defaultStyleId, baseId)
    }
}
