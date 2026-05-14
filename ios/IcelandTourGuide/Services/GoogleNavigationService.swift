import Foundation
import CoreLocation

enum GoogleNavigationServiceError: LocalizedError {
    case missingAPIKey
    case destinationNotFound
    case routeNotFound
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Google Maps API key is missing"
        case .destinationNotFound:
            return "Destination not found"
        case .routeNotFound:
            return "No driving route found"
        case .invalidResponse(let message):
            return message
        }
    }
}

final class GoogleNavigationService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func autocomplete(query: String, origin: CLLocationCoordinate2D?, sessionToken: String) async throws -> [PlaceSuggestion] {
        guard let apiKey = AppConfiguration.googleMapsAPIKey else {
            throw GoogleNavigationServiceError.missingAPIKey
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.count >= 2 else { return [] }

        let url = URL(string: "https://places.googleapis.com/v1/places:autocomplete")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")

        let body = PlacesAutocompleteRequest(
            input: trimmedQuery,
            includedRegionCodes: ["is"],
            languageCode: "en-US",
            regionCode: "IS",
            locationBias: origin.map {
                PlacesLocationBias(
                    circle: PlacesCircle(
                        center: RouteLatLng(latitude: $0.latitude, longitude: $0.longitude),
                        radius: 75_000
                    )
                )
            },
            origin: origin.map { RouteLatLng(latitude: $0.latitude, longitude: $0.longitude) },
            includeQueryPredictions: true,
            sessionToken: sessionToken
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data, serviceName: "Places autocomplete")
        let payload = try JSONDecoder().decode(PlacesAutocompleteResponse.self, from: data)
        if let error = payload.error {
            throw GoogleNavigationServiceError.invalidResponse(error.message)
        }

        return (payload.suggestions ?? []).compactMap { suggestion in
            if let prediction = suggestion.placePrediction {
                return PlaceSuggestion(
                    id: prediction.placeId ?? prediction.place ?? UUID().uuidString,
                    title: prediction.structuredFormat?.mainText.text ?? prediction.text?.text ?? trimmedQuery,
                    subtitle: prediction.structuredFormat?.secondaryText?.text,
                    query: prediction.text?.text ?? trimmedQuery,
                    placeId: prediction.placeId,
                    types: prediction.types ?? [],
                    distanceMeters: prediction.distanceMeters,
                    primaryType: prediction.types?.first
                )
            }

            if let prediction = suggestion.queryPrediction {
                let text = prediction.text?.text ?? trimmedQuery
                return PlaceSuggestion(
                    id: text,
                    title: prediction.structuredFormat?.mainText.text ?? text,
                    subtitle: prediction.structuredFormat?.secondaryText?.text,
                    query: text,
                    placeId: nil,
                    types: [],
                    distanceMeters: nil,
                    primaryType: nil
                )
            }

            return nil
        }
        .sorted { Self.suggestionScore($0) < Self.suggestionScore($1) }
    }

    func destination(from suggestion: PlaceSuggestion, sessionToken: String? = nil) async throws -> NavigationDestination {
        if let placeId = suggestion.placeId {
            do {
                return try await placeDetails(placeId: placeId, fallbackTitle: suggestion.title, sessionToken: sessionToken)
            } catch {
                return try await geocodeDestination(query: suggestion.query)
            }
        }

        return try await geocodeDestination(query: suggestion.query)
    }

    func placeDetails(placeId: String, fallbackTitle: String, sessionToken: String? = nil) async throws -> NavigationDestination {
        guard let apiKey = AppConfiguration.googleMapsAPIKey else {
            throw GoogleNavigationServiceError.missingAPIKey
        }

        var components = URLComponents(string: "https://places.googleapis.com/v1/places/\(placeId)")
        var queryItems = [
            URLQueryItem(name: "languageCode", value: "en-US"),
            URLQueryItem(name: "regionCode", value: "IS")
        ]
        if let sessionToken {
            queryItems.append(URLQueryItem(name: "sessionToken", value: sessionToken))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw GoogleNavigationServiceError.destinationNotFound
        }

        var request = URLRequest(url: url)
        request.addValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.addValue("id,displayName,formattedAddress,location", forHTTPHeaderField: "X-Goog-FieldMask")

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data, serviceName: "Place details")
        let payload = try JSONDecoder().decode(PlaceDetailsResponse.self, from: data)
        if let error = payload.error {
            throw GoogleNavigationServiceError.invalidResponse(error.message)
        }
        guard let location = payload.location else {
            throw GoogleNavigationServiceError.destinationNotFound
        }

