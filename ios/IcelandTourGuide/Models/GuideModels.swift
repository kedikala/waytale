import Foundation
import CoreLocation

enum POICategory: String, Codable, CaseIterable {
    case geology
    case volcano
    case glacier
    case waterfall
    case history
    case folklore
    case wildlife
    case drivingSafety
    case viewpoint
    case town
    case fuelLogistics
}

struct POI: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let category: POICategory
    let latitude: Double
    let longitude: Double
    let radiusMeters: CLLocationDistance
    let priority: Int
    let routeTags: [String]
    let narrationSeed: String
    let safetyNote: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct DriveLeg: Identifiable, Codable, Hashable {
    let id: String
    let dayId: String
    let label: String
    let roadNumbers: [String]
    let corridor: [CoordinatePoint]
    let summary: String
}

struct CoordinatePoint: Codable, Hashable {
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct DemoLocation: Identifiable, Hashable {
    let id: String
    let label: String
    let dayId: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct ItineraryStop: Identifiable, Codable, Hashable {
    let id: String
    let dayId: String
    let time: String
    let title: String
    let description: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct NavigationDestination: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let address: String
    let latitude: Double
    let longitude: Double
    let placeId: String?

    init(id: String = UUID().uuidString, title: String, address: String, latitude: Double, longitude: Double, placeId: String? = nil) {
        self.id = id
        self.title = title
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.placeId = placeId
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct PlaceSuggestion: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let query: String
    let placeId: String?
    let types: [String]
    let distanceMeters: Double?
    let primaryType: String?

    var displayText: String {
        [title, subtitle].compactMap { $0 }.joined(separator: ", ")
    }

    var formattedDistance: String? {
        guard let distanceMeters else { return nil }
        if distanceMeters >= 10_000 {
            return "\(Int((distanceMeters / 1_000).rounded())) km away"
        }
        if distanceMeters >= 1_000 {
            return String(format: "%.1f km away", distanceMeters / 1_000)
        }
        return "\(Int(distanceMeters.rounded())) m away"
    }

    var displaySubtitle: String? {
        [formattedDistance, subtitle].compactMap { $0 }.joined(separator: " - ").nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

struct NavigationRoute: Identifiable, Codable, Hashable {
    let id: String
    let destination: NavigationDestination
    let distanceMeters: Int
    let durationSeconds: Int
    let encodedPolyline: String
    let path: [CoordinatePoint]
    let steps: [NavigationStep]

    init(
        id: String = UUID().uuidString,
        destination: NavigationDestination,
        distanceMeters: Int,
        durationSeconds: Int,
        encodedPolyline: String,
        path: [CoordinatePoint],
        steps: [NavigationStep]
    ) {
        self.id = id
        self.destination = destination
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.encodedPolyline = encodedPolyline
        self.path = path
        self.steps = steps
    }
}

struct NavigationStep: Identifiable, Codable, Hashable {
    let id: String
    let instruction: String
    let maneuver: String?
    let distanceMeters: Int?
    let durationSeconds: Int?
    let path: [CoordinatePoint]

    init(
        id: String = UUID().uuidString,
        instruction: String,
        maneuver: String?,
        distanceMeters: Int?,
        durationSeconds: Int?,
        path: [CoordinatePoint] = []
    ) {
        self.id = id
        self.instruction = instruction
        self.maneuver = maneuver
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.path = path
    }
}

struct GuideContext: Codable {
    let coordinate: CoordinatePoint?
    let speedMetersPerSecond: Double?
    let headingDegrees: Double?
    let activeDayId: String
    let activeLeg: DriveLeg?
    let nearestPOIs: [POI]
    let nearestItineraryStop: ItineraryStop?
}

struct NarrationCacheItem: Codable, Identifiable {
    let id: String
    let subjectId: String
    let audioFileName: String
    let textVersion: String
    let generatedAt: Date
    let expiresAt: Date?
    let sourceContext: String
}

struct SpokenMemory: Codable {
    let subjectId: String
    let spokenAt: Date
}
