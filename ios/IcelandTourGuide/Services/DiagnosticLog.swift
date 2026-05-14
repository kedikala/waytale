import Foundation
import OSLog

struct DiagnosticEvent: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let category: String
    let message: String

    var line: String {
        let time = timestamp.formatted(date: .omitted, time: .standard)
        return "\(time) [\(category)] \(message)"
    }
}

@MainActor
final class DiagnosticLog: ObservableObject {
    static let shared = DiagnosticLog()

    @Published private(set) var events: [DiagnosticEvent] = []

    private let logger = Logger(subsystem: "com.example.waytale", category: "Diagnostics")
    private let maxEvents = 500

    private init() {}

    func record(_ category: String, _ message: String) {
        let event = DiagnosticEvent(timestamp: Date(), category: category, message: message)
        logger.info("[\(category, privacy: .public)] \(message, privacy: .public)")
        events.insert(event, at: 0)
        if events.count > maxEvents {
            events.removeLast(events.count - maxEvents)
        }
    }

    func clear() {
        events.removeAll()
        record("diagnostics", "cleared log")
    }

    var exportText: String {
        events.reversed().map(\.line).joined(separator: "\n")
    }
}