        return NavigationDestination(
            id: payload.id ?? placeId,
            title: payload.displayName?.text ?? fallbackTitle,
            address: payload.formattedAddress ?? fallbackTitle,
            latitude: location.latitude,
            longitude: location.longitude,
            placeId: payload.id ?? placeId
        )
    }

    func geocodeDestination(query: String) async throws -> NavigationDestination {
        guard let apiKey = AppConfiguration.googleMapsAPIKey else {
            throw GoogleNavigationServiceError.missingAPIKey
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw GoogleNavigationServiceError.destinationNotFound
        }

        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/geocode/json")
        components?.queryItems = [
            URLQueryItem(name: "address", value: trimmedQuery),
            URLQueryItem(name: "region", value: "is"),
            URLQueryItem(name: "key", value: apiKey)
        ]

        guard let url = components?.url else {
            throw GoogleNavigationServiceError.destinationNotFound
        }

        let (data, response) = try await session.data(from: url)
        try validateHTTPResponse(response, data: data, serviceName: "Geocoding")
        let payload = try JSONDecoder().decode(GeocodeResponse.self, from: data)
        guard payload.status == "OK", let result = payload.results?.first else {
            throw GoogleNavigationServiceError.invalidResponse(payload.errorMessage ?? payload.error?.message ?? "Destination not found")
        }

        let title = result.name
        let location = result.geometry.location
        return NavigationDestination(
            title: title,
            address: result.formattedAddress,
            latitude: location.lat,
            longitude: location.lng
        )
    }

    func route(origin: NavigationDestination?, originCoordinate: CLLocationCoordinate2D, destination: NavigationDestination) async throws -> NavigationRoute {
        do {
            return try await computeRoute(origin: origin, originCoordinate: originCoordinate, destination: destination, useTraffic: true)
        } catch GoogleNavigationServiceError.routeNotFound {
            return try await computeRoute(origin: origin, originCoordinate: originCoordinate, destination: destination, useTraffic: false)
        }
    }

    private func computeRoute(origin: NavigationDestination?, originCoordinate: CLLocationCoordinate2D, destination: NavigationDestination, useTraffic: Bool) async throws -> NavigationRoute {
        guard let apiKey = AppConfiguration.googleMapsAPIKey else {
            throw GoogleNavigationServiceError.missingAPIKey
        }

        let url = URL(string: "https://routes.googleapis.com/directions/v2:computeRoutes")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.addValue(
            [
                "routes.duration",
                "routes.distanceMeters",
                "routes.polyline.encodedPolyline",
                "routes.legs.steps.distanceMeters",
                "routes.legs.steps.staticDuration",
                "routes.legs.steps.polyline.encodedPolyline",
                "routes.legs.steps.navigationInstruction"
            ].joined(separator: ","),
            forHTTPHeaderField: "X-Goog-FieldMask"
        )

        let body = ComputeRoutesRequest(
            origin: RouteWaypoint(destination: origin, fallbackCoordinate: originCoordinate),
            destination: RouteWaypoint(destination: destination, fallbackCoordinate: destination.coordinate),
            travelMode: "DRIVE",
            routingPreference: useTraffic ? "TRAFFIC_AWARE" : nil,
            computeAlternativeRoutes: false,
            routeModifiers: useTraffic ? .init(avoidTolls: false, avoidHighways: false, avoidFerries: false) : nil,
            languageCode: "en-US",
            units: "METRIC",
            polylineQuality: "HIGH_QUALITY"
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data, serviceName: "Routes")
        let payload = try JSONDecoder().decode(ComputeRoutesResponse.self, from: data)
        if let error = payload.error {
            throw GoogleNavigationServiceError.invalidResponse(error.message)
        }
        guard let route = payload.routes?.first else {
            throw GoogleNavigationServiceError.routeNotFound
        }
        guard let encodedPolyline = route.polyline?.encodedPolyline, !encodedPolyline.isEmpty else {
            throw GoogleNavigationServiceError.invalidResponse("Google returned a route without map geometry")
        }
        let steps = (route.legs ?? [])
            .flatMap(\.steps)
            .compactMap { step -> NavigationStep? in
                guard let instruction = step.navigationInstruction?.instructions, !instruction.isEmpty else {
                    return nil
                }
                let stepPath = step.polyline.map { Self.decodePolyline($0.encodedPolyline) } ?? []
                return NavigationStep(
                    instruction: instruction,
                    maneuver: step.navigationInstruction?.maneuver,
                    distanceMeters: step.distanceMeters,
                    durationSeconds: step.staticDuration.flatMap(Self.seconds(from:)),
                    path: stepPath
                )
            }

        return NavigationRoute(
            destination: destination,
            distanceMeters: route.distanceMeters ?? 0,
            durationSeconds: route.duration.flatMap(Self.seconds(from:)) ?? 0,
            encodedPolyline: encodedPolyline,
            path: Self.decodePolyline(encodedPolyline),
            steps: steps
        )
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data, serviceName: String) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if let error = try? JSONDecoder().decode(GoogleAPIErrorEnvelope.self, from: data).error {
                throw GoogleNavigationServiceError.invalidResponse("\(serviceName) request failed: \(error.message)")
            }
            let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = body.map { ": \($0.prefix(180))" } ?? ""
            throw GoogleNavigationServiceError.invalidResponse("\(serviceName) request failed: HTTP \(httpResponse.statusCode)\(suffix)")
        }
    }

    private static func suggestionScore(_ suggestion: PlaceSuggestion) -> Int {
        let types = Set(suggestion.types)
        if types.contains("street_address") || types.contains("route") || types.contains("premise") {
            return 0
        }
        if types.contains("tourist_attraction") || types.contains("park") || types.contains("point_of_interest") || types.contains("establishment") {
            return 1
        }
        if types.contains("locality") || types.contains("administrative_area_level_1") {
            return 2
        }
        if types.contains("natural_feature") {
            return 3
        }
        return suggestion.placeId == nil ? 4 : 2
    }

    private static func seconds(from protobufDuration: String) -> Int? {
        guard protobufDuration.hasSuffix("s") else { return nil }
        let value = protobufDuration.dropLast()
        guard let seconds = Double(value) else { return nil }
        return Int(seconds.rounded())
    }

    private static func decodePolyline(_ encodedPolyline: String) -> [CoordinatePoint] {
        var coordinates: [CoordinatePoint] = []
        let scalars = Array(encodedPolyline.unicodeScalars).map { Int($0.value) }
        var index = 0
        var latitude = 0
        var longitude = 0

        while index < scalars.count {
            guard let decodedLatitude = decodeCoordinateDelta(scalars: scalars, index: &index),
                  let decodedLongitude = decodeCoordinateDelta(scalars: scalars, index: &index) else {
                break
            }
            latitude += decodedLatitude
            longitude += decodedLongitude
            coordinates.append(CoordinatePoint(latitude: Double(latitude) / 100_000, longitude: Double(longitude) / 100_000))
        }

        return coordinates
    }

    private static func decodeCoordinateDelta(scalars: [Int], index: inout Int) -> Int? {
        var result = 0
        var shift = 0
        var byte = 0

        repeat {
            guard index < scalars.count else { return nil }
            byte = scalars[index] - 63
            index += 1
            result |= (byte & 0x1f) << shift
            shift += 5
        } while byte >= 0x20

        return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
    }
}

