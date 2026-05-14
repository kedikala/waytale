import XCTest
@testable import IcelandTourGuide

final class NarrationCacheTests: XCTestCase {
    func testCacheStoresAndReturnsMatchingVersion() async throws {
        let cache = NarrationCache()
        let data = Data("audio".utf8)
        let subject = "test-\(UUID().uuidString)"
        let url = try await cache.store(audioData: data, subjectId: subject, textVersion: "v1", sourceContext: "test")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let hit = await cache.cachedAudioURL(subjectId: subject, textVersion: "v1")
        XCTAssertNotNil(hit)
        let miss = await cache.cachedAudioURL(subjectId: subject, textVersion: "v2")
        XCTAssertNil(miss)
    }
}
