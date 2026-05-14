import Foundation
import AVFoundation
import CoreLocation
import UserNotifications

enum PlaceSearchField: Sendable {
    case origin
    case destination
}

@MainActor
final class TourGuideViewModel: ObservableObject {
    @Published var activeDayId = TripData.defaultDayId
    @Published private(set) var isDriveModeActive = false
    @Published private(set) var currentMatch: POIMatch?
    @Published private(set) var activeLeg: DriveLeg?
    @Published private(set) var nearestStop: ItineraryStop?
    @Published private(set) var statusMessage = "Ready"
    @Published private(set) var poiDebugMessage = "No POI evaluation yet"
    @Published private(set) var isPreparingNarration = false
    @Published private(set) var isAnsweringQuestion = false
    @Published private(set) var autoNarrationEnabled: Bool
    @Published private(set) var selectedDestination: NavigationDestination?
    @Published private(set) var selectedOrigin: NavigationDestination?
    @Published private(set) var activeRoute: NavigationRoute?
    @Published private(set) var routeStatusMessage = "Set a destination"
    @Published private(set) var isRouting = false
    @Published private(set) var isNavigating = false
    @Published private(set) var navigationVoiceGuidanceEnabled: Bool
    @Published private(set) var originSuggestions: [PlaceSuggestion] = []
    @Published private(set) var destinationSuggestions: [PlaceSuggestion] = []
    @Published private(set) var isLoadingOriginSuggestions = false
    @Published private(set) var isLoadingDestinationSuggestions = false

    let locationManager: LocationManager
    let audioGuide: AudioGuideService
    let voiceQuestionService: VoiceQuestionService
    let realtimeGuideService: RealtimeGuideService
    let demoLocations = TripData.demoLocations

    private let poiEngine: POIEngine
    private let backend: BackendClient
    private let cache: NarrationCache
    private let navigationService: GoogleNavigationService
    private var locationTask: Task<Void, Never>?
    private var realtimeStartTask: Task<Void, Never>?
    private var routeTask: Task<Void, Never>?
    private var originAutocompleteTask: Task<Void, Never>?
    private var destinationAutocompleteTask: Task<Void, Never>?
    private var locationUpdateEvaluationTask: Task<Void, Never>?
    private var regionNarrationTask: Task<Void, Never>?
    private var originAutocompleteSessionToken = UUID().uuidString
    private var destinationAutocompleteSessionToken = UUID().uuidString
    private var lastRouteRefreshLocation: CLLocation?
    private var lastRouteRefreshAt: Date?
    private var navigationVoiceTask: Task<Void, Never>?
    private var spokenNavigationInstructionKeys = Set<String>()
    private var lastNavigationVoicePromptAt: Date?
    private var lastLoggedPOIDebugMessage: String?
    private var narrationInterruptionToken = 0
    private var pendingSpokenPOIByPlaybackTitle: [String: String] = [:]
    private var skippablePOIByPlaybackTitle: [String: String] = [:]

    init() {
        let locationManager = LocationManager()
        let audioGuide = AudioGuideService()
        let backend = BackendClient()
        let poiEngine = POIEngine()
        let cache = NarrationCache()
        #if targetEnvironment(simulator)
        let autoNarrationEnabled = false
        #else
        let autoNarrationEnabled = true
        #endif
        let navigationVoiceGuidanceEnabled = UserDefaults.standard.object(forKey: "waytale.navigationVoiceGuidanceEnabled") as? Bool ?? false

        self.locationManager = locationManager
        self.audioGuide = audioGuide
        self.backend = backend
        self.poiEngine = poiEngine
        self.cache = cache
        self.navigationService = GoogleNavigationService()
        self.autoNarrationEnabled = autoNarrationEnabled
        self.navigationVoiceGuidanceEnabled = navigationVoiceGuidanceEnabled
        self.voiceQuestionService = VoiceQuestionService(backend: backend, audioGuide: audioGuide)
        self.realtimeGuideService = RealtimeGuideService(backend: backend)
        self.audioGuide.onPlaybackFinished = { [weak self] title in
            guard let self else { return }
            self.skippablePOIByPlaybackTitle.removeValue(forKey: title)
            guard let poiId = self.pendingSpokenPOIByPlaybackTitle.removeValue(forKey: title) else { return }
            self.poiEngine.markSpoken(subjectId: poiId)
            DiagnosticLog.shared.record("poi.narration", "marked spoken after playback \(title)")
        }
        self.audioGuide.onPlaybackFailed = { [weak self] title, error in
            guard let self else { return }
            self.skippablePOIByPlaybackTitle.removeValue(forKey: title)
            if self.pendingSpokenPOIByPlaybackTitle.removeValue(forKey: title) != nil {
                DiagnosticLog.shared.record("poi.narration", "not marking spoken after failed playback \(title): \(error?.localizedDescription ?? "unknown")")
            }
        }
        self.realtimeGuideService.onSessionEnded = { [weak self] in
            guard let self else { return }
            self.isAnsweringQuestion = false
            self.statusMessage = "Realtime guide session ended"
            DiagnosticLog.shared.record("realtime", "session ended callback")
        }
        self.locationManager.onLocationUpdate = { [weak self] in
            self?.scheduleLocationUpdateEvaluation()
        }
        self.locationManager.onRegionEntry = { [weak self] identifier in
            self?.handleRegionEntry(identifier)
        }
    }

    func activateAlwaysOnGuideIfNeeded() {
        if isDriveModeActive { return }
        startDriveMode()
    }

    func startDriveMode() {
        guard !isDriveModeActive else { return }
        isDriveModeActive = true
        statusMessage = autoNarrationEnabled ? "Drive Mode active" : "Drive Mode active; Auto POI paused"
        DiagnosticLog.shared.record("guide", "start drive mode autoPOI=\(autoNarrationEnabled)")
        locationManager.requestPermissions()
        locationManager.configureGeofences(for: TripData.pois)
        locationManager.startDriveModeLocation()
        locationTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.evaluateCurrentLocation()
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
    }

