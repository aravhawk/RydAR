import XCTest
import Foundation
import SQLite3
@testable import RydAR

final class SimulatorFixtureTests: XCTestCase {
    func testGPXContainsExactBundledCurveAndUsesSharedSentence() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        // The Xcode test runner cannot always see the repo's fixtures folder. The contract still
        // runs from the command line, where `xcodebuild test` reads it.
        try XCTSkipUnless(
            FileManager.default.isReadableFile(atPath: root.appendingPathComponent("fixtures/old-wire-approach.expect.json").path),
            "fixtures/ is outside the test sandbox")
        let expected = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf:
            root.appendingPathComponent("fixtures/old-wire-approach.expect.json"))) as? [String: Any])
        XCTAssertEqual(expected["spoken_line"] as? String, spokenWarning)
        let curveID = try XCTUnwrap(expected["curve_id"] as? String)

        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(try BundledCurves.curvesURL().path,
                                      &database, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(database,
            "SELECT coordinates_json, quality_flags, closed_loop FROM curves WHERE id = ?", -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        // SQLITE_TRANSIENT copies the temporary Swift string into the bound statement.
        sqlite3_bind_text(statement, 1, curveID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        let text = String(cString: try XCTUnwrap(sqlite3_column_text(statement, 0)))
        XCTAssertEqual(String(cString: try XCTUnwrap(sqlite3_column_text(statement, 1))), "")
        XCTAssertEqual(sqlite3_column_int(statement, 2), 0)
        let coordinates = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[Double]])

        let parser = try XCTUnwrap(XMLParser(contentsOf: root.appendingPathComponent("fixtures/old-wire-approach.gpx")))
        let delegate = WaypointParser()
        parser.delegate = delegate
        XCTAssertTrue(parser.parse())
        XCTAssertEqual(delegate.points.count, expected["waypoints"] as? Int)
        XCTAssertEqual(Array(delegate.points.dropFirst(35).prefix(coordinates.count)), coordinates)
        XCTAssertEqual(PreviewCurves.samples.first?.coordinates,
                       coordinates.map { MapPoint(longitude: $0[0], latitude: $0[1]) })
    }
}

private final class WaypointParser: NSObject, XMLParserDelegate {
    var points: [[Double]] = []
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        guard elementName == "wpt", let lat = Double(attributeDict["lat"] ?? ""),
              let lon = Double(attributeDict["lon"] ?? "") else { return }
        points.append([lon, lat])
    }
}
