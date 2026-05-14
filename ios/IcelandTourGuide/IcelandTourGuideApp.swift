import SwiftUI
import GoogleMaps

@main
struct IcelandTourGuideApp: App {
    @StateObject private var viewModel = TourGuideViewModel()

    init() {
        if let apiKey = AppConfiguration.googleMapsAPIKey {
            GMSServices.provideAPIKey(apiKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            DriveModeView()
                .environmentObject(viewModel)
                .environmentObject(viewModel.locationManager)
                .environmentObject(viewModel.audioGuide)
                .environmentObject(viewModel.voiceQuestionService)
                .environmentObject(viewModel.realtimeGuideService)
        }
    }
}