    func stopDriveMode() {
        isDriveModeActive = false
        isNavigating = false
        statusMessage = "Drive Mode stopped"
        DiagnosticLog.shared.record("guide", "stop drive mode")
        locationTask?.cancel()
        locationTask = nil
        realtimeStartTask?.cancel()
        realtimeStartTask = nil
        locationUpdateEvaluationTask?.cancel()
        locationUpdateEvaluationTask = nil
        regionNarrationTask?.cancel()
        regionNarrationTask = nil
        isAnsweringQuestion = false
        narrationInterruptionToken += 1
        locationManager.stopDriveModeLocation()
        locationManager.stopGeofences()
        realtimeGuideService.endSession(reason: "drive mode stopped")
        audioGuide.stop()
    }

    func suspendGuideServicesForBackground() {
        guard isDriveModeActive else { return }
        DiagnosticLog.shared.record("guide", "suspend guide services for background")
        isDriveModeActive = false
        statusMessage = "Guide paused in background"
        locationTask?.cancel()
        locationTask = nil
        realtimeStartTask?.cancel()
        realtimeStartTask = nil
        locationUpdateEvaluationTask?.cancel()
        locationUpdateEvaluationTask = nil
        regionNarrationTask?.cancel()
        regionNarrationTask = nil
        isAnsweringQuestion = false
        narrationInterruptionToken += 1
        locationManager.stopDriveModeLocation()
        locationManager.stopGeofences()
        realtimeGuideService.endSession(reason: "guide background suspend")
        audioGuide.stop()
    }

