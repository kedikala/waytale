import XCTest
import CoreLocation
@testable import IcelandTourGuide

final class BackendClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testAskPayloadIncludesGpsDayAndNativeContext() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = BackendClient(baseURLString: "https://example.test", session: session)
        let context = GuideContext(
            coordinate: CoordinatePoint(latitude: 63.4044, longitude: -19.0450),
            speedMetersPerSecond: 18,
            headingDegrees: 90,
            activeDayId: "2026-06-29",
            activeLeg: TripData.driveLegs[0],
            nearestPOIs: [TripData.pois[5]],
            nearestItineraryStop: TripData.itineraryStops[1]
        )
        var capturedBody: Data?

        MockURLProtocol.requestHandler = { request in
            capturedBody = request.httpBody
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"answer":"ok"}"#.utf8))
        }

        _ = try await client.ask(
            question: "What is interesting here?",
            coordinate: CLLocationCoordinate2D(latitude: 63.4044, longitude: -19.0450),
            dayId: "2026-06-29",
            context: context
        )

        let body = try XCTUnwrap(capturedBody)
        let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(object?["question"] as? String, "What is interesting here?")
        XCTAssertEqual(object?["dayId"] as? String, "2026-06-29")
        XCTAssertEqual(object?["lat"] as? Double, 63.4044)
        XCTAssertEqual(object?["lon"] as? Double, -19.0450)

        let nativeContext = try XCTUnwrap(object?["context"] as? [String: Any])
        XCTAssertEqual(nativeContext["activeDayId"] as? String, "2026-06-29")
        XCTAssertNotNil(nativeContext["nearestPOIs"])
        XCTAssertNotNil(nativeContext["activeLeg"])
    }
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: BackendError.invalidResponse)
            return
        }
        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
