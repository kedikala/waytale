import Foundation
import CoreLocation
import CoreGraphics

struct POIMatch: Identifiable {
    let id: String
    let poi: POI
    let distanceMeters: CLLocationDistance
    let score: Double

    init(poi: POI, distanceMeters: CLLocationDistance, score: Double) {
        self.id = poi.id
        self.poi = poi
        self.distanceMeters = distanceMeters
        self.score = score
    }
}

final class POIEngine {
    private let pois: [POI]
    private let driveLegs: [DriveLeg]
    private let stops: [ItineraryStop]
    private var spokenMemory: [String: Date] = [:]
    private let repeatSuppressionInterval: TimeInterval = 60 * 60 * 8

    init(pois: [POI] = TripData.pois, driveLegs: [DriveLeg] = TripData.driveLegs, stops: [ItineraryStop] = TripData.itineraryStops) {
        self.pois = pois
        self.driveLegs = driveLegs
        self.stops = stops
    }

    func nearestPOIs(to location: CLLocation, activeLeg: DriveLeg?, limit: Int = 5, includeSuppressed: Bool = false) -> [POIMatch] {
        let routeTags = Set((activeLeg?.roadNumbers ?? []) + [activeLeg?.id, activeLeg?.dayId].compactMap { $0 })
        return pois.compactMap { poi in
            let poiLocation = CLLocation(latitude: poi.latitude, longitude: poi.longitude)
            let distance = location.distance(from: poiLocation)
            let onRoute = poi.routeTags.contains { routeTags.contains($0) }
            let effectiveRadius = onRoute ? poi.radiusMeters * 1.6 : poi.radiusMeters
            guard distance <= effectiveRadius else { return nil }
            guard includeSuppressed || !isSuppressed(subjectId: poi.id) else { return nil }
            let score = Double(poi.priority * 1000) + (onRoute ? 800 : 0) - distance / 20
            return POIMatch(poi: poi, distanceMeters: distance, score: score)
        }
        .sorted { $0.score > $1.score }
        .prefix(limit)
        .map { $0 }
    }

    func bestNarrationCandidate(location: CLLocation, activeLeg: DriveLeg?) -> POIMatch? {
        nearestPOIs(to: location, activeLeg: activeLeg, limit: 1).first
    }

    func poi(withID id: String) -> POI? {
        pois.first { $0.id == id }
    }

    func activeLeg(for location: CLLocation, dayId: String) -> DriveLeg? {
        let candidates = driveLegs.filter { $0.dayId == dayId }
        var bestLeg: DriveLeg?
        var bestDistance = CLLocationDistance.greatestFiniteMagnitude

        for leg in candidates {
            let distance = distanceToPolyline(location: location, points: leg.corridor)
            if distance <= 7000, distance < bestDistance {
                bestDistance = distance
                bestLeg = leg
            }
        }

        return bestLeg
    }

    func nearestItineraryStop(to location: CLLocation, dayId: String) -> ItineraryStop? {
        var nearestStop: ItineraryStop?
        var nearestDistance = CLLocationDistance.greatestFiniteMagnitude

        for stop in stops where stop.dayId == dayId {
            let stopLocation = CLLocation(latitude: stop.latitude, longitude: stop.longitude)
            let distance = location.distance(from: stopLocation)
            if distance < nearestDistance {
                nearestDistance = distance
                nearestStop = stop
            }
        }

        return nearestStop
    }

    func markSpoken(subjectId: String, at date: Date = Date()) {
        spokenMemory[subjectId] = date
    }

    func isSuppressed(subjectId: String, now: Date = Date()) -> Bool {
        guard let date = spokenMemory[subjectId] else { return false }
        return now.timeIntervalSince(date) < repeatSuppressionInterval
    }

    private func distanceToPolyline(location: CLLocation, points: [CoordinatePoint]) -> CLLocationDistance {
        guard points.count > 1 else {
            guard let first = points.first else { return .greatestFiniteMagnitude }
            return location.distance(from: CLLocation(latitude: first.latitude, longitude: first.longitude))
        }
        return zip(points, points.dropFirst())
            .map { distanceToSegment(location: location, start: $0.0, end: $0.1) }
            .min() ?? .greatestFiniteMagnitude
    }

    private func distanceToSegment(location: CLLocation, start: CoordinatePoint, end: CoordinatePoint) -> CLLocationDistance {
        let origin = CLLocationCoordinate2D(latitude: start.latitude, longitude: start.longitude)
        let point = project(location.coordinate, origin: origin)
        let endPoint = project(end.coordinate, origin: origin)
        let lengthSquared = endPoint.x * endPoint.x + endPoint.y * endPoint.y
        guard lengthSquared > 0 else {
            return location.distance(from: CLLocation(latitude: start.latitude, longitude: start.longitude))
        }
        let t = max(0, min(1, (point.x * endPoint.x + point.y * endPoint.y) / lengthSquared))
        let closest = CGPoint(x: endPoint.x * t, y: endPoint.y * t)
        return hypot(point.x - closest.x, point.y - closest.y)
    }

    private func project(_ coordinate: CLLocationCoordinate2D, origin: CLLocationCoordinate2D) -> CGPoint {
        let earthRadius = 6_371_000.0
        let x = degreesToRadians(coordinate.longitude - origin.longitude) * earthRadius * cos(degreesToRadians(origin.latitude))
        let y = degreesToRadians(coordinate.latitude - origin.latitude) * earthRadius
        return CGPoint(x: x, y: y)
    }

    private func degreesToRadians(_ value: Double) -> Double {
        value * .pi / 180
    }
}
