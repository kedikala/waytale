import Foundation
import AVFoundation
import CoreLocation

@MainActor
final class VoiceQuestionService: ObservableObject {
    @Published private(set) var isRecordingQuestion = false
    @Published private(set) var errorMessage: String?

    private let backend: BackendClient
    private let audioGuide: AudioGuideService
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    init(backend: BackendClient, audioGuide: AudioGuideService) {
        self.backend = backend
        self.audioGuide = audioGuide
    }

    func requestPermissions() async {
        _ = await requestMicrophonePermission()
    }

    func requestMicrophonePermission() async -> Bool {
        let microphoneAllowed = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { allowed in continuation.resume(returning: allowed) }
        }
        if !microphoneAllowed {
            errorMessage = "Microphone permission is required for Ask Waytale."
        }
        return microphoneAllowed
    }

    func recordQuestion() throws {
        try configureMicSession()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("question-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.record()
        recordingURL = url
        isRecordingQuestion = true
    }

    func stopAndAnswerRecordedQuestion(context: GuideContext) async {
        recorder?.stop()
        isRecordingQuestion = false
        guard let recordingURL else { return }
        do {
            let question = try await backend.transcribe(audioFileURL: recordingURL)
            try? FileManager.default.removeItem(at: recordingURL)
            await answer(question: question, context: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func answer(question: String, context: GuideContext) async {
        do {
            let answer = try await backend.ask(
                question: question,
                coordinate: context.coordinate?.coordinate,
                dayId: context.activeDayId,
                context: context
            )
            let audioData = try await backend.speech(
                text: answer,
                instructions: "Speak as a concise, helpful Iceland road-trip guide with a warm, lower-register storyteller delivery."
            )
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("answer-\(UUID().uuidString).mp3")
            try audioData.write(to: url, options: [.atomic])
            audioGuide.play(title: "Guide Answer", audioURL: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func configureMicSession() throws {
        try AudioSessionCoordinator.shared.configureForVoiceCapture(reason: "question mic")
    }
}
