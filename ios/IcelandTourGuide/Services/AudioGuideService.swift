import Foundation
import AVFoundation
import OSLog
import WebRTC

@MainActor
final class AudioSessionCoordinator {
    static let shared = AudioSessionCoordinator()

    private let logger = Logger(subsystem: "com.example.waytale", category: "AudioSession")
    private let externalPorts: Set<AVAudioSession.Port> = [
        .airPlay,
        .bluetoothA2DP,
        .bluetoothHFP,
        .bluetoothLE,
        .carAudio,
        .headphones,
        .usbAudio
    ]

    private init() {}

    func configureForNarrationPlayback(reason: String) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playback,
            mode: .spokenAudio,
            options: []
        )
        try session.setActive(true)
        logRoute(reason: reason)
    }

    func configureForVoiceCapture(reason: String) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetoothHFP]
        )
        try session.setActive(true)
        try reassertPreferredOutput(reason: reason)
        logRoute(reason: reason)
    }

    func configureForRealtime(reason: String) throws {
        let session = RTCAudioSession.sharedInstance()
        session.lockForConfiguration()
        defer { session.unlockForConfiguration() }

        try session.setCategory(
            .playAndRecord,
            with: [.defaultToSpeaker, .allowBluetoothHFP]
        )
        try session.setMode(.videoChat)
        try session.setActive(true)
        try selectPreferredRealtimeInput(reason: reason)
        session.isAudioEnabled = true
        try reassertPreferredOutput(reason: reason)
        try selectPreferredRealtimeInput(reason: "\(reason) after output route")
        logRoute(reason: reason)
    }

    func deactivateAndNotifyOthers(reason: String) {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            DiagnosticLog.shared.record("audio.route", "audio session deactivated \(reason)")
        } catch {
            logger.error("audio session deactivate failed: \(error.localizedDescription, privacy: .public)")
            DiagnosticLog.shared.record("audio.error", "deactivate failed \(reason): \(error.localizedDescription)")
        }
    }

    func reassertPreferredOutput(reason: String) throws {
        let session = AVAudioSession.sharedInstance()
        try session.overrideOutputAudioPort(hasExternalAudioRoute(session) ? .none : .speaker)
        logRoute(reason: reason)
    }

    func reassertRealtimeInput(reason: String) throws {
        try selectPreferredRealtimeInput(reason: reason)
        logRoute(reason: reason)
    }

    func currentRouteSummary(reason: String) -> String {
        let session = AVAudioSession.sharedInstance()
        let outputs = routeOutputs(session)
        let inputs = routeInputs(session)
        return hasExternalAudioRoute(session) ? "audio route external out=\(outputs) in=\(inputs) \(reason)" : "audio route forced speaker out=\(outputs) in=\(inputs) \(reason)"
    }

    private func hasExternalAudioRoute(_ session: AVAudioSession) -> Bool {
        session.currentRoute.outputs.contains { externalPorts.contains($0.portType) }
    }

    private func selectPreferredRealtimeInput(reason: String) throws {
        let session = AVAudioSession.sharedInstance()
        let inputs = session.availableInputs ?? []
        let inputSummary = inputs
            .map { "\($0.portType.rawValue):\($0.portName)" }
            .joined(separator: ",")
        DiagnosticLog.shared.record("audio.input", "available \(inputSummary.isEmpty ? "none" : inputSummary) \(reason)")

        let preferredOrder: [AVAudioSession.Port] = [
            .carAudio,
            .bluetoothHFP,
            .headsetMic,
            .usbAudio,
            .builtInMic
        ]
        let preferredInputs = preferredOrder.compactMap { port in
            inputs.first { $0.portType == port }
        }
        guard !preferredInputs.isEmpty else {
            DiagnosticLog.shared.record("audio.input", "no preferred realtime input available \(reason)")
            return
        }

        try? session.setPreferredInput(nil)
        for preferredInput in preferredInputs {
            try session.setPreferredInput(preferredInput)
            DiagnosticLog.shared.record("audio.input", "selected \(preferredInput.portType.rawValue):\(preferredInput.portName) \(reason)")
            if routeHasInput(session) {
                DiagnosticLog.shared.record("audio.input", "active \(routeInputs(session)) \(reason)")
                return
            }
        }
        DiagnosticLog.shared.record("audio.input", "selected input did not attach; route in=\(routeInputs(session)) \(reason)")
    }

    private func routeHasInput(_ session: AVAudioSession) -> Bool {
        !session.currentRoute.inputs.isEmpty
    }

    private func routeOutputs(_ session: AVAudioSession) -> String {
        let outputs = session.currentRoute.outputs.map(\.portType.rawValue).joined(separator: ",")
        return outputs.isEmpty ? "none" : outputs
    }

    private func routeInputs(_ session: AVAudioSession) -> String {
        let inputs = session.currentRoute.inputs.map(\.portType.rawValue).joined(separator: ",")
        return inputs.isEmpty ? "none" : inputs
    }

    private func logRoute(reason: String) {
        logger.debug("\(self.currentRouteSummary(reason: reason), privacy: .public)")
        DiagnosticLog.shared.record("audio.route", currentRouteSummary(reason: reason))
    }
}

