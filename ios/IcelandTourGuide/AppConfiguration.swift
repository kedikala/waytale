import Foundation

enum AppBrand {
    static let name = "Waytale"
}

enum AppConfiguration {
    // Replace this with the deployed Vercel URL for device testing.
    // Localhost works only in the iOS simulator when the backend runs on the same Mac.
    static let backendBaseURL = Bundle.main.object(forInfoDictionaryKey: "BackendBaseURL") as? String ?? "http://localhost:3000"

    static var googleMapsAPIKey: String? {
        [
            ProcessInfo.processInfo.environment["GOOGLE_MAPS_API_KEY"],
            ProcessInfo.processInfo.environment["GOOGLE_MAPS_EMBED_API_KEY"],
            Bundle.main.object(forInfoDictionaryKey: "GoogleMapsAPIKey") as? String,
            Bundle.main.object(forInfoDictionaryKey: "GoogleMapsEmbedAPIKey") as? String
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty && !$0.contains("$(") }
    }

    static var googleMapsEmbedAPIKey: String? {
        googleMapsAPIKey
    }
}