private struct GeocodeResponse: Decodable {
    let status: String?
    let results: [GeocodeResult]?
    let errorMessage: String?
    let error: GoogleAPIError?

    enum CodingKeys: String, CodingKey {
        case status
        case results
        case error
        case errorMessage = "error_message"
    }
}

private struct PlacesAutocompleteRequest: Encodable {
    let input: String
    let includedRegionCodes: [String]
    let languageCode: String
    let regionCode: String
    let locationBias: PlacesLocationBias?
    let origin: RouteLatLng?
    let includeQueryPredictions: Bool
    let sessionToken: String
}

private struct PlacesLocationBias: Encodable {
    let circle: PlacesCircle
}

private struct PlacesCircle: Encodable {
    let center: RouteLatLng
    let radius: Double
}

private struct PlacesAutocompleteResponse: Decodable {
    let suggestions: [PlacesAutocompleteSuggestion]?
    let error: GoogleAPIError?
}

private struct PlacesAutocompleteSuggestion: Decodable {
    let placePrediction: PlacesPlacePrediction?
    let queryPrediction: PlacesQueryPrediction?
}

private struct PlacesPlacePrediction: Decodable {
    let place: String?
    let placeId: String?
    let text: PlacesText?
    let structuredFormat: PlacesStructuredFormat?
    let types: [String]?
    let distanceMeters: Double?
}