@MainActor
final class AudioGuideService: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var nowPlayingTitle: String?
    @Published private(set) var errorMessage: String?

    var onPlaybackFinished: ((String) -> Void)?
    var onPlaybackFailed: ((String, Error?) -> Void)?

    private var player: AVPlayer?
    private var queue: [(title: String, url: URL)] = []

    init() {
        observeInterruptions()
    }

    @discardableResult
    func configureSession() -> Bool {
        do {
            try AudioSessionCoordinator.shared.configureForNarrationPlayback(reason: "narration playback")
            return true
        } catch {
            errorMessage = error.localizedDescription
            DiagnosticLog.shared.record("audio.error", "configure session failed: \(error.localizedDescription)")
            return false
        }
    }

    func enqueue(title: String, audioURL: URL) {
        DiagnosticLog.shared.record("audio.queue", "enqueue \(title)")
        queue.append((title, audioURL))
        if !isPlaying {
            playNext()
        }
    }

    func play(title: String, audioURL: URL) {
        DiagnosticLog.shared.record("audio.play", "requested \(title)")
        stop(shouldNotifyOthers: false)
        queue = [(title, audioURL)]
        playNext()
    }

    func playSequence(_ items: [(title: String, audioURL: URL)]) {
        guard let first = items.first else { return }
        DiagnosticLog.shared.record("audio.play", "requested sequence \(first.title) count=\(items.count)")
        stop(shouldNotifyOthers: false)
        queue = items.map { ($0.title, $0.audioURL) }
        playNext()
    }

    func stop(shouldNotifyOthers: Bool = true) {
        if isPlaying || player != nil || !queue.isEmpty {
            DiagnosticLog.shared.record("audio.stop", "stopping \(nowPlayingTitle ?? "unknown")")
        }
        player?.pause()
        player = nil
        queue.removeAll()
        isPlaying = false
        nowPlayingTitle = nil
        if shouldNotifyOthers {
            AudioSessionCoordinator.shared.deactivateAndNotifyOthers(reason: "audio guide stopped")
        }
    }

    private func playNext() {
        guard !queue.isEmpty else {
            isPlaying = false
            nowPlayingTitle = nil
            AudioSessionCoordinator.shared.deactivateAndNotifyOthers(reason: "audio guide finished")
            return
        }
        let item = queue.removeFirst()
        guard FileManager.default.fileExists(atPath: item.url.path) else {
            errorMessage = "Audio file is missing for \(item.title)."
            DiagnosticLog.shared.record("audio.error", "missing file for \(item.title)")
            playNext()
            return
        }
        guard configureSession() else {
            onPlaybackFailed?(item.title, errorMessage.map { AudioGuideError.sessionConfiguration($0) })
            playNext()
            return
        }
        nowPlayingTitle = item.title
        DiagnosticLog.shared.record("audio.play", "started \(item.title)")
        let playerItem = AVPlayerItem(url: item.url)
        player = AVPlayer(playerItem: playerItem)
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                DiagnosticLog.shared.record("audio.play", "finished \(item.title)")
                self?.onPlaybackFinished?(item.title)
                self?.playNext()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                self?.errorMessage = error?.localizedDescription ?? "Audio playback failed."
                DiagnosticLog.shared.record("audio.error", "failed \(item.title): \(self?.errorMessage ?? "unknown")")
                self?.onPlaybackFailed?(item.title, error)
                self?.playNext()
            }
        }
        isPlaying = true
        player?.play()
    }

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard
                let info = notification.userInfo,
                let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                let type = AVAudioSession.InterruptionType(rawValue: rawType)
            else { return }
            Task { @MainActor in
                switch type {
                case .began:
                    DiagnosticLog.shared.record("audio.interruption", "began")
                    self?.player?.pause()
                    self?.isPlaying = false
                case .ended:
                    DiagnosticLog.shared.record("audio.interruption", "ended")
                    self?.player?.play()
                    self?.isPlaying = self?.player != nil
                @unknown default:
                    break
                }
            }
        }
    }
}

private enum AudioGuideError: LocalizedError {
    case sessionConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .sessionConfiguration(let message):
            return message
        }
    }
}
