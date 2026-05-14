import SwiftUI
import CoreLocation
import GoogleMaps
import GoogleNavigation
import UIKit

struct DriveModeView: View {
    @EnvironmentObject private var viewModel: TourGuideViewModel
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var audioGuide: AudioGuideService
    @EnvironmentObject private var voiceService: VoiceQuestionService
    @EnvironmentObject private var realtimeService: RealtimeGuideService
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var diagnosticLog = DiagnosticLog.shared
    @AppStorage("waytale.companionModeEnabled") private var isCompanionModeEnabled = false
    @AppStorage("waytale.backgroundPOINarrationEnabled") private var isBackgroundPOINarrationEnabled = false
    @State private var originQuery = ""
    @State private var destinationQuery = ""
    @State private var showsDiagnostics = false
    @FocusState private var focusedSearchField: RouteSearchField?

    var body: some View {
        ZStack {
            if isCompanionModeEnabled {
                companionBackground
                realtimeLiveBadge
                VStack(spacing: 14) {
                    companionHeader
                    Spacer()
                    companionBottomPanel
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 14)
            } else {
                mapLayer
                realtimeLiveBadge

                if viewModel.isNavigating {
                    navigationControlDock
                        .zIndex(20)
                } else {
                    VStack {
                        LinearGradient(colors: [.black.opacity(0.62), .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 210)
                        Spacer()
                        LinearGradient(colors: [.clear, .black.opacity(0.76)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 390)
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                    VStack(spacing: 14) {
                        mapHeader
                        Spacer()
                        mapBottomPanel
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            DiagnosticLog.shared.record("app.lifecycle", "main view task started")
            viewModel.activateAlwaysOnGuideIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                DiagnosticLog.shared.record("app.lifecycle", "scene active")
                viewModel.activateAlwaysOnGuideIfNeeded()
            case .inactive:
                DiagnosticLog.shared.record("app.lifecycle", "scene inactive")
            case .background:
                DiagnosticLog.shared.record("app.lifecycle", "scene background")
                let shouldKeepGuideActive = isBackgroundPOINarrationEnabled || viewModel.isNavigating || isCompanionModeEnabled
                if shouldKeepGuideActive {
                    DiagnosticLog.shared.record(
                        "app.lifecycle",
                        "keeping guide active in background backgroundPOI=\(isBackgroundPOINarrationEnabled) navigating=\(viewModel.isNavigating) companion=\(isCompanionModeEnabled)"
                    )
                } else {
                    DiagnosticLog.shared.record("app.lifecycle", "background POI disabled; suspending guide services")
                    viewModel.suspendGuideServicesForBackground()
                }
            @unknown default:
                DiagnosticLog.shared.record("app.lifecycle", "scene unknown")
            }
        }
        .sheet(isPresented: $showsDiagnostics) {
            diagnosticsSheet
                .presentationDetents([.medium, .large])
        }
        .onChange(of: isCompanionModeEnabled) { _, enabled in
            guard enabled, viewModel.isNavigating else { return }
            viewModel.stopNavigation()
        }
    }

    private var companionBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.02, green: 0.08, blue: 0.16),
                Color(red: 0.03, green: 0.18, blue: 0.22),
                Color(red: 0.01, green: 0.05, blue: 0.10)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var companionHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Waytale")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Companion Mode")
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(.white)
                    Text(companionSubtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(3)
                }

                Spacer(minLength: 8)

                Button {
                    showsDiagnostics = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .frame(width: 34, height: 34)
                }
                .foregroundStyle(.white)
                .background(.white.opacity(0.12), in: Circle())
                .accessibilityLabel("Settings")
            }

            HStack(spacing: 8) {
                mapPill(icon: "location.fill", text: gpsValue)
                mapPill(icon: "mic.circle.fill", text: realtimeService.isSessionActive ? "Live" : "Tap Ask")
            }
        }
        .padding(14)
        .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.14)))
    }

    private var companionBottomPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Always-on guide", systemImage: viewModel.isDriveModeActive ? "waveform.circle.fill" : "waveform.circle")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.cyan)
                Text(audioGuide.nowPlayingTitle ?? viewModel.currentMatch?.poi.name ?? "Listening for nearby POIs")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(viewModel.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                Button {
                    handleNarrationControlTapped()
                } label: {
                    Label(narrationControlTitle, systemImage: narrationControlIcon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryDriveButtonStyle())

                Button {
                    viewModel.askGuideButtonTapped()
                } label: {
                    Label(realtimeService.isSessionActive ? "End" : "Ask Waytale", systemImage: realtimeService.isSessionActive ? "phone.down.fill" : "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryDriveButtonStyle())
            }
        }
        .padding(14)
        .background(.black.opacity(0.66), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.14)))
    }

    @ViewBuilder
    private var mapLayer: some View {
        if AppConfiguration.googleMapsAPIKey != nil {
            GoogleTripMapView(
                origin: directionsOrigin,
                destination: directionsDestination,
                activeLeg: viewModel.activeLeg,
                route: viewModel.activeRoute,
                isNavigating: viewModel.isNavigating,
                shouldSimulateSelectedOrigin: shouldSimulateSelectedOrigin,
                shouldMuteNavigationVoice: viewModel.isNavigating || realtimeService.isSessionActive || realtimeService.isPreparingRealtimeAudio,
                heading: locationManager.heading?.trueHeading
            )
                .ignoresSafeArea()
        } else {
            LinearGradient(colors: [Color(red: 0.04, green: 0.08, blue: 0.14), Color(red: 0.05, green: 0.22, blue: 0.20)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .overlay {
                    VStack(spacing: 12) {
                        Image(systemName: "map.fill")
                            .font(.largeTitle)
                        Text("Google Maps SDK key missing")
                            .font(.headline)
                        Text("Set GOOGLE_MAPS_API_KEY to load the in-app map.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.74))
                    }
                    .foregroundStyle(.white)
                    .padding(24)
                }
        }
    }

    private var mapHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Waytale")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Text(directionsDestination?.title ?? "Where to?")
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                    Text(routeSubtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 8) {
                    mapPill(icon: originPillIcon, text: originPillText)
                    Button {
                        showsDiagnostics = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .frame(width: 34, height: 34)
                    }
                    .foregroundStyle(.white)
                    .background(.white.opacity(0.12), in: Circle())
                    .accessibilityLabel("Settings")
                }
            }

            routeSearchControls

            destinationChips
        }
        .padding(14)
        .background(.black.opacity(0.54), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.14)))
    }

    private var mapBottomPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.selectedDestination != nil || viewModel.activeRoute != nil {
                navigationStatusPanel
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Always-on guide", systemImage: viewModel.isDriveModeActive ? "waveform.circle.fill" : "waveform.circle")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.cyan)
                    Text(audioGuide.nowPlayingTitle ?? "No narration playing")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(viewModel.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Button {
                    if viewModel.isNavigating {
                        viewModel.stopNavigation()
                    } else if viewModel.selectedDestination != nil {
                        viewModel.startNavigation()
                    } else {
                        viewModel.askGuideButtonTapped()
                    }
                } label: {
                    Image(systemName: primaryDriveIcon)
                        .frame(width: 48, height: 48)
                }
                .foregroundStyle(.black)
                .background(primaryDriveColor, in: Circle())
                .accessibilityLabel(primaryDriveAccessibilityLabel)
            }

            HStack(spacing: 10) {
                Button {
                    handleNarrationControlTapped()
                } label: {
                    Label(narrationControlTitle, systemImage: narrationControlIcon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryDriveButtonStyle())

                Button {
                    viewModel.askGuideButtonTapped()
                } label: {
                    Label(realtimeService.isSessionActive ? "End" : "Ask Waytale", systemImage: realtimeService.isSessionActive ? "phone.down.fill" : "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryDriveButtonStyle())
            }
        }
        .padding(14)
        .background(.black.opacity(0.66), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.14)))
    }

    private var navigationControlDock: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: 10) {
                    if audioGuide.isPlaying {
                        Button {
                            viewModel.stopCurrentNarration()
                        } label: {
                            Image(systemName: "stop.fill")
                                .frame(width: 48, height: 48)
                        }
                        .foregroundStyle(.white)
                        .background(.black.opacity(0.56), in: Circle())
                        .contentShape(Circle())
                        .accessibilityLabel("Stop Waytale narration")
                    }

                    Button {
                        viewModel.askGuideButtonTapped()
                    } label: {
                        Image(systemName: realtimeService.isSessionActive ? "phone.down.fill" : "mic.fill")
                            .frame(width: 48, height: 48)
                    }
                    .foregroundStyle(.white)
                    .background(.black.opacity(0.56), in: Circle())
                    .contentShape(Circle())
                    .accessibilityLabel(realtimeService.isSessionActive ? "End Waytale conversation" : "Ask Waytale")

                    Button {
                        viewModel.stopNavigation()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 52, height: 52)
                    }
                    .foregroundStyle(.white)
                    .background(.red, in: Circle())
                    .accessibilityLabel("End navigation")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private var realtimeLiveBadge: some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 7) {
                    Circle()
                        .fill(realtimeService.isSessionActive ? .cyan : .white.opacity(0.42))
                        .frame(width: 8, height: 8)
                    Text(realtimeService.isSessionActive ? "Waytale Live" : "Waytale")
                        .font(.caption.weight(.heavy))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(.blue.opacity(realtimeService.isSessionActive ? 0.86 : 0.58), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.18)))
                .shadow(color: .blue.opacity(realtimeService.isSessionActive ? 0.32 : 0), radius: 14)
            }
            Spacer()
        }
        .padding(.top, viewModel.isNavigating ? 58 : 14)
        .padding(.horizontal, 16)
        .allowsHitTesting(false)
        .zIndex(12)
    }

    private var destinationChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TripData.itineraryStops) { stop in
                    Button {
                        destinationQuery = stop.title
                        focusedSearchField = nil
                        viewModel.setDestination(stop)
                    } label: {
                        Label(stop.title, systemImage: "mappin")
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.10), in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.14)))
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }

    private var routeSearchControls: some View {
        VStack(spacing: 7) {
            routeSearchField(
                label: "From",
                icon: "location.fill",
                placeholder: "Current location",
                text: $originQuery,
                field: .origin,
                isLoading: viewModel.isLoadingOriginSuggestions
            )

            routeSearchField(
                label: "To",
                icon: "magnifyingglass",
                placeholder: "Search address or place",
                text: $destinationQuery,
                field: .destination,
                isLoading: viewModel.isLoadingDestinationSuggestions || viewModel.isRouting
            )

            if focusedSearchField == .origin {
                originSuggestionList
            } else if focusedSearchField == .destination {
                suggestionList(
                    suggestions: viewModel.destinationSuggestions,
                    currentLocationOption: false,
                    emptyLabel: destinationQuery.count >= 2 ? "Searching Google Places..." : nil
                ) { suggestion in
                    destinationQuery = suggestion.displayText
                    focusedSearchField = nil
                    viewModel.selectDestinationSuggestion(suggestion)
                }
            }
        }
    }

    private var originSuggestionList: some View {
        suggestionList(
            suggestions: viewModel.originSuggestions,
            currentLocationOption: true,
            emptyLabel: originQuery.count >= 2 ? "Searching Google Places..." : nil
        ) { suggestion in
            originQuery = suggestion.displayText
            focusedSearchField = nil
            viewModel.selectOriginSuggestion(suggestion)
        }
    }

    private func routeSearchField(
        label: String,
        icon: String,
        placeholder: String,
        text: Binding<String>,
        field: RouteSearchField,
        isLoading: Bool
    ) -> some View {
        HStack(spacing: 9) {
            Text(label)
                .font(.caption.weight(.heavy))
                .foregroundStyle(.white.opacity(0.58))
                .frame(width: 38, alignment: .leading)

            Image(systemName: icon)
                .foregroundStyle(.white.opacity(0.66))
                .frame(width: 16)

            TextField(placeholder, text: text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(field == .origin ? .next : .go)
                .focused($focusedSearchField, equals: field)
                .foregroundStyle(.white)
                .onSubmit {
                    submitSearch(field)
                }
                .onChange(of: text.wrappedValue) { _, newValue in
                    guard focusedSearchField == field else { return }
                    viewModel.updateAutocomplete(query: newValue, field: field.placeSearchField)
                }

            if isLoading {
                ProgressView()
                    .tint(.white.opacity(0.78))
                    .frame(width: 18, height: 18)
            } else if !text.wrappedValue.isEmpty {
                Button {
                    clearSearch(field)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .foregroundStyle(.white.opacity(0.68))
                .accessibilityLabel(field == .origin ? "Clear origin" : "Clear destination")
            }

            Button {
                submitSearch(field)
            } label: {
                Image(systemName: field == .origin ? "arrow.up.right" : "arrow.turn.down.right")
                    .frame(width: 28, height: 28)
            }
            .foregroundStyle(.black)
            .background(.mint, in: Circle())
            .disabled(isLoading)
            .accessibilityLabel(field == .origin ? "Set origin" : "Route to destination")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 16))
    }

    private func suggestionList(
        suggestions: [PlaceSuggestion],
        currentLocationOption: Bool,
        emptyLabel: String?,
        onSelect: @escaping (PlaceSuggestion) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if currentLocationOption {
                Button {
                    originQuery = ""
                    focusedSearchField = nil
                    viewModel.setOriginToCurrentLocation()
                } label: {
                    suggestionRow(title: "Current location", subtitle: gpsValue, icon: "location.fill")
                }
                .foregroundStyle(.white)
            }

            ForEach(suggestions.prefix(5)) { suggestion in
                Button {
                    onSelect(suggestion)
                } label: {
                    suggestionRow(title: suggestion.title, subtitle: suggestion.displaySubtitle, icon: suggestion.placeId == nil ? "magnifyingglass" : "mappin")
                }
                .foregroundStyle(.white)
            }

            if suggestions.isEmpty, let emptyLabel {
                Text(emptyLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.58))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
        }
        .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.10)))
    }

    private func suggestionRow(title: String, subtitle: String?, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.mint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private var navigationStatusPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(viewModel.isNavigating ? "Navigating" : "Route", systemImage: viewModel.isNavigating ? "location.north.line.fill" : "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.mint)
                Spacer()
                if let route = viewModel.activeRoute {
                    Text("\(route.formattedDistance) · \(route.formattedDuration)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                }
            }

            Text(nextNavigationInstruction)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)

            HStack(spacing: 10) {
                Button {
                    viewModel.isNavigating ? viewModel.stopNavigation() : viewModel.startNavigation()
                } label: {
                    Label(viewModel.isNavigating ? "End" : "Start", systemImage: viewModel.isNavigating ? "xmark" : "location.north.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CompactNavButtonStyle(color: viewModel.isNavigating ? .red : .mint))

                Button {
                    viewModel.clearDestination()
                    destinationQuery = ""
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 42)
                }
                .buttonStyle(SecondaryDriveButtonStyle())
                .accessibilityLabel("Clear route")
            }
        }
        .padding(12)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.14)))
    }

    private func mapPill(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(.white.opacity(0.12), in: Capsule())
    }

    private func mapMetric(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .foregroundStyle(.mint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.58))
                Text(value)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.10), in: Capsule())
    }

    private func submitDestinationSearch() {
        focusedSearchField = nil
        viewModel.searchDestination(destinationQuery)
    }

    private func submitSearch(_ field: RouteSearchField) {
        switch field {
        case .origin:
            focusedSearchField = .destination
            viewModel.searchOrigin(originQuery)
        case .destination:
            submitDestinationSearch()
        }
    }

    private func clearSearch(_ field: RouteSearchField) {
        switch field {
        case .origin:
            originQuery = ""
            focusedSearchField = nil
            viewModel.setOriginToCurrentLocation()
        case .destination:
            destinationQuery = ""
            viewModel.clearDestination()
        }
    }

    private var routeSubtitle: String {
        if viewModel.isRouting {
            return "Calculating route..."
        }
        if viewModel.selectedDestination != nil || viewModel.activeRoute != nil {
            return viewModel.routeStatusMessage
        }
        return viewModel.currentMatch?.poi.narrationSeed ?? viewModel.activeLeg?.summary ?? viewModel.statusMessage
    }

    private var companionSubtitle: String {
        viewModel.currentMatch?.poi.narrationSeed ?? viewModel.activeLeg?.summary ?? "Use another navigation app while Waytale handles POI narration and voice help."
    }

    private var nextNavigationInstruction: String {
        if let firstStep = viewModel.activeRoute?.steps.first {
            return firstStep.instruction
        }
        return viewModel.routeStatusMessage
    }

    private var primaryDriveIcon: String {
        if viewModel.isNavigating { return "xmark" }
        if viewModel.selectedDestination != nil { return "location.north.fill" }
        return realtimeService.isSessionActive ? "phone.down.fill" : "mic.fill"
    }

    private var primaryDriveColor: Color {
        if viewModel.isNavigating { return .red }
        return realtimeService.isSessionActive && viewModel.selectedDestination == nil ? .red : .mint
    }

    private var primaryDriveAccessibilityLabel: String {
        if viewModel.isNavigating { return "End Navigation" }
        if viewModel.selectedDestination != nil { return "Start Navigation" }
        return realtimeService.isSessionActive ? "End Waytale" : "Ask Waytale"
    }

    private var narrationControlTitle: String {
        if audioGuide.isPlaying { return "Stop Audio" }
        return realtimeService.isSessionActive ? "Stop" : "Play POI"
    }

    private var narrationControlIcon: String {
        if audioGuide.isPlaying { return "stop.fill" }
        return realtimeService.isSessionActive ? "stop.fill" : "play.fill"
    }

    private func handleNarrationControlTapped() {
        if audioGuide.isPlaying {
            viewModel.stopCurrentNarration()
        } else if realtimeService.isSessionActive {
            realtimeService.stopCurrentResponse()
        } else {
            viewModel.playCurrentNarrationNow()
        }
    }

    private var diagnosticsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    modeSettingsCard
                    backgroundPOISettingsCard
                    navigationVoiceSettingsCard
                    currentPOICard
                    statusGrid
                    controls
                    realtimeDiagnosticsCard
                    diagnosticLogCard
                    demoLocationControls
                }
                .padding(18)
            }
            .background(Color(red: 0.04, green: 0.08, blue: 0.14))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }

    private var modeSettingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isCompanionModeEnabled ? "person.wave.2.fill" : "map.fill")
                    .foregroundStyle(.mint)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text("App Mode")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(isCompanionModeEnabled ? "Companion Mode keeps Waytale focused on voice, GPS, and POI narration." : "Navigation Mode shows the in-app map, route search, and navigation controls.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Toggle("", isOn: $isCompanionModeEnabled)
                    .labelsHidden()
                    .tint(.mint)
                    .accessibilityLabel("Use Companion Mode")
            }

            Text(isCompanionModeEnabled ? "In-app maps are hidden. Use Google Maps separately for turn-by-turn navigation." : "Turn on Companion Mode if you want Waytale without in-app maps.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }

    private var backgroundPOISettingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isBackgroundPOINarrationEnabled ? "location.circle.fill" : "location.slash.fill")
                    .foregroundStyle(isBackgroundPOINarrationEnabled ? .mint : .orange)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Background POI Narration")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(isBackgroundPOINarrationEnabled ? "Waytale can keep POI narration active after you switch apps or lock the phone." : "Waytale stops GPS/geofences when it goes to the background.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Toggle("", isOn: $isBackgroundPOINarrationEnabled)
                    .labelsHidden()
                    .tint(.mint)
                    .accessibilityLabel("Allow Background POI Narration")
            }

            Text(isBackgroundPOINarrationEnabled ? "Use this when you want Google Maps in front while Waytale narrates nearby places." : "Turn this on only when you intentionally want Waytale to narrate while it is not visible.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }

    private var navigationVoiceSettingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: viewModel.navigationVoiceGuidanceEnabled ? "arrow.triangle.turn.up.right.circle.fill" : "speaker.slash.circle.fill")
                    .foregroundStyle(viewModel.navigationVoiceGuidanceEnabled ? .mint : .orange)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text("GPS Voice Guidance")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(viewModel.navigationVoiceGuidanceEnabled ? "Waytale speaks turn prompts only when you approach a maneuver." : "Waytale keeps visual navigation active without speaking GPS prompts.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Toggle(
                    "",
                    isOn: Binding(
                        get: { viewModel.navigationVoiceGuidanceEnabled },
                        set: { viewModel.setNavigationVoiceGuidanceEnabled($0) }
                    )
                )
                .labelsHidden()
                .tint(.mint)
                .accessibilityLabel("Enable GPS Voice Guidance")
            }

            Text("POI narration and Ask Waytale are unaffected by this setting.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active Drive Mode")
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(.mint)
            Text(viewModel.currentMatch?.poi.name ?? viewModel.activeLeg?.label ?? "Start Drive Mode")
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.65)
            Text(viewModel.currentMatch?.poi.narrationSeed ?? viewModel.activeLeg?.summary ?? "GPS-triggered long narration for important Iceland POIs.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.78))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
    }

    private var currentPOICard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Narration", systemImage: "speaker.wave.2.fill")
                .font(.headline)
                .foregroundStyle(.white)
            Text(audioGuide.nowPlayingTitle ?? "No narration playing")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text(viewModel.statusMessage)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
            Text(viewModel.poiDebugMessage)
                .font(.caption.monospaced())
                .foregroundStyle(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
            if isBackgroundPOINarrationEnabled, locationManager.authorizationStatus != .authorizedAlways {
                Text("Background POI playback needs Location set to Always. Current: \(authorizationText).")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 18))
    }

    private var statusGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statusTile(title: "GPS", value: gpsValue, icon: "location.fill")
            statusTile(title: "Mic trigger", value: realtimeService.isSessionActive ? "Live" : "Button", icon: "mic.fill")
            statusTile(title: "Audio", value: audioGuide.isPlaying ? "Playing" : "Ready", icon: "hifispeaker.fill")
            statusTile(title: "Realtime", value: realtimeService.isSessionActive ? "Live" : "Idle", icon: "antenna.radiowaves.left.and.right")
            statusTile(title: "Auto POI", value: viewModel.autoNarrationEnabled ? "On" : "Paused", icon: "map.fill")
            statusTile(title: "Location", value: authorizationText, icon: "location.viewfinder")
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Button {
                viewModel.isDriveModeActive ? viewModel.stopDriveMode() : viewModel.startDriveMode()
            } label: {
                Label(viewModel.isDriveModeActive ? "Stop Drive Mode" : "Start Drive Mode", systemImage: viewModel.isDriveModeActive ? "stop.fill" : "car.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryDriveButtonStyle(color: viewModel.isDriveModeActive ? .red : .mint))

            HStack(spacing: 12) {
                Button {
                    handleNarrationControlTapped()
                } label: {
                    Label(narrationControlTitle, systemImage: narrationControlIcon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryDriveButtonStyle())

                Button {
                    viewModel.askGuideButtonTapped()
                } label: {
                    Label(realtimeService.isSessionActive ? "End Session" : "Ask Waytale", systemImage: realtimeService.isSessionActive ? "phone.down.fill" : "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryDriveButtonStyle())
            }

            Button {
                viewModel.precacheToday()
            } label: {
                Label("Cache Nearby Narration", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryDriveButtonStyle())

            Button {
                viewModel.toggleAutoNarration()
            } label: {
                Label(viewModel.autoNarrationEnabled ? "Pause Auto POI" : "Enable Auto POI", systemImage: viewModel.autoNarrationEnabled ? "pause.circle.fill" : "map.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryDriveButtonStyle())
        }
    }

    private var realtimeDiagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Realtime")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Use the Ask Waytale button to start a live Realtime conversation. Ask follow-ups naturally and say “end session” when done.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
            Text("Realtime: \(realtimeService.status)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(realtimeService.isSessionActive ? .mint : .white.opacity(0.62))
            if !realtimeService.transcript.isEmpty {
                Text("Realtime heard: \(realtimeService.transcript)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.mint)
            }
            if let errorMessage = realtimeService.errorMessage {
                Text("Realtime error: \(errorMessage)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            if !realtimeService.debugLog.isEmpty {
                Text(realtimeService.debugLog)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(8)
            }
            if let errorMessage = voiceService.errorMessage {
                Text("Mic error: \(errorMessage)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }

    private var diagnosticLogCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Event Log", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text("\(diagnosticLog.events.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.62))
            }

            Text("Newest events are shown first. Copy this after a test drive when POI, audio, route, or realtime behavior looks wrong.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = diagnosticLog.exportText
                } label: {
                    Label("Copy Log", systemImage: "doc.on.doc.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryDriveButtonStyle())

                Button {
                    diagnosticLog.clear()
                } label: {
                    Label("Clear", systemImage: "trash.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryDriveButtonStyle())
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(diagnosticLog.events.prefix(80)) { event in
                    Text(event.line)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }

    private var demoLocationControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Simulator GPS", systemImage: "mappin.and.ellipse")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                if locationManager.demoLocationLabel != nil {
                    Button("Use Live") {
                        viewModel.clearDemoLocation()
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.mint)
                }
            }

            Text(locationManager.demoLocationLabel.map { "Demo location: \($0)" } ?? "Simulator defaults to San Francisco unless you set a location. Use one of these buttons to test Iceland narration.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.demoLocations) { demoLocation in
                        Button {
                            viewModel.useDemoLocation(demoLocation)
                        } label: {
                            Text(demoLocation.label)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(.white.opacity(0.10), in: Capsule())
                                .overlay(Capsule().stroke(.white.opacity(0.18)))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 18))
    }

    private func statusTile(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.mint)
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.62))
            Text(value)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(14)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    private var gpsValue: String {
        guard let location = locationManager.currentLocation else { return authorizationText }
        let prefix = locationManager.demoLocationLabel == nil ? "" : "Demo "
        return "\(prefix)\(String(format: "%.4f", location.coordinate.latitude)), \(String(format: "%.4f", location.coordinate.longitude))"
    }

    private var originPillIcon: String {
        viewModel.selectedOrigin == nil ? "location.fill" : "arrow.up.right"
    }

    private var originPillText: String {
        viewModel.selectedOrigin?.title ?? gpsValue
    }

    private var directionsOrigin: CLLocationCoordinate2D? {
        viewModel.selectedOrigin?.coordinate ?? locationManager.currentLocation?.coordinate ?? viewModel.activeLeg?.corridor.first?.coordinate
    }

    private var shouldSimulateSelectedOrigin: Bool {
        guard let selectedOrigin = viewModel.selectedOrigin else { return false }
        guard let currentLocation = locationManager.currentLocation else { return true }
        let selectedLocation = CLLocation(latitude: selectedOrigin.latitude, longitude: selectedOrigin.longitude)
        return currentLocation.distance(from: selectedLocation) > 1_000
    }

    private var directionsDestination: GoogleMapsDestination? {
        if let destination = viewModel.selectedDestination {
            return GoogleMapsDestination(
                title: destination.title,
                coordinate: destination.coordinate,
                placeId: destination.placeId
            )
        }

        if let stop = viewModel.nearestStop {
            return GoogleMapsDestination(title: stop.title, coordinate: stop.coordinate, placeId: nil)
        }

        if let match = viewModel.currentMatch {
            return GoogleMapsDestination(title: match.poi.name, coordinate: match.poi.coordinate, placeId: nil)
        }

        if let leg = viewModel.activeLeg, let lastPoint = leg.corridor.last {
            return GoogleMapsDestination(title: leg.label, coordinate: lastPoint.coordinate, placeId: nil)
        }

        return TripData.itineraryStops
            .first { $0.dayId == viewModel.activeDayId }
            .map { GoogleMapsDestination(title: $0.title, coordinate: $0.coordinate, placeId: nil) }
    }

    private var authorizationText: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways: return "Always"
        case .authorizedWhenInUse: return "When In Use"
        case .denied, .restricted: return "Denied"
        case .notDetermined: return "Not Asked"
        @unknown default: return "Unknown"
        }
    }
}

private enum RouteSearchField: Hashable {
    case origin
    case destination

    var placeSearchField: PlaceSearchField {
        switch self {
        case .origin: return .origin
        case .destination: return .destination
        }
    }
}

private struct GoogleMapsDestination {
    let title: String
    let coordinate: CLLocationCoordinate2D
    let placeId: String?
}

private struct GoogleTripMapView: UIViewRepresentable {
    let origin: CLLocationCoordinate2D?
    let destination: GoogleMapsDestination?
    let activeLeg: DriveLeg?
    let route: NavigationRoute?
    let isNavigating: Bool
    let shouldSimulateSelectedOrigin: Bool
    let shouldMuteNavigationVoice: Bool
    let heading: CLLocationDirection?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> GMSMapView {
        let options = GMSMapViewOptions()
        options.camera = GMSCameraPosition.camera(withLatitude: 63.9, longitude: -19.5, zoom: 7)
        let mapView = GMSMapView(options: options)
        mapView.settings.compassButton = true
        mapView.settings.myLocationButton = true
        mapView.settings.rotateGestures = true
        mapView.settings.tiltGestures = true
        mapView.settings.zoomGestures = true
        mapView.settings.scrollGestures = true
        mapView.isBuildingsEnabled = true
        mapView.isTrafficEnabled = true
        mapView.isMyLocationEnabled = true
        mapView.padding = UIEdgeInsets(top: 132, left: 0, bottom: 238, right: 0)
        mapView.mapType = .normal
        mapView.delegate = context.coordinator
        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        if isNavigating {
            context.coordinator.startLiveNavigation(
                on: mapView,
                origin: origin,
                destination: destination,
                shouldSimulateSelectedOrigin: shouldSimulateSelectedOrigin,
                shouldMuteNavigationVoice: shouldMuteNavigationVoice
            )
            return
        }

        context.coordinator.stopLiveNavigation(on: mapView)
        mapView.clear()
        mapView.padding = UIEdgeInsets(top: 132, left: 0, bottom: 238, right: 0)

        var bounds: GMSCoordinateBounds?
        if let route, route.path.count > 1 {
            let routePath = GMSMutablePath()
            for point in route.path {
                routePath.add(point.coordinate)
                bounds = expandedBounds(bounds, point.coordinate)
            }
            let polyline = GMSPolyline(path: routePath)
            polyline.strokeWidth = isNavigating ? 8 : 6
            polyline.strokeColor = UIColor.systemBlue.withAlphaComponent(0.82)
            polyline.map = mapView
        } else if let activeLeg, activeLeg.corridor.count > 1 {
            let legPath = GMSMutablePath()
            for point in activeLeg.corridor {
                legPath.add(point.coordinate)
                bounds = expandedBounds(bounds, point.coordinate)
            }
            let polyline = GMSPolyline(path: legPath)
            polyline.strokeWidth = 5
            polyline.strokeColor = UIColor.systemTeal.withAlphaComponent(0.70)
            polyline.map = mapView
        }

        if let origin {
            let marker = GMSMarker(position: origin)
            marker.title = "Current position"
            marker.icon = GMSMarker.markerImage(with: UIColor.black)
            marker.map = mapView
            bounds = expandedBounds(bounds, origin)
        }

        if let destination {
            let marker = GMSMarker(position: destination.coordinate)
            marker.title = destination.title
            marker.icon = GMSMarker.markerImage(with: UIColor.systemRed)
            marker.map = mapView
            bounds = expandedBounds(bounds, destination.coordinate)
        }

        context.coordinator.updatePreviewCamera(
            on: mapView,
            bounds: bounds,
            cameraKey: previewCameraKey(route: route, activeLeg: activeLeg, destination: destination)
        )
    }

    private func previewCameraKey(
        route: NavigationRoute?,
        activeLeg: DriveLeg?,
        destination: GoogleMapsDestination?
    ) -> String {
        if let route {
            return "route:\(route.encodedPolyline)"
        }
        if let destination {
            return destination.placeId.map { "destination:\($0)" }
                ?? "destination:\(coordinateKey(destination.coordinate))"
        }
        if let activeLeg {
            return "leg:\(activeLeg.id)"
        }
        return "iceland"
    }

    private func coordinateKey(_ coordinate: CLLocationCoordinate2D) -> String {
        "\(String(format: "%.5f", coordinate.latitude)),\(String(format: "%.5f", coordinate.longitude))"
    }

    private func expandedBounds(_ bounds: GMSCoordinateBounds?, _ coordinate: CLLocationCoordinate2D) -> GMSCoordinateBounds {
        if let bounds {
            return bounds.includingCoordinate(coordinate)
        }
        return GMSCoordinateBounds(coordinate: coordinate, coordinate: coordinate)
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        private var hasPromptedForNavigationTerms = false
        private var activeNavigationKey: String?
        private var pendingNavigationKey: String?
        private var lastPreviewCameraKey: String?
        private var userAdjustedPreviewCamera = false

        func updatePreviewCamera(
            on mapView: GMSMapView,
            bounds: GMSCoordinateBounds?,
            cameraKey: String
        ) {
            if lastPreviewCameraKey != cameraKey {
                lastPreviewCameraKey = cameraKey
                userAdjustedPreviewCamera = false
            }
            guard !userAdjustedPreviewCamera else { return }

            if let bounds {
                mapView.animate(with: GMSCameraUpdate.fit(bounds, withPadding: 52))
            } else {
                mapView.animate(to: GMSCameraPosition.camera(withLatitude: 63.9, longitude: -19.5, zoom: 7))
            }
        }

        func startLiveNavigation(
            on mapView: GMSMapView,
            origin: CLLocationCoordinate2D?,
            destination: GoogleMapsDestination?,
            shouldSimulateSelectedOrigin: Bool,
            shouldMuteNavigationVoice: Bool
        ) {
            guard let destination else {
                stopLiveNavigation(on: mapView)
                return
            }

            mapView.padding = .zero
            mapView.isTrafficEnabled = true

            guard GMSNavigationServices.areTermsAndConditionsAccepted() else {
                showNavigationTermsIfNeeded(
                    mapView: mapView,
                    origin: origin,
                    destination: destination,
                    shouldSimulateSelectedOrigin: shouldSimulateSelectedOrigin,
                    shouldMuteNavigationVoice: shouldMuteNavigationVoice
                )
                return
            }

            mapView.isNavigationEnabled = true
            mapView.travelMode = .driving
            mapView.lightingMode = .lowLight
            mapView.followingPerspective = .tilted
            mapView.shouldDisplaySpeedLimit = true
            mapView.shouldDisplaySpeedometer = true

            applyNavigationAudioPolicy(
                to: mapView.navigator,
                shouldMuteNavigationVoice: shouldMuteNavigationVoice
            )

            let key = navigationKey(
                for: destination,
                origin: shouldSimulateSelectedOrigin ? origin : nil
            )
            if activeNavigationKey == key {
                let navigator = mapView.navigator
                applyNavigationAudioPolicy(
                    to: navigator,
                    shouldMuteNavigationVoice: shouldMuteNavigationVoice
                )
                navigator?.isGuidanceActive = true
                return
            }
            if pendingNavigationKey == key {
                return
            }

            guard let waypoint = waypoint(for: destination) else { return }

            let navigator = mapView.navigator
            navigator?.avoidsHighways = false
            navigator?.avoidsTolls = false
            navigator?.avoidsFerries = false
            applyNavigationAudioPolicy(
                to: navigator,
                shouldMuteNavigationVoice: shouldMuteNavigationVoice
            )
            navigator?.isGuidanceActive = false

            pendingNavigationKey = key

            if shouldSimulateSelectedOrigin, let origin {
                mapView.locationSimulator?.simulateLocation(at: origin)
            } else {
                mapView.locationSimulator?.stopSimulation()
            }

            #if targetEnvironment(simulator)
            mapView.locationSimulator?.speedMultiplier = 4
            #endif

            navigator?.setDestinations([waypoint]) { [weak self, weak mapView] status in
                self?.handleRouteStatus(
                    status,
                    key: key,
                    mapView: mapView,
                    shouldSimulateSelectedOrigin: shouldSimulateSelectedOrigin
                )
            }
        }

        private func applyNavigationAudioPolicy(
            to navigator: GMSNavigator?,
            shouldMuteNavigationVoice: Bool
        ) {
            navigator?.voiceGuidance = shouldMuteNavigationVoice ? .silent : .alertsAndGuidance
            navigator?.audioDeviceType = shouldMuteNavigationVoice ? .builtInOnly : .bluetooth
        }

        private func handleRouteStatus(
            _ status: GMSRouteStatus,
            key: String,
            mapView: GMSMapView?,
            shouldSimulateSelectedOrigin: Bool
        ) {
            guard let mapView else { return }
            pendingNavigationKey = nil
            if status == .OK {
                activeNavigationKey = key
                UIApplication.shared.isIdleTimerDisabled = true
                mapView.navigator?.isGuidanceActive = true
                mapView.cameraMode = .following
                if shouldSimulateSelectedOrigin {
                    mapView.locationSimulator?.simulateLocationsAlongExistingRoute()
                }
            } else {
                activeNavigationKey = nil
                mapView.navigator?.isGuidanceActive = false
                print("Google Navigation route failed: \(status.rawValue)")
            }
        }

        func stopLiveNavigation(on mapView: GMSMapView) {
            activeNavigationKey = nil
            pendingNavigationKey = nil
            UIApplication.shared.isIdleTimerDisabled = false
            mapView.navigator?.isGuidanceActive = false
            mapView.navigator?.clearDestinations()
            mapView.locationSimulator?.stopSimulation()
            mapView.isNavigationEnabled = false
        }

        private func showNavigationTermsIfNeeded(
            mapView: GMSMapView,
            origin: CLLocationCoordinate2D?,
            destination: GoogleMapsDestination,
            shouldSimulateSelectedOrigin: Bool,
            shouldMuteNavigationVoice: Bool
        ) {
            guard !hasPromptedForNavigationTerms else { return }
            hasPromptedForNavigationTerms = true
            let options = GMSNavigationTermsAndConditionsOptions(companyName: "Waytale")
            GMSNavigationServices.showTermsAndConditionsDialogIfNeeded(with: options) { [weak self, weak mapView] accepted in
                self?.hasPromptedForNavigationTerms = false
                guard accepted, let mapView else { return }
                self?.startLiveNavigation(
                    on: mapView,
                    origin: origin,
                    destination: destination,
                    shouldSimulateSelectedOrigin: shouldSimulateSelectedOrigin,
                    shouldMuteNavigationVoice: shouldMuteNavigationVoice
                )
            }
        }

        private func waypoint(for destination: GoogleMapsDestination) -> GMSNavigationWaypoint? {
            if let placeId = destination.placeId, !placeId.isEmpty {
                return GMSNavigationWaypoint(placeID: placeId, title: destination.title)
            }
            return GMSNavigationWaypoint(location: destination.coordinate, title: destination.title)
        }

        private func navigationKey(for destination: GoogleMapsDestination, origin: CLLocationCoordinate2D?) -> String {
            let originKey: String
            if let origin {
                originKey = "origin:\(origin.latitude),\(origin.longitude)|"
            } else {
                originKey = "origin:gps|"
            }
            if let placeId = destination.placeId, !placeId.isEmpty {
                return "\(originKey)place:\(placeId)"
            }
            return "\(originKey)coord:\(destination.coordinate.latitude),\(destination.coordinate.longitude)"
        }

        func mapView(_ mapView: GMSMapView, willMove gesture: Bool) {
            guard gesture else { return }
            if mapView.isNavigationEnabled {
                mapView.cameraMode = .free
            } else {
                userAdjustedPreviewCamera = true
            }
        }
    }
}

private struct PrimaryDriveButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .padding(.vertical, 18)
            .foregroundStyle(.black)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct SecondaryDriveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .padding(.vertical, 15)
            .foregroundStyle(.white)
            .background(.white.opacity(configuration.isPressed ? 0.12 : 0.08), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.16)))
    }
}

private struct CompactNavButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .padding(.vertical, 14)
            .foregroundStyle(.black)
            .background(color.opacity(configuration.isPressed ? 0.72 : 1), in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    let backend = BackendClient()
    let audio = AudioGuideService()
    DriveModeView()
        .environmentObject(TourGuideViewModel())
        .environmentObject(LocationManager())
        .environmentObject(audio)
        .environmentObject(VoiceQuestionService(backend: backend, audioGuide: audio))
        .environmentObject(RealtimeGuideService(backend: backend))
}