    func searchDestination(_ query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            routeStatusMessage = "Enter a destination"
            DiagnosticLog.shared.record("route", "empty destination search")
            return
        }
        DiagnosticLog.shared.record("route", "search destination '\(trimmedQuery)'")
        routeTask?.cancel()
        routeTask = Task { [weak self] in
            guard let self else { return }
            await self.loadDestinationAndRoute(query: trimmedQuery)
        }
    }

    func searchOrigin(_ query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            setOriginToCurrentLocation()
            return
        }
        DiagnosticLog.shared.record("route", "search origin '\(trimmedQuery)'")
        routeTask?.cancel()
        routeTask = Task { [weak self] in
            guard let self else { return }
            await self.loadOrigin(query: trimmedQuery)
        }
    }

    func updateAutocomplete(query: String, field: PlaceSearchField) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.count < 2 {
            clearSuggestions(for: field)
            return
        }

        let sessionToken = autocompleteSessionToken(for: field)
        switch field {
        case .origin:
            originAutocompleteTask?.cancel()
            isLoadingOriginSuggestions = true
            originAutocompleteTask = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: 260_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self?.loadAutocomplete(query: trimmedQuery, field: field, sessionToken: sessionToken)
            }
        case .destination:
            destinationAutocompleteTask?.cancel()
            isLoadingDestinationSuggestions = true
            destinationAutocompleteTask = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: 260_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self?.loadAutocomplete(query: trimmedQuery, field: field, sessionToken: sessionToken)
            }
        }
    }

    func setDestination(_ destination: NavigationDestination) {
        DiagnosticLog.shared.record("route", "set destination \(destination.title) \(String(format: "%.5f", destination.latitude)),\(String(format: "%.5f", destination.longitude))")
        routeTask?.cancel()
        selectedDestination = destination
        activeRoute = nil
        resetNavigationVoiceProgress()
        routeStatusMessage = "Routing to \(destination.title)..."
        routeTask = Task { [weak self] in
            guard let self else { return }
            await self.loadRoute(to: destination)
        }
    }

    func setDestination(_ stop: ItineraryStop) {
        let destination = NavigationDestination(
            id: stop.id,
            title: stop.title,
            address: stop.description,
            latitude: stop.latitude,
            longitude: stop.longitude
        )
        activeDayId = stop.dayId
        setDestination(destination)
    }

    func selectDestinationSuggestion(_ suggestion: PlaceSuggestion) {
        destinationAutocompleteTask?.cancel()
        destinationSuggestions = []
        routeTask?.cancel()
        routeTask = Task { [weak self] in
            guard let self else { return }
            await self.loadDestinationAndRoute(suggestion: suggestion)
        }
    }

    func selectOriginSuggestion(_ suggestion: PlaceSuggestion) {
        originAutocompleteTask?.cancel()
        originSuggestions = []
        routeTask?.cancel()
        routeTask = Task { [weak self] in
            guard let self else { return }
            await self.loadOrigin(suggestion: suggestion)
        }
    }

    func setOriginToCurrentLocation() {
        selectedOrigin = nil
        originSuggestions = []
        originAutocompleteTask?.cancel()
        originAutocompleteSessionToken = UUID().uuidString
        routeStatusMessage = selectedDestination.map { "Routing to \($0.title) from current location..." } ?? "Using current location"
        if let selectedDestination {
            setDestination(selectedDestination)
        }
    }

    func startNavigation() {
        guard let selectedDestination else {
            routeStatusMessage = "Set a destination first"
            DiagnosticLog.shared.record("navigation", "start failed: no destination")
            return
        }
        if !isDriveModeActive {
            startDriveMode()
        }
        isNavigating = true
        DiagnosticLog.shared.record("navigation", "start to \(selectedDestination.title)")
        realtimeGuideService.navigationStateDidChange(isNavigating: true, context: currentContext())
        routeStatusMessage = activeRoute.map { "Navigating \($0.formattedDistance) to \(selectedDestination.title)" } ?? "Starting route..."
        scheduleNavigationVoicePromptIfNeeded(location: locationManager.currentLocation)
        if activeRoute == nil {
            setDestination(selectedDestination)
        }
    }

    func stopNavigation() {
        isNavigating = false
        DiagnosticLog.shared.record("navigation", "stop")
        resetNavigationVoiceProgress()
        realtimeGuideService.navigationStateDidChange(isNavigating: false, context: currentContext())
        routeStatusMessage = selectedDestination.map { "Route ready to \($0.title)" } ?? "Set a destination"
    }

    func clearDestination() {
        DiagnosticLog.shared.record("route", "clear destination")
        routeTask?.cancel()
        routeTask = nil
        isRouting = false
        isNavigating = false
        selectedDestination = nil
        activeRoute = nil
        destinationSuggestions = []
        destinationAutocompleteTask?.cancel()
        destinationAutocompleteSessionToken = UUID().uuidString
        resetNavigationVoiceProgress()
        lastRouteRefreshLocation = nil
        lastRouteRefreshAt = nil
        routeStatusMessage = "Set a destination"
    }

    func setNavigationVoiceGuidanceEnabled(_ enabled: Bool) {
        navigationVoiceGuidanceEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "waytale.navigationVoiceGuidanceEnabled")
        DiagnosticLog.shared.record("navigation", "voice guidance \(enabled ? "enabled" : "disabled")")
        if !enabled {
            navigationVoiceTask?.cancel()
            navigationVoiceTask = nil
            if audioGuide.isPlaying, audioGuide.nowPlayingTitle == "Navigation" {
                audioGuide.stop()
            }
        } else {
            scheduleNavigationVoicePromptIfNeeded(location: locationManager.currentLocation)
        }
    }

    func askGuideButtonTapped() {
        if realtimeGuideService.isSessionActive {
            endRealtimeConversation()
            return
        }
        if !isDriveModeActive {
            startDriveMode()
        }
        DiagnosticLog.shared.record("realtime", "ask button tapped")
        startRealtimeConversation(initialQuestion: nil)
    }

    func legacyAskGuideButtonTapped() {
        if voiceQuestionService.isRecordingQuestion {
            Task {
                beginQuestionInterruption(status: "Answering question...")
                defer { finishQuestionInterruption() }
                await voiceQuestionService.stopAndAnswerRecordedQuestion(context: currentContext())
                if isDriveModeActive, audioGuide.isPlaying {
                    statusMessage = "Playing answer"
                }
            }
        } else {
            do {
                try voiceQuestionService.recordQuestion()
                statusMessage = "Recording question..."
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func playCurrentNarrationNow() {
        guard let match = currentMatch else {
            statusMessage = "No important POI nearby"
            DiagnosticLog.shared.record("poi.manual", "play requested but no current match")
            return
        }
        DiagnosticLog.shared.record("poi.manual", "play \(match.poi.name) distance=\(Int(match.distanceMeters))m")
        Task { await playNarration(for: match, force: true) }
    }

    func stopCurrentNarration() {
        guard audioGuide.isPlaying || isPreparingNarration else {
            statusMessage = "No narration playing"
            DiagnosticLog.shared.record("audio.stop", "skip requested but no Waytale audio")
            return
        }

        narrationInterruptionToken += 1
        if let title = audioGuide.nowPlayingTitle,
           let poiId = skippablePOIByPlaybackTitle[title] {
            poiEngine.markSpoken(subjectId: poiId)
            pendingSpokenPOIByPlaybackTitle = pendingSpokenPOIByPlaybackTitle.filter { $0.value != poiId }
            skippablePOIByPlaybackTitle = skippablePOIByPlaybackTitle.filter { $0.value != poiId }
            DiagnosticLog.shared.record("poi.skip", "user skipped \(title)")
            statusMessage = "Skipped narration"
        } else {
            DiagnosticLog.shared.record("audio.stop", "user stopped \(audioGuide.nowPlayingTitle ?? "Waytale audio")")
            statusMessage = "Stopped audio"
        }
        audioGuide.stop()
    }

    func toggleAutoNarration() {
        autoNarrationEnabled.toggle()
        statusMessage = autoNarrationEnabled ? "Auto POI narration enabled" : "Auto POI narration paused"
        DiagnosticLog.shared.record("poi.auto", "set \(autoNarrationEnabled)")
        if !autoNarrationEnabled {
            narrationInterruptionToken += 1
        }
    }

    func precacheToday() {
        guard let location = locationManager.currentLocation else {
            statusMessage = "Start GPS before pre-caching nearby narration"
            DiagnosticLog.shared.record("poi.cache", "skipped: no GPS")
            return
        }
        let leg = poiEngine.activeLeg(for: location, dayId: activeDayId)
        let matches = poiEngine.nearestPOIs(to: location, activeLeg: leg, limit: 5, includeSuppressed: true)
        Task {
            for match in matches {
                await ensureNarrationCached(for: match)
            }
            statusMessage = "Cached nearby narration"
            DiagnosticLog.shared.record("poi.cache", "cached \(matches.count) nearby narrations")
        }
    }

    func useDemoLocation(_ demoLocation: DemoLocation) {
        activeDayId = demoLocation.dayId
        locationManager.useDemoLocation(demoLocation)
        statusMessage = "Demo GPS: \(demoLocation.label)"
        Task { await evaluateCurrentLocation() }
    }

    func clearDemoLocation() {
        locationManager.clearDemoLocation()
        statusMessage = "Using simulator/device GPS"
    }

    private func evaluateCurrentLocation() async {
        guard isDriveModeActive else {
            poiDebugMessage = "POI check skipped: guide inactive"
            logPOIDebugIfNeeded()
            return
        }
        guard let location = locationManager.currentLocation else {
            poiDebugMessage = "POI check skipped: waiting for GPS"
            logPOIDebugIfNeeded()
            return
        }
        let leg = poiEngine.activeLeg(for: location, dayId: activeDayId)
        activeLeg = leg
        nearestStop = poiEngine.nearestItineraryStop(to: location, dayId: activeDayId)
        currentMatch = poiEngine.bestNarrationCandidate(location: location, activeLeg: leg)
        updatePOIDebugMessage(location: location, activeLeg: leg)

        if autoNarrationEnabled,
           !isAnsweringQuestion,
           !isPreparingNarration,
           !realtimeGuideService.isSessionActive,
           let match = currentMatch {
            guard !audioGuide.isPlaying else {
                return
            }
            DiagnosticLog.shared.record("poi.candidate", "\(match.poi.name) distance=\(Int(match.distanceMeters))m score=\(Int(match.score))")
            await playNarration(for: match, force: false)
            return
        }

        await refreshNavigationRouteIfNeeded(from: location)
        scheduleNavigationVoicePromptIfNeeded(location: location)
    }

    private func scheduleLocationUpdateEvaluation(regionIdentifier: String? = nil) {
        guard isDriveModeActive else { return }
        if let regionIdentifier {
            DiagnosticLog.shared.record("poi.evaluate", "scheduled from region \(regionIdentifier)")
        }
        locationUpdateEvaluationTask?.cancel()
        locationUpdateEvaluationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.locationUpdateEvaluationTask = nil
            guard self.isDriveModeActive else { return }
            if let regionIdentifier {
                self.poiDebugMessage = "Region entered: \(regionIdentifier). Checking nearby POIs..."
                self.logPOIDebugIfNeeded()
            }
            await self.evaluateCurrentLocation()
        }
    }

    private func handleRegionEntry(_ identifier: String) {
        guard isDriveModeActive else { return }
        poiDebugMessage = "Region entered: \(identifier). Preparing direct POI check..."
        logPOIDebugIfNeeded()
        DiagnosticLog.shared.record("geofence.enter", "view model handling \(identifier)")
        regionNarrationTask?.cancel()
        regionNarrationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if !Task.isCancelled {
                    self.regionNarrationTask = nil
                }
            }
            await self.playRegionNarrationIfPossible(identifier)
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard !Task.isCancelled else { return }
            await self.evaluateCurrentLocation()
        }
    }

    private func playRegionNarrationIfPossible(_ identifier: String) async {
        guard autoNarrationEnabled else {
            poiDebugMessage = "Region entered: \(identifier). Auto POI is paused."
            logPOIDebugIfNeeded()
            return
        }
        guard !isAnsweringQuestion, !isPreparingNarration, !realtimeGuideService.isSessionActive else {
            poiDebugMessage = "Region entered: \(identifier). Waiting for current audio session to finish."
            logPOIDebugIfNeeded()
            return
        }
        guard let poi = poiEngine.poi(withID: identifier) else {
            poiDebugMessage = "Region entered: \(identifier). No matching POI data."
            logPOIDebugIfNeeded()
            return
        }

        let distance = locationManager.currentLocation.map {
            $0.distance(from: CLLocation(latitude: poi.latitude, longitude: poi.longitude))
        } ?? 0
        let match = POIMatch(poi: poi, distanceMeters: distance, score: Double(poi.priority * 1000))

        guard !audioGuide.isPlaying else {
            poiDebugMessage = "Region entered: \(poi.name). Waytale audio is already playing."
            logPOIDebugIfNeeded()
            return
        }
        DiagnosticLog.shared.record("poi.region", "play \(poi.name) distance=\(Int(distance))m")
        await playNarration(for: match, force: false)
    }

    private func loadDestinationAndRoute(query: String) async {
        isRouting = true
        routeStatusMessage = "Finding \(query)..."
        defer { isRouting = false }
        do {
            let destination = try await navigationService.geocodeDestination(query: query)
            guard !Task.isCancelled else { return }
            selectedDestination = destination
            resetNavigationVoiceProgress()
            routeStatusMessage = "Routing to \(destination.title)..."
            try await loadRouteData(to: destination)
        } catch {
            guard !Task.isCancelled else { return }
            activeRoute = nil
            routeStatusMessage = error.localizedDescription
            DiagnosticLog.shared.record("route.error", error.localizedDescription)
        }
    }

    private func loadDestinationAndRoute(suggestion: PlaceSuggestion) async {
        isRouting = true
        routeStatusMessage = "Routing to \(suggestion.title)..."
        defer {
            isRouting = false
            destinationAutocompleteSessionToken = UUID().uuidString
        }
        do {
            let destination = try await navigationService.destination(from: suggestion, sessionToken: destinationAutocompleteSessionToken)
            guard !Task.isCancelled else { return }
            selectedDestination = destination
            resetNavigationVoiceProgress()
            try await loadRouteData(to: destination)
        } catch {
            guard !Task.isCancelled else { return }
            activeRoute = nil
            routeStatusMessage = error.localizedDescription
            DiagnosticLog.shared.record("route.error", error.localizedDescription)
        }
    }

    private func loadOrigin(query: String) async {
        isRouting = true
        routeStatusMessage = "Finding start point..."
        defer { isRouting = false }
        do {
            let origin = try await navigationService.geocodeDestination(query: query)
            guard !Task.isCancelled else { return }
            selectedOrigin = origin
            routeStatusMessage = selectedDestination.map { "Routing to \($0.title)..." } ?? "Start point set"
            if let selectedDestination {
                try await loadRouteData(to: selectedDestination)
            }
        } catch {
            guard !Task.isCancelled else { return }
            routeStatusMessage = error.localizedDescription
            DiagnosticLog.shared.record("route.error", error.localizedDescription)
        }
    }

    private func loadOrigin(suggestion: PlaceSuggestion) async {
        isRouting = true
        routeStatusMessage = "Setting start point..."
        defer {
            isRouting = false
            originAutocompleteSessionToken = UUID().uuidString
        }
        do {
            let origin = try await navigationService.destination(from: suggestion, sessionToken: originAutocompleteSessionToken)
            guard !Task.isCancelled else { return }
            selectedOrigin = origin
            routeStatusMessage = selectedDestination.map { "Routing to \($0.title)..." } ?? "Start point set"
            if let selectedDestination {
                try await loadRouteData(to: selectedDestination)
            }
        } catch {
            guard !Task.isCancelled else { return }
            routeStatusMessage = error.localizedDescription
            DiagnosticLog.shared.record("route.error", error.localizedDescription)
        }
    }

    private func loadRoute(to destination: NavigationDestination) async {
        isRouting = true
        defer { isRouting = false }
        do {
            try await loadRouteData(to: destination)
        } catch {
            guard !Task.isCancelled else { return }
            activeRoute = nil
            routeStatusMessage = error.localizedDescription
            DiagnosticLog.shared.record("route.error", error.localizedDescription)
        }
    }

    private func loadRouteData(to destination: NavigationDestination) async throws {
        guard let origin = routeOrigin(for: destination) else {
            routeStatusMessage = "Waiting for GPS before routing"
            DiagnosticLog.shared.record("route", "waiting for GPS before routing to \(destination.title)")
            locationManager.requestPermissions()
            locationManager.startDriveModeLocation()
            return
        }
        do {
            let route = try await navigationService.route(origin: selectedOrigin, originCoordinate: origin, destination: destination)
            applyRoute(route, origin: origin)
        } catch GoogleNavigationServiceError.routeNotFound {
            activeRoute = nil
            routeStatusMessage = noRouteMessage(to: destination)
            DiagnosticLog.shared.record("route.error", routeStatusMessage)
        }
    }

    private func noRouteMessage(to destination: NavigationDestination) -> String {
        if selectedOrigin != nil {
            return "No driving route found between selected locations"
        }
        if let currentLocation = locationManager.currentLocation {
            let destinationLocation = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
            if currentLocation.distance(from: destinationLocation) > 450_000 {
                return "Current GPS is too far from this Iceland route. Choose a From location in Iceland."
            }
        }
        return "No driving route found"
    }

    private func routeOrigin(for destination: NavigationDestination) -> CLLocationCoordinate2D? {
        if let selectedOrigin {
            return selectedOrigin.coordinate
        }

        if let currentLocation = locationManager.currentLocation {
            let destinationLocation = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
            if currentLocation.distance(from: destinationLocation) <= 450_000 {
                return currentLocation.coordinate
            }
        }

        return activeLeg?.corridor.first?.coordinate ?? locationManager.currentLocation?.coordinate
    }

    private func applyRoute(_ route: NavigationRoute, origin: CLLocationCoordinate2D) {
        guard !Task.isCancelled else { return }
        activeRoute = route
        lastRouteRefreshLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        lastRouteRefreshAt = Date()
        routeStatusMessage = "\(route.formattedDistance) · \(route.formattedDuration)"
        DiagnosticLog.shared.record("route", "loaded \(route.formattedDistance) \(route.formattedDuration) steps=\(route.steps.count)")
        if isNavigating {
            scheduleNavigationVoicePromptIfNeeded(location: locationManager.currentLocation)
        }
    }

    private func refreshNavigationRouteIfNeeded(from location: CLLocation) async {
        guard selectedOrigin == nil else { return }
        guard isNavigating, !isRouting, let selectedDestination else { return }

        let movedFarEnough = lastRouteRefreshLocation.map { location.distance(from: $0) > 300 } ?? true
        let waitedLongEnough = lastRouteRefreshAt.map { Date().timeIntervalSince($0) > 90 } ?? true
        guard activeRoute == nil || (movedFarEnough && waitedLongEnough) else { return }

        isRouting = true
        defer { isRouting = false }
        do {
            try await loadRouteData(to: selectedDestination)
        } catch {
            guard !Task.isCancelled else { return }
            routeStatusMessage = error.localizedDescription
        }
    }

    private func loadAutocomplete(query: String, field: PlaceSearchField, sessionToken: String) async {
        do {
            let suggestions = try await navigationService.autocomplete(query: query, origin: routeOrigin, sessionToken: sessionToken)
            guard !Task.isCancelled else { return }
            switch field {
            case .origin:
                originSuggestions = suggestions
                isLoadingOriginSuggestions = false
            case .destination:
                destinationSuggestions = suggestions
                isLoadingDestinationSuggestions = false
            }
        } catch {
            guard !Task.isCancelled else { return }
            switch field {
            case .origin:
                originSuggestions = []
                isLoadingOriginSuggestions = false
            case .destination:
                destinationSuggestions = []
                isLoadingDestinationSuggestions = false
            }
        }
    }

    private func clearSuggestions(for field: PlaceSearchField) {
        switch field {
        case .origin:
            originAutocompleteTask?.cancel()
            originSuggestions = []
            isLoadingOriginSuggestions = false
        case .destination:
            destinationAutocompleteTask?.cancel()
            destinationSuggestions = []
            isLoadingDestinationSuggestions = false
        }
    }

    private func autocompleteSessionToken(for field: PlaceSearchField) -> String {
        switch field {
        case .origin:
            return originAutocompleteSessionToken
        case .destination:
            return destinationAutocompleteSessionToken
        }
    }

    private func playNarration(for match: POIMatch, force: Bool) async {
        guard force || !poiEngine.isSuppressed(subjectId: match.poi.id) else {
            DiagnosticLog.shared.record("poi.skip", "\(match.poi.name) suppressed")
            return
        }
        guard force || !isAnsweringQuestion else {
            DiagnosticLog.shared.record("poi.skip", "\(match.poi.name) answering question")
            return
        }
        let token = narrationInterruptionToken
        isPreparingNarration = true
        statusMessage = "Preparing \(match.poi.name)"
        DiagnosticLog.shared.record("poi.narration", "prepare \(match.poi.name) force=\(force)")
        defer { isPreparingNarration = false }
        do {
            let textVersion = textVersion(for: match.poi)
            let audioURL: URL
            if let cached = await cache.cachedAudioURL(subjectId: match.poi.id, textVersion: textVersion) {
                audioURL = cached
                DiagnosticLog.shared.record("poi.narration", "cache hit \(match.poi.name)")
            } else {
                DiagnosticLog.shared.record("poi.narration", "generate \(match.poi.name)")
                let narration = try await generatedNarration(for: match.poi)
                let audioData = try await backend.speech(
                    text: narration,
                    instructions: "Speak as a warm, lower-register documentary storyteller guiding passengers through Iceland by car. Use natural pacing, crisp pronunciation, vivid factual narration, and an unrushed sense of wonder."
                )
                audioURL = try await cache.store(
                    audioData: audioData,
                    subjectId: match.poi.id,
                    textVersion: textVersion,
                    sourceContext: match.poi.narrationSeed
                )
            }
            guard force || (!isAnsweringQuestion && token == narrationInterruptionToken) else {
                DiagnosticLog.shared.record("poi.skip", "\(match.poi.name) interrupted before playback")
                return
            }
            let approachAudioURL = await approachCalloutAudioURL(for: match)
            guard force || (!isAnsweringQuestion && token == narrationInterruptionToken) else {
                DiagnosticLog.shared.record("poi.skip", "\(match.poi.name) interrupted before playback")
                return
            }
            pendingSpokenPOIByPlaybackTitle[match.poi.name] = match.poi.id
            skippablePOIByPlaybackTitle[match.poi.name] = match.poi.id
            if let approachAudioURL {
                let approachTitle = approachCalloutTitle(for: match.poi)
                skippablePOIByPlaybackTitle[approachTitle] = match.poi.id
                audioGuide.playSequence([
                    (title: approachTitle, audioURL: approachAudioURL),
                    (title: match.poi.name, audioURL: audioURL)
                ])
            } else {
                audioGuide.play(title: match.poi.name, audioURL: audioURL)
            }
            statusMessage = "Playing \(match.poi.name)"
            DiagnosticLog.shared.record("poi.narration", "playing \(match.poi.name)")
        } catch {
            statusMessage = error.localizedDescription
            DiagnosticLog.shared.record("poi.error", "\(match.poi.name): \(error.localizedDescription)")
        }
    }

    private func updatePOIDebugMessage(location: CLLocation, activeLeg: DriveLeg?) {
        let nearest = poiEngine.nearestPOIs(to: location, activeLeg: activeLeg, limit: 1, includeSuppressed: true).first
        let candidateText: String
        if let nearest {
            let suppressed = poiEngine.isSuppressed(subjectId: nearest.poi.id) ? ", suppressed" : ""
            candidateText = "\(nearest.poi.name) \(Int(nearest.distanceMeters))m\(suppressed)"
        } else {
            candidateText = "none in trigger radius"
        }

        var blockers: [String] = []
        if !autoNarrationEnabled { blockers.append("Auto POI off") }
        if isAnsweringQuestion { blockers.append("answering question") }
        if isPreparingNarration { blockers.append("preparing narration") }
        if realtimeGuideService.isSessionActive { blockers.append("realtime live") }
        if audioGuide.isPlaying { blockers.append("audio: \(audioGuide.nowPlayingTitle ?? "playing")") }

        let blockerText = blockers.isEmpty ? "ready" : blockers.joined(separator: ", ")
        poiDebugMessage = "Nearest POI: \(candidateText). State: \(blockerText). GPS: \(String(format: "%.5f", location.coordinate.latitude)), \(String(format: "%.5f", location.coordinate.longitude))"
        logPOIDebugIfNeeded()
    }

    private func logPOIDebugIfNeeded() {
        guard poiDebugMessage != lastLoggedPOIDebugMessage else { return }
        lastLoggedPOIDebugMessage = poiDebugMessage
        DiagnosticLog.shared.record("poi.evaluate", poiDebugMessage)
    }

    private func ensureNarrationCached(for match: POIMatch) async {
        let textVersion = textVersion(for: match.poi)
        if await cache.cachedAudioURL(subjectId: match.poi.id, textVersion: textVersion) != nil { return }
        do {
            let narration = try await generatedNarration(for: match.poi)
            let audioData = try await backend.speech(
                text: narration,
                instructions: "Speak as a warm, lower-register documentary storyteller guiding passengers through Iceland by car. Use natural pacing, crisp pronunciation, vivid factual narration, and an unrushed sense of wonder."
            )
            _ = try await cache.store(audioData: audioData, subjectId: match.poi.id, textVersion: textVersion, sourceContext: match.poi.narrationSeed)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func generatedNarration(for poi: POI) async throws -> String {
        let prompt = """
        Create a full 60 to 90 second English audio tour narration for \(poi.name). Use vivid but factual language. Include what to look for from the car, why this place matters, one memorable detail, and one practical travel cue. Source notes: \(poi.narrationSeed) \(poi.safetyNote ?? "")
        """
        return try await backend.ask(
            question: prompt,
            coordinate: locationManager.currentLocation?.coordinate,
            dayId: activeDayId,
            context: currentContext()
        )
    }

    private func approachCalloutAudioURL(for match: POIMatch) async -> URL? {
        guard let text = approachCalloutText(for: match) else { return nil }
        let subjectId = "\(match.poi.id)-approach-\(stableHash(text))"
        let textVersion = stableHash("waytale-approach-v1|\(text)")
        if let cached = await cache.cachedAudioURL(subjectId: subjectId, textVersion: textVersion) {
            return cached
        }

        do {
            DiagnosticLog.shared.record("poi.approach", text)
            let audioData = try await backend.speech(
                text: text,
                instructions: "Speak as a concise in-car location callout before a longer tour narration. Keep it clear, practical, and under five seconds."
            )
            return try await cache.store(
                audioData: audioData,
                subjectId: subjectId,
                textVersion: textVersion,
                sourceContext: text
            )
        } catch {
            DiagnosticLog.shared.record("poi.approach", "failed \(match.poi.name): \(error.localizedDescription)")
            return nil
        }
    }

    private func approachCalloutText(for match: POIMatch) -> String? {
        guard let location = locationManager.currentLocation else { return nil }
        let poiLocation = CLLocation(latitude: match.poi.latitude, longitude: match.poi.longitude)
        let distanceText = formattedApproachDistance(location.distance(from: poiLocation))
        let bearing = bearingDegrees(from: location.coordinate, to: match.poi.coordinate)
        let directionText: String

        if let heading = currentTravelHeading(from: location) {
            directionText = relativeDirectionText(bearing: bearing, heading: heading)
        } else {
            directionText = "to the \(cardinalDirection(for: bearing))"
        }

        return "\(match.poi.name) is about \(distanceText) \(directionText)."
    }

    private func approachCalloutTitle(for poi: POI) -> String {
        "Approaching \(poi.name)"
    }

    private func currentTravelHeading(from location: CLLocation) -> CLLocationDirection? {
        if let trueHeading = locationManager.heading?.trueHeading, trueHeading >= 0 {
            return trueHeading
        }
        if location.course >= 0 {
            return location.course
        }
        return nil
    }

    private func formattedApproachDistance(_ distance: CLLocationDistance) -> String {
        if distance < 100 {
            return "\(Int((distance / 10).rounded() * 10)) meters"
        }
        if distance < 1000 {
            return "\(Int((distance / 25).rounded() * 25)) meters"
        }
        let kilometers = distance / 1000
        return String(format: "%.1f kilometers", kilometers)
    }

    private func relativeDirectionText(bearing: CLLocationDirection, heading: CLLocationDirection) -> String {
        let delta = normalizedAngle(bearing - heading)
        let magnitude = abs(delta)
        let side = delta >= 0 ? "right" : "left"

        switch magnitude {
        case 0..<22.5:
            return "straight ahead"
        case 22.5..<67.5:
            return "ahead on your \(side)"
        case 67.5..<112.5:
            return "to your \(side)"
        case 112.5..<157.5:
            return "behind you on your \(side)"
        default:
            return "behind you"
        }
    }

    private func normalizedAngle(_ angle: CLLocationDirection) -> CLLocationDirection {
        var normalized = angle.truncatingRemainder(dividingBy: 360)
        if normalized > 180 { normalized -= 360 }
        if normalized < -180 { normalized += 360 }
        return normalized
    }

    private func bearingDegrees(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) -> CLLocationDirection {
        let originLatitude = degreesToRadians(origin.latitude)
        let destinationLatitude = degreesToRadians(destination.latitude)
        let longitudeDelta = degreesToRadians(destination.longitude - origin.longitude)
        let y = sin(longitudeDelta) * cos(destinationLatitude)
        let x = cos(originLatitude) * sin(destinationLatitude) - sin(originLatitude) * cos(destinationLatitude) * cos(longitudeDelta)
        return (radiansToDegrees(atan2(y, x)) + 360).truncatingRemainder(dividingBy: 360)
    }

    private func cardinalDirection(for bearing: CLLocationDirection) -> String {
        let directions = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]
        let index = Int(((bearing + 22.5).truncatingRemainder(dividingBy: 360)) / 45)
        return directions[index]
    }

    private func degreesToRadians(_ value: Double) -> Double {
        value * .pi / 180
    }

    private func radiansToDegrees(_ value: Double) -> Double {
        value * 180 / .pi
    }

    private func answer(question: String) async {
        await voiceQuestionService.answer(question: question, context: currentContext())
    }

    private func resetNavigationVoiceProgress() {
        navigationVoiceTask?.cancel()
        navigationVoiceTask = nil
        spokenNavigationInstructionKeys.removeAll()
        lastNavigationVoicePromptAt = nil
    }

    private func scheduleNavigationVoicePromptIfNeeded(location: CLLocation?, force: Bool = false) {
        guard navigationVoiceTask == nil else { return }
        guard let prompt = navigationVoicePrompt(location: location, force: force) else { return }
        navigationVoiceTask = Task { [weak self] in
            guard let self else { return }
            await self.playNavigationVoicePrompt(prompt)
        }
    }

    private func navigationVoicePrompt(location: CLLocation?, force: Bool) -> NavigationVoicePrompt? {
        guard navigationVoiceGuidanceEnabled else { return nil }
        guard isNavigating, let route = activeRoute, !route.steps.isEmpty else { return nil }
        guard !isAnsweringQuestion, !isPreparingNarration else { return nil }
        guard !realtimeGuideService.isSessionActive, !realtimeGuideService.isPreparingRealtimeAudio else { return nil }
        guard !voiceQuestionService.isRecordingQuestion else { return nil }
        if audioGuide.isPlaying {
            DiagnosticLog.shared.record("navigation", "voice prompt skipped: audio \(audioGuide.nowPlayingTitle ?? "playing")")
            return nil
        }
        if !force, let lastNavigationVoicePromptAt, Date().timeIntervalSince(lastNavigationVoicePromptAt) < 12 {
            return nil
        }

        let candidate: (index: Int, step: NavigationStep, distance: CLLocationDistance)
        if force {
            candidate = (0, route.steps[0], 0)
        } else {
            guard let location else { return nil }
            guard let nearest = nearestNavigationStep(in: route, to: location), nearest.distance <= 90 else {
                return nil
            }
            candidate = nearest
        }

        guard isTurnNavigationStep(candidate.step, index: candidate.index) else {
            return nil
        }

        let instruction = cleanNavigationInstruction(candidate.step.instruction)
        guard !instruction.isEmpty else { return nil }
        let instructionKey = navigationInstructionKey(for: candidate.step, instruction: instruction)
        guard !spokenNavigationInstructionKeys.contains(instructionKey) else {
            return nil
        }

        let text = instruction
        return NavigationVoicePrompt(
            routeId: route.id,
            instructionKey: instructionKey,
            stepId: candidate.step.id,
            text: text
        )
    }

    private func nearestNavigationStep(
        in route: NavigationRoute,
        to location: CLLocation
    ) -> (index: Int, step: NavigationStep, distance: CLLocationDistance)? {
        route.steps.enumerated()
            .map { index, step in
                (index: index, step: step, distance: distanceToStep(step, from: location))
            }
            .min { $0.distance < $1.distance }
    }

    private func distanceToStep(_ step: NavigationStep, from location: CLLocation) -> CLLocationDistance {
        guard !step.path.isEmpty else { return .greatestFiniteMagnitude }
        if step.path.count == 1 {
            return location.distance(from: CLLocation(latitude: step.path[0].latitude, longitude: step.path[0].longitude))
        }
        return zip(step.path, step.path.dropFirst())
            .map { distanceToSegment(location: location, start: $0.0, end: $0.1) }
            .min() ?? .greatestFiniteMagnitude
    }

    private func distanceToSegment(location: CLLocation, start: CoordinatePoint, end: CoordinatePoint) -> CLLocationDistance {
        let locationLatitude = location.coordinate.latitude
        let locationLongitude = location.coordinate.longitude
        let startLatitude = start.latitude
        let startLongitude = start.longitude
        let endLatitude = end.latitude
        let endLongitude = end.longitude
        let deltaLatitude = endLatitude - startLatitude
        let deltaLongitude = endLongitude - startLongitude
        let lengthSquared = deltaLatitude * deltaLatitude + deltaLongitude * deltaLongitude

        guard lengthSquared > 0 else {
            return location.distance(from: CLLocation(latitude: startLatitude, longitude: startLongitude))
        }

        let projection = max(
            0,
            min(
                1,
                ((locationLatitude - startLatitude) * deltaLatitude + (locationLongitude - startLongitude) * deltaLongitude) / lengthSquared
            )
        )
        let projected = CLLocation(
            latitude: startLatitude + projection * deltaLatitude,
            longitude: startLongitude + projection * deltaLongitude
        )
        return location.distance(from: projected)
    }

    private func playNavigationVoicePrompt(_ prompt: NavigationVoicePrompt) async {
        defer {
            navigationVoiceTask = nil
        }
        let token = narrationInterruptionToken
        do {
            let textVersion = navigationPromptTextVersion(for: prompt.text)
            let subjectId = "navigation-\(prompt.stepId)"
            let audioURL: URL
            if let cached = await cache.cachedAudioURL(subjectId: subjectId, textVersion: textVersion) {
                audioURL = cached
            } else {
                let audioData = try await backend.speech(
                    text: prompt.text,
                    instructions: "Speak as a clear, calm in-car navigation voice. Keep it brief and practical."
                )
                audioURL = try await cache.store(
                    audioData: audioData,
                    subjectId: subjectId,
                    textVersion: textVersion,
                    sourceContext: prompt.text
                )
            }
            guard !Task.isCancelled else { return }
            guard isNavigating, !isAnsweringQuestion, token == narrationInterruptionToken else { return }
            guard !realtimeGuideService.isSessionActive, !realtimeGuideService.isPreparingRealtimeAudio else { return }
            guard !audioGuide.isPlaying else {
                DiagnosticLog.shared.record("navigation", "voice prompt skipped after load: audio \(audioGuide.nowPlayingTitle ?? "playing")")
                return
            }

            audioGuide.play(title: "Navigation", audioURL: audioURL)
            spokenNavigationInstructionKeys.insert(prompt.instructionKey)
            lastNavigationVoicePromptAt = Date()
            statusMessage = prompt.text
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func cleanNavigationInstruction(_ instruction: String) -> String {
        instruction
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func navigationPromptTextVersion(for text: String) -> String {
        let value = "waytale-navigation-v1|\(text)"
        return stableHash(value)
    }

    private func isTurnNavigationStep(_ step: NavigationStep, index: Int) -> Bool {
        guard index > 0 else { return false }
        let maneuver = step.maneuver?.lowercased() ?? ""
        let excludedManeuvers = ["depart", "arrive", "arrive_left", "arrive_right", "straight", "unknown"]
        if !maneuver.isEmpty, !excludedManeuvers.contains(maneuver) {
            return true
        }

        let instruction = cleanNavigationInstruction(step.instruction).lowercased()
        return [
            "turn ", "take ", "merge ", "keep ", "exit ", "slight ", "sharp ",
            "make a u", "make u", "at the roundabout", "enter the roundabout"
        ].contains { instruction.hasPrefix($0) }
    }

    private func navigationInstructionKey(for step: NavigationStep, instruction: String) -> String {
        let maneuver = step.maneuver?.lowercased() ?? "none"
        return stableHash("\(maneuver)|\(instruction.lowercased())")
    }

    private func stableHash(_ value: String) -> String {
        let hash = value.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { partial, byte in
            (partial ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private func currentContext() -> GuideContext {
        let location = locationManager.currentLocation
        let leg = activeLeg
        let matches = location.map { poiEngine.nearestPOIs(to: $0, activeLeg: leg, limit: 5, includeSuppressed: true).map(\.poi) } ?? []
        return GuideContext(
            coordinate: location.map { CoordinatePoint(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) },
            speedMetersPerSecond: location?.speed,
            headingDegrees: locationManager.heading?.trueHeading,
            activeDayId: activeDayId,
            activeLeg: leg,
            nearestPOIs: matches,
            nearestItineraryStop: nearestStop
        )
    }

    private var routeOrigin: CLLocationCoordinate2D? {
        selectedOrigin?.coordinate ?? locationManager.currentLocation?.coordinate ?? activeLeg?.corridor.first?.coordinate
    }

    private func textVersion(for poi: POI) -> String {
        let text = "cedar-storyteller-v1|" + poi.narrationSeed + (poi.safetyNote ?? "")
        return stableHash(text)
    }

    private func beginQuestionInterruption(status: String) {
        isAnsweringQuestion = true
        narrationInterruptionToken += 1
        audioGuide.stop(shouldNotifyOthers: false)
        statusMessage = status
    }

    private func finishQuestionInterruption() {
        isAnsweringQuestion = false
    }

    private func startRealtimeConversation(initialQuestion: String?) {
        guard isDriveModeActive else { return }
        realtimeStartTask?.cancel()
        isAnsweringQuestion = true
        narrationInterruptionToken += 1
        audioGuide.stop(shouldNotifyOthers: false)
        statusMessage = "Preparing Waytale live audio..."

        realtimeStartTask = Task { [weak self] in
            guard let self else { return }
            let microphoneAllowed = await self.voiceQuestionService.requestMicrophonePermission()
            guard microphoneAllowed, AVAudioApplication.shared.recordPermission == .granted else {
                self.statusMessage = "Microphone permission is required for Waytale live audio"
                self.isAnsweringQuestion = false
                self.realtimeGuideService.clearRealtimeAudioPreparation()
                self.realtimeStartTask = nil
                return
            }
            if self.isNavigating {
                self.realtimeGuideService.prepareForNavigationActivation()
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, self.isDriveModeActive else {
                self.realtimeGuideService.clearRealtimeAudioPreparation()
                return
            }
            self.realtimeGuideService.startSession(context: self.currentContext(), initialQuestion: initialQuestion)
            self.statusMessage = "Waytale live session started"
            self.realtimeStartTask = nil
        }
    }

    private func endRealtimeConversation() {
        realtimeStartTask?.cancel()
        realtimeStartTask = nil
        realtimeGuideService.endSession(reason: "ask button toggled")
        isAnsweringQuestion = false
        statusMessage = "Waytale live session ended"
    }

    private func isStopCommand(_ question: String) -> Bool {
        let normalized = question
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[^\w\s]"#, with: "", options: .regularExpression)
        let stopCommands = [
            "stop",
            "stop talking",
            "stop narration",
            "stop the narration",
            "stop audio",
            "pause",
            "pause narration",
            "be quiet",
            "quiet",
            "silence"
        ]
        return stopCommands.contains(normalized)
    }
}

extension NavigationRoute {
    var formattedDistance: String {
        let kilometers = Double(distanceMeters) / 1_000
        if kilometers >= 10 {
            return "\(Int(kilometers.rounded())) km"
        }
        return String(format: "%.1f km", kilometers)
    }

    var formattedDuration: String {
        let minutes = max(1, Int((Double(durationSeconds) / 60).rounded()))
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return remainingMinutes == 0 ? "\(hours) hr" : "\(hours) hr \(remainingMinutes) min"
        }
        return "\(minutes) min"
    }
}

private struct NavigationVoicePrompt {
    let routeId: String
    let instructionKey: String
    let stepId: String
    let text: String
}
