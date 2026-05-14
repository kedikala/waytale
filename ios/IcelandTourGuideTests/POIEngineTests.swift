import XCTest
import CoreLocation
@testable import IcelandTourGuide

final class POIEngineTests: XCTestCase {
    func testFindsJokulsarlonNearby() {
        let engine = POIEngine()
        let location = CLLocation(latitude: 64.0473, longitude: -16.1791)
        let matches = engine.nearestPOIs(to: location, activeLeg: nil, limit: 3, includeSuppressed: true)
        XCTAssertTrue(matches.contains { $0.poi.id == "jokulsarlon-lagoon" })
    }

    func testMatchesSouthCoastLeg() {
        let engine = POIEngine()
        let location = CLLocation(latitude: 63.5321, longitude: -19.5114)
        let leg = engine.activeLeg(for: location, dayId: "2026-06-29")
        XCTAssertEqual(leg?.id, "d3-south-coast")
    }

    func testRepeatSuppression() {
        let engine = POIEngine()
        XCTAssertFalse(engine.isSuppressed(subjectId: "jokulsarlon-lagoon"))
        engine.markSpoken(subjectId: "jokulsarlon-lagoon")
        XCTAssertTrue(engine.isSuppressed(subjectId: "jokulsarlon-lagoon"))
    }
}
