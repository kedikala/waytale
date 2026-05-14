import Foundation
import CoreLocation
import UserNotifications

@MainActor
final class LocationManager: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var heading: CLHeading?
    @Published private(set) var errorMessage: String?
    @Published private(set) var enteredRegionIdentifier: String?
    @Published private(set) var demoLocationLabel: String?

    var onLocationUpdate: (() -> Void)?
    var onRegionEntry: ((String) -> Void)?

    private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 25
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
    }

    func requestPermissions() {
        DiagnosticLog.shared.record("location.permission", "request from \(authorizationLabel(manager.authorizationStatus))")
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    func startDriveModeLocation() {
        DiagnosticLog.shared.record("location", "start updates auth=\(authorizationLabel(manager.authorizationStatus))")
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
        manager.startMonitoringSignificantLocationChanges()
    }

    func stopDriveModeLocation() {
        DiagnosticLog.shared.record("location", "stop updates")
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        manager.stopMonitoringSignificantLocationChanges()
    }

    func stopGeofences() {
        let monitoredRegions = manager.monitoredRegions
        guard !monitoredRegions.isEmpty else { return }
        DiagnosticLog.shared.record("geofence", "stopping \(monitoredRegions.count) monitored regions")
        for region in monitoredRegions {
            manager.stopMonitoring(for: region)
        }
    }

    func useDemoLocation(_ demoLocation: DemoLocation) {
        DiagnosticLog.shared.record("location.demo", "\(demoLocation.label) \(String(format: "%.5f", demoLocation.latitude)),\(String(format: "%.5f", demoLocation.longitude))")
        demoLocationLabel = demoLocation.label
        currentLocation = CLLocation(
            coordinate: demoLocation.coordinate,
            altitude: 0,
            horizontalAccuracy: 8,
            verticalAccuracy: 8,
            course: -1,
            speed: 16,
            timestamp: Date()
        )
        errorMessage = nil
    }

    func clearDemoLocation() {
        DiagnosticLog.shared.record("location.demo", "clear demo location")
        demoLocationLabel = nil
        currentLocation = nil
        manager.requestLocation()
    }

    func configureGeofences(for pois: [POI]) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            DiagnosticLog.shared.record("geofence", "region monitoring unavailable")
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
        let maximumDistance = manager.maximumRegionMonitoringDistance > 0 ? manager.maximumRegionMonitoringDistance : 1000
        let monitoredPOIs = Array(pois.sorted(by: { $0.priority > $1.priority }).prefix(20))
        DiagnosticLog.shared.record("geofence", "monitoring \(monitoredPOIs.count) POIs maxRadius=\(Int(maximumDistance))")
        for poi in monitoredPOIs {
            let radius = min(max(poi.radiusMeters, 150), maximumDistance)
            let region = CLCircularRegion(center: poi.coordinate, radius: radius, identifier: poi.id)
            region.notifyOnEntry = true
            region.notifyOnExit = false
            manager.startMonitoring(for: region)
        }
    }

    private func authorizationLabel(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedAlways: return "always"
        case .authorizedWhenInUse: return "whenInUse"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown"
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            DiagnosticLog.shared.record("location.permission", "changed to \(authorizationLabel(manager.authorizationStatus))")
            if manager.authorizationStatus == .authorizedWhenInUse {
                manager.requestAlwaysAuthorization()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            guard demoLocationLabel == nil else { return }
            currentLocation = location
            DiagnosticLog.shared.record(
                "location.update",
                "\(String(format: "%.5f", location.coordinate.latitude)),\(String(format: "%.5f", location.coordinate.longitude)) accuracy=\(Int(location.horizontalAccuracy))m speed=\(String(format: "%.1f", location.speed))"
            )
            onLocationUpdate?()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            heading = newHeading
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            errorMessage = error.localizedDescription
            DiagnosticLog.shared.record("location.error", error.localizedDescription)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        manager.requestLocation()
        Task { @MainActor in
            enteredRegionIdentifier = region.identifier
            DiagnosticLog.shared.record("geofence.enter", region.identifier)
            onRegionEntry?(region.identifier)
        }
        let content = UNMutableNotificationContent()
        content.title = "Waytale location nearby"
        content.body = "Open Waytale for nearby narration."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "poi-\(region.identifier)-\(Date().timeIntervalSince1970)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
