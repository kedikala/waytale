import Foundation
import CoreLocation

enum BackendError: Error, LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case server(String)
    case missingTranscript

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL: return "Backend URL is invalid."
        case .invalidResponse: return "Backend returned an invalid response."
        case .server(let message): return message
        case .missingTranscript: return "Transcription response did not include text."
        }
    }
}

struct AskResponse: Decodable {
    let answer: String
}

struct TranscribeResponse: Decodable {
    let transcript: String
}

struct RealtimeClientSecretResponse: Decodable {
    let value: String?
    let clientSecret: RealtimeClientSecret?

    enum CodingKeys: String, CodingKey {
        case value
        case clientSecret = "client_secret"
    }

    var resolvedValue: String? {
        value ?? clientSecret?.value
    }
}

struct RealtimeClientSecret: Decodable {
    let value: String?
}

final class BackendClient {
    var baseURL: URL
    private let session: URLSession

    init(baseURLString: String = AppConfiguration.backendBaseURL, session: URLSession = .shared) {
        self.baseURL = URL(string: baseURLString) ?? URL(string: "http://localhost:3000")!
        self.session = session
    }

    func ask(question: String, coordinate: CLLocationCoordinate2D?, dayId: String, context: GuideContext? = nil) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/ask"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = AskPayload(
            question: question,
            lat: coordinate?.latitude,
            lon: coordinate?.longitude,
            dayId: dayId,
            context: context
        )
        request.httpBody = try JSONEncoder().encode(payload)
        let data = try await perform(request)
        return try JSONDecoder().decode(AskResponse.self, from: data).answer
    }

    func speech(text: String, instructions: String? = nil) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/speech"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SpeechPayload(text: text, instructions: instructions))
        return try await perform(request)
    }

    func transcribe(audioFileURL: URL) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/transcribe"))
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try multipartBody(fileURL: audioFileURL, fieldName: "file", boundary: boundary)
        let data = try await perform(request)
        let response = try JSONDecoder().decode(TranscribeResponse.self, from: data)
        guard !response.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BackendError.missingTranscript
        }
        return response.transcript
    }

    func realtimeClientSecret() async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/realtime/session"))
        request.httpMethod = "GET"
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let data = try await perform(request)
        let response = try JSONDecoder().decode(RealtimeClientSecretResponse.self, from: data)
        guard let value = response.resolvedValue, !value.isEmpty else {
            throw BackendError.server("Realtime session did not include a client secret.")
        }
        return value
    }

    func toolOutput(name: String, rawArguments: String, context: GuideContext?) async throws -> String {
        let parsedArguments = (try? JSONSerialization.jsonObject(with: Data(rawArguments.utf8)) as? [String: Any]) ?? [:]
        if name == "ask_with_web_search" {
            let question = parsedArguments["question"] as? String ?? "Answer the passenger's question."
            let answer = try await ask(
                question: question,
                coordinate: context?.coordinate?.coordinate,
                dayId: context?.activeDayId ?? TripData.defaultDayId,
                context: context
            )
            return encodedJSONObject(["answer": answer])
        }

        var components = URLComponents(url: baseURL.appendingPathComponent("/api/tools/\(name)"), resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = []
        if let coordinate = context?.coordinate {
            queryItems.append(URLQueryItem(name: "lat", value: String(coordinate.latitude)))
            queryItems.append(URLQueryItem(name: "lon", value: String(coordinate.longitude)))
        }
        queryItems.append(URLQueryItem(name: "dayId", value: context?.activeDayId ?? TripData.defaultDayId))
        for (key, value) in parsedArguments {
            queryItems.append(URLQueryItem(name: key, value: String(describing: value)))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw BackendError.invalidBaseURL
        }
        let data = try await perform(URLRequest(url: url))
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if let error = try? JSONDecoder().decode(ServerError.self, from: data) {
                throw BackendError.server(error.error)
            }
            throw BackendError.server("Backend returned HTTP \(http.statusCode).")
        }
        return data
    }

    private func multipartBody(fileURL: URL, fieldName: String, boundary: String) throws -> Data {
        var data = Data()
        let fileData = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent
        data.appendString("--\(boundary)\r\n")
        data.appendString("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\n")
        data.appendString("Content-Type: audio/m4a\r\n\r\n")
        data.append(fileData)
        data.appendString("\r\n--\(boundary)--\r\n")
        return data
    }
}

private func encodedJSONObject(_ object: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: object), let string = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return string
}

private struct AskPayload: Encodable {
    let question: String
    let lat: Double?
    let lon: Double?
    let dayId: String
    let context: GuideContext?
}

private struct SpeechPayload: Encodable {
    let text: String
    let instructions: String?
}

private struct ServerError: Decodable {
    let error: String
}

private extension Data {
    mutating func appendString(_ string: String) {
        append(Data(string.utf8))
    }
}