private struct PlacesQueryPrediction: Decodable {
    let text: PlacesText?
    let structuredFormat: PlacesStructuredFormat?
}

private struct PlacesStructuredFormat: Decodable {
    let mainText: PlacesText
    let secondaryText: PlacesText?
}

private struct PlacesText: Decodable {
    let text: String
}

private struct PlaceDetailsResponse: Decodable {
    let id: String?
    let displayName: PlacesText?
    let formattedAddress: String?
    let location: RouteLatLng?
    let error: GoogleAPIError?
}

private struct GeocodeResult: Decodable {
    let formattedAddress: String
    let geometry: GeocodeGeometry
    let addressComponents: [GeocodeAddressComponent]

    var name: String {
        addressComponents.first?.longName ?? formattedAddress
    }

    enum CodingKeys: String, CodingKey {
        case formattedAddress = "formatted_address"
        case geometry
        case addressComponents = "address_components"
    }
}

private struct GeocodeGeometry: Decodable {
    let location: GeocodeLocation
}

private struct GeocodeLocation: Decodable {
    let lat: Double
    let lng: Double
}

private struct GeocodeAddressComponent: Decodable {
    let longName: String

    enum CodingKeys: String, CodingKey {
        case longName = "long_name"
    }
}

private struct ComputeRoutesRequest: Encodable {
    let origin: RouteWaypoint
    let destination: RouteWaypoint
    let travelMode: String
    let routingPreference: String?
    let computeAlternativeRoutes: Bool
    let routeModifiers: RouteModifiers?
    let languageCode: String
    let units: String
    let polylineQuality: String
}

private struct RouteWaypoint: Encodable {
    let location: RouteLocation?
    let placeId: String?
    let address: String?

    init(destination: NavigationDestination?, fallbackCoordinate: CLLocationCoordinate2D) {
        if let placeId = destination?.placeId, !placeId.isEmpty {
            location = nil
            self.placeId = placeId
            address = nil
        } else {
            location = RouteLocation(latLng: RouteLatLng(latitude: fallbackCoordinate.latitude, longitude: fallbackCoordinate.longitude))
            placeId = nil
            address = nil
        }
    }
}

private struct RouteLocation: Encodable {
    let latLng: RouteLatLng
}

private struct RouteLatLng: Codable {
    let latitude: Double
    let longitude: Double
}

private struct RouteModifiers: Encodable {
    let avoidTolls: Bool
    let avoidHighways: Bool
    let avoidFerries: Bool
}

private struct ComputeRoutesResponse: Decodable {
    let routes: [ComputedRoute]?
    let error: GoogleAPIError?
}

private struct ComputedRoute: Decodable {
    let distanceMeters: Int?
    let duration: String?
    let polyline: RoutePolyline?
    let legs: [ComputedRouteLeg]?
}

private struct RoutePolyline: Decodable {
    let encodedPolyline: String
}

private struct ComputedRouteLeg: Decodable {
    let steps: [ComputedRouteStep]
}

private struct ComputedRouteStep: Decodable {
    let distanceMeters: Int?
    let staticDuration: String?
    let polyline: RoutePolyline?
    let navigationInstruction: RouteNavigationInstruction?
}

private struct RouteNavigationInstruction: Decodable {
    let maneuver: String?
    let instructions: String?
}

private struct GoogleAPIErrorEnvelope: Decodable {
    let error: GoogleAPIError
}

private struct GoogleAPIError: Decodable {
    let code: Int?
    let message: String
    let status: String?
}
