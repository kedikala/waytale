import Foundation
import AVFoundation
import OSLog
import WebRTC

@MainActor
final class RealtimeGuideService: NSObject, ObservableObject {
    @Published private(set) var isSessionActive = false
    @Published private(set) var status = "Idle"
    @Published private(set) var transcript = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var debugLog = ""
    @Published private(set) var isPreparingRealtimeAudio = false

    var onSessionEnded: (() -> Void)?

    private let backend: BackendClient
    private let factory: RTCPeerConnectionFactory
    private let logger = Logger(subsystem: "com.example.waytale", category: "RealtimeGuide")
    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private var audioTrack: RTCAudioTrack?
    private var activeContext: GuideContext?
    private var activeResponseId: String?
    private var pendingInitialQuestion: String?
    private var statsTask: Task<Void, Never>?
    private var micResumeTask: Task<Void, Never>?
    private var handledFunctionCallIds = Set<String>()
    private var shouldCreateResponseAfterCurrentResponse = false
    private var lastAssistantResponseCompletedAt: Date?
    private var lastEndSessionCommandAt: Date?
    private var routeChangeObserver: NSObjectProtocol?
    private var startupTask: Task<Void, Never>?

    init(backend: BackendClient) {
        self.backend = backend
        RTCInitializeSSL()
        RTCPeerConnectionFactory.initialize()
        self.factory = RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
        super.init()
    }

    deinit {
        RTCCleanupSSL()
    }

    func startSession(context: GuideContext, initialQuestion: String? = nil) {
        DiagnosticLog.shared.record("realtime", "start session initialQuestion=\(initialQuestion?.isEmpty == false)")
        startupTask?.cancel()
        stopPeerConnection(sendEndedEvent: false)
        errorMessage = nil
        status = "Preparing realtime audio..."
        transcript = ""
        isSessionActive = true
        isPreparingRealtimeAudio = false
        activeContext = context
        pendingInitialQuestion = initialQuestion

        startupTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await self?.connect(context: context, initialQuestion: initialQuestion)
        }
    }

    func endSession(reason: String = "manual") {
        DiagnosticLog.shared.record("realtime", "end session requested reason=\(reason)")
        startupTask?.cancel()
        startupTask = nil
        stopPeerConnection(sendEndedEvent: true)
    }

    func stopCurrentResponse() {
        sendEvent(["type": "response.cancel"])
        sendEvent(["type": "output_audio_buffer.clear"])
        status = "Stopped current response"
        appendDebug("sent response.cancel + output_audio_buffer.clear")
    }

    func updateContext(_ context: GuideContext) {
        activeContext = context
    }

    func navigationStateDidChange(isNavigating: Bool, context: GuideContext) {
        updateContext(context)
        guard isSessionActive else { return }
        appendDebug("navigation \(isNavigating ? "started" : "stopped") while realtime active")
        reassertRealtimeAudioAfterNavigationChange()
    }

    func prepareForNavigationActivation() {
        isPreparingRealtimeAudio = true
        status = "Preparing realtime audio..."
        do {
            try configureAudioSession(installRouteObserver: false)
            appendDebug("prepared realtime audio while navigation active")
        } catch {
            errorMessage = error.localizedDescription
            appendDebug("navigation realtime audio prep failed: \(error.localizedDescription)")
        }
    }

    func clearRealtimeAudioPreparation() {
        isPreparingRealtimeAudio = false
    }

    private func connect(context: GuideContext, initialQuestion: String?) async {
        do {
            status = "Connecting native WebRTC..."
            isPreparingRealtimeAudio = false
            appendDebug("connect step: configure audio")
            try configureAudioSession()
            appendDebug("connect step: request client secret")
            let clientSecret = try await backend.realtimeClientSecret()
            guard isSessionActive else {
                appendDebug("connect cancelled: session inactive after client secret")
                return
            }
            appendDebug("connect step: create peer connection")
            let peerConnection = makePeerConnection()
            self.peerConnection = peerConnection

            let audioSource = factory.audioSource(with: RTCMediaConstraints(
                mandatoryConstraints: nil,
                optionalConstraints: [
                    "googEchoCancellation": "true",
                    "googAutoGainControl": "true",
                    "googNoiseSuppression": "true",
                    "googHighpassFilter": "true"
                ]
            ))
            let audioTrack = factory.audioTrack(with: audioSource, trackId: "iceland-guide-audio")
            audioTrack.isEnabled = true
            self.audioTrack = audioTrack

            let transceiverInit = RTCRtpTransceiverInit()
            transceiverInit.direction = .sendRecv
            transceiverInit.streamIds = ["iceland-guide-stream"]
            peerConnection.addTransceiver(with: audioTrack, init: transceiverInit)

            let dataConfig = RTCDataChannelConfiguration()
            guard let dataChannel = peerConnection.dataChannel(forLabel: "oai-events", configuration: dataConfig) else {
                throw RealtimeError.connection("Could not create Realtime data channel.")
            }
            dataChannel.delegate = self
            self.dataChannel = dataChannel

            let offer = try await offer(for: peerConnection)
            guard isSessionActive else {
                appendDebug("connect cancelled: session inactive after offer")
                return
            }
            appendDebug("offer audio=\(offer.sdp.contains("m=audio")) sendrecv=\(offer.sdp.contains("a=sendrecv"))")
            appendDebug("connect step: set local description")
            try await setLocalDescription(offer, peerConnection: peerConnection)
            appendDebug("connect step: exchange sdp")
            let answerSDP = try await exchangeSDP(offer.sdp, clientSecret: clientSecret)
            guard isSessionActive else {
                appendDebug("connect cancelled: session inactive after sdp exchange")
                return
            }
            appendDebug("answer audio=\(answerSDP.contains("m=audio"))")
            appendDebug("connect step: set remote description")
            try await setRemoteDescription(RTCSessionDescription(type: .answer, sdp: answerSDP), peerConnection: peerConnection)
            reassertLoudspeakerRouteIfPossible(reason: "remote description set")
            startStatsLoop()
        } catch {
            isPreparingRealtimeAudio = false
            errorMessage = error.localizedDescription
            status = "Realtime error"
            appendDebug("connect error: \(type(of: error)) \(error.localizedDescription) taskCancelled=\(Task.isCancelled)")
            stopPeerConnection(sendEndedEvent: true)
        }
    }

    private func makePeerConnection() -> RTCPeerConnection {
        let configuration = RTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan
        configuration.continualGatheringPolicy = .gatherContinually
        configuration.tcpCandidatePolicy = .enabled
        configuration.bundlePolicy = .maxBundle
        configuration.rtcpMuxPolicy = .require
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let peerConnection = factory.peerConnection(with: configuration, constraints: constraints, delegate: self) else {
            preconditionFailure("RTCPeerConnectionFactory failed to create a peer connection.")
        }
        return peerConnection
    }

    private func configureAudioSession(installRouteObserver: Bool = true) throws {
        try AudioSessionCoordinator.shared.configureForRealtime(reason: "realtime audio session configured")
        if installRouteObserver {
            installRouteChangeObserverIfNeeded()
        }
        appendDebug("audio session realtime speaker/HFP loudspeaker")
    }

    private func installRouteChangeObserverIfNeeded() {
        guard routeChangeObserver == nil else { return }
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reassertLoudspeakerRouteIfPossible(reason: "route changed")
            }
        }
    }

    private func removeRouteChangeObserver() {
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
            self.routeChangeObserver = nil
        }
    }

    private func reassertLoudspeakerRouteIfPossible(reason: String) {
        do {
            try AudioSessionCoordinator.shared.reassertPreferredOutput(reason: reason)
            try AudioSessionCoordinator.shared.reassertRealtimeInput(reason: "\(reason) input check")
            appendDebug(AudioSessionCoordinator.shared.currentRouteSummary(reason: reason))
        } catch {
            appendDebug("audio route failed: \(error.localizedDescription)")
        }
    }

    private func reassertRealtimeAudioAfterNavigationChange() {
        Task { [weak self] in
            await MainActor.run {
                guard let self, self.isSessionActive else { return }
                do {
                    try self.configureAudioSession()
                } catch {
                    self.appendDebug("audio session refresh failed: \(error.localizedDescription)")
                }
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run {
                guard let self, self.isSessionActive else { return }
                self.reassertLoudspeakerRouteIfPossible(reason: "navigation audio settled")
            }
        }
    }

    private func offer(for peerConnection: RTCPeerConnection) async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation { continuation in
            let constraints = RTCMediaConstraints(
                mandatoryConstraints: ["OfferToReceiveAudio": "true"],
                optionalConstraints: nil
            )
            peerConnection.offer(for: constraints) { description, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let description {
                    continuation.resume(returning: description)
                } else {
                    continuation.resume(throwing: RealtimeError.connection("WebRTC did not create an SDP offer."))
                }
            }
        }
    }

    private func setLocalDescription(_ description: RTCSessionDescription, peerConnection: RTCPeerConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.setLocalDescription(description) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func setRemoteDescription(_ description: RTCSessionDescription, peerConnection: RTCPeerConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.setRemoteDescription(description) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func exchangeSDP(_ offerSDP: String, clientSecret: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/realtime/calls")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(clientSecret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/sdp", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(offerSDP.utf8)
        appendDebug("sdp exchange request bytes=\(request.httpBody?.count ?? 0)")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RealtimeError.connection("OpenAI Realtime SDP exchange returned an invalid response.")
        }
        appendDebug("sdp exchange status=\(http.statusCode) bytes=\(data.count)")
        guard (200..<300).contains(http.statusCode), let answer = String(data: data, encoding: .utf8) else {
            let message = String(data: data, encoding: .utf8) ?? "OpenAI Realtime SDP exchange failed."
            throw RealtimeError.connection(message)
        }
        return answer
    }

    private func startStatsLoop() {
        statsTask?.cancel()
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                await self?.collectStats()
            }
        }
    }

    private func collectStats() async {
        guard let peerConnection else { return }
        let report = await withCheckedContinuation { continuation in
            peerConnection.statistics { statsReport in
                continuation.resume(returning: statsReport)
            }
        }
        var outboundAudio: RTCStatistics?
        for stat in report.statistics.values {
            if stat.type == "outbound-rtp", statString(stat.values["kind"]).contains("audio") {
                outboundAudio = stat
                break
            }
        }
        if let outboundAudio {
            let packets = statString(outboundAudio.values["packetsSent"])
            let bytes = statString(outboundAudio.values["bytesSent"])
            appendDebug("native mic packets=\(packets) bytes=\(bytes)")
        } else {
            appendDebug("native mic stats unavailable")
        }
    }

    private func statString(_ value: NSObject?) -> String {
        value?.description ?? "?"
    }

    private func sendContextMessage(initialQuestion: String?) {
        guard let activeContext else { return }
        let contextText = encodedJSON(activeContext).prefix(6000)
        sendUserText(
            """
            Current app trip context for this live voice session:
            \(contextText)
            Use this silently as location and itinerary context. Do not read raw coordinates unless asked.
            """
        )
        if let initialQuestion, !initialQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sendUserText("Passenger question: \(initialQuestion)")
            sendEvent(["type": "response.create"])
        } else {
            sendUserText("Say exactly: Hello, how can I help?")
            sendEvent(["type": "response.create"])
        }
    }

    private func sendUserText(_ text: String) {
        sendEvent([
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [
                    [
                        "type": "input_text",
                        "text": text
                    ]
                ]
            ]
        ])
    }

    private func sendEvent(_ event: [String: Any]) {
        guard let dataChannel, dataChannel.readyState == .open else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: event), let string = String(data: data, encoding: .utf8) else { return }
        dataChannel.sendData(RTCDataBuffer(data: Data(string.utf8), isBinary: false))
    }

    private func handleRealtimeEvent(_ event: [String: Any]) {
        guard let type = event["type"] as? String else { return }
        if [
            "session.created",
            "session.updated",
            "input_audio_buffer.speech_started",
            "input_audio_buffer.speech_stopped",
            "conversation.item.input_audio_transcription.completed",
            "response.created",
            "response.done",
            "response.audio.done",
            "response.audio_transcript.done",
            "response.cancelled",
            "response.output_item.done",
            "response.function_call_arguments.done"
        ].contains(type) {
            appendDebug(summary(for: event, type: type))
        }

        switch type {
        case "response.created":
            if let response = event["response"] as? [String: Any] {
                activeResponseId = response["id"] as? String
            }
            micResumeTask?.cancel()
            micResumeTask = nil
            setMicrophoneEnabled(!shouldMuteMicrophoneDuringAssistantResponse, reason: "assistant response active")
            reassertLoudspeakerRouteIfPossible(reason: "response created")
            errorMessage = nil
        case "response.done":
            var wasCancelledByUserSpeech = false
            if let response = event["response"] as? [String: Any],
               let status = response["status"] as? String {
                let details = response["status_details"] as? [String: Any]
                let reason = details?["reason"] as? String
                wasCancelledByUserSpeech = status == "cancelled" && reason == "turn_detected"
                if status != "completed" {
                    appendDebug("response status \(status)")
                }
            }
            activeResponseId = nil
            lastAssistantResponseCompletedAt = Date()
            shouldCreateResponseAfterCurrentResponse = false
            if !wasCancelledByUserSpeech {
                sendEvent(["type": "input_audio_buffer.clear"])
            }
            if shouldMuteMicrophoneDuringAssistantResponse, !wasCancelledByUserSpeech {
                scheduleMicrophoneResume(afterNanoseconds: 4_000_000_000, reason: "assistant response done")
            }
        case "response.cancelled":
            activeResponseId = nil
            shouldCreateResponseAfterCurrentResponse = false
            sendEvent(["type": "input_audio_buffer.clear"])
            scheduleMicrophoneResume(afterNanoseconds: 700_000_000, reason: "assistant response cancelled")
        case "conversation.item.input_audio_transcription.completed":
            let text = event["transcript"] as? String ?? ""
            transcript = text
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            if isEndSessionCommand(text) {
                lastEndSessionCommandAt = Date()
                endSession(reason: "explicit transcript command")
                return
            }
            if isStopCommand(text) {
                stopCurrentResponse()
                return
            }
            if activeResponseId == nil, shouldMuteMicrophoneDuringAssistantResponse, !shouldStartAssistantTurn(for: text) {
                sendEvent(["type": "input_audio_buffer.clear"])
            }
        case "response.function_call_arguments.done":
            Task { [weak self] in
                await self?.respondToFunctionCall(event)
            }
        case "error":
            let error = event["error"] as? [String: Any]
            let message = error?["message"] as? String ?? "Realtime API error."
            appendDebug("api error: \(message)")
            if message.localizedCaseInsensitiveContains("active response in progress") {
                status = "Realtime listening"
                errorMessage = nil
                appendDebug("ignored active-response echo race")
            } else {
                errorMessage = message
                status = "Realtime error"
                setMicrophoneEnabled(true, reason: "api error")
            }
        default:
            break
        }
    }

    private func respondToFunctionCall(_ event: [String: Any]) async {
        let item = event["item"] as? [String: Any]
        let name = item?["name"] as? String ?? event["name"] as? String
        let callId = item?["call_id"] as? String ?? event["call_id"] as? String
        let arguments = item?["arguments"] as? String ?? event["arguments"] as? String ?? "{}"
        guard let name, let callId else { return }
        guard !handledFunctionCallIds.contains(callId) else {
            appendDebug("ignored duplicate tool call \(callId)")
            return
        }
        handledFunctionCallIds.insert(callId)
        if name == "end_realtime_session" {
            guard recentlyHeardEndSessionCommand else {
                sendFunctionCallOutput(callId: callId, output: #"{"ended":false,"reason":"No recent explicit end-session phrase was transcribed. Keep the live session open."}"#)
                appendDebug("ignored end session tool call without recent end command")
                createResponseWhenReady()
                return
            }

            sendFunctionCallOutput(callId: callId, output: #"{"ended":true}"#)
            appendDebug("end session tool called after explicit command")
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 150_000_000)
                await MainActor.run {
                    self?.endSession(reason: "realtime tool")
                }
            }
            return
        }
        do {
            let output = try await backend.toolOutput(name: name, rawArguments: arguments, context: activeContext)
            sendFunctionCallOutput(callId: callId, output: output)
            createResponseWhenReady()
        } catch {
            sendFunctionCallOutput(callId: callId, output: #"{"error":"Tool call failed"}"#)
            createResponseWhenReady()
        }
    }

    private func sendFunctionCallOutput(callId: String, output: String) {
        sendEvent([
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": callId,
                "output": output
            ]
        ])
    }

    private func createResponseWhenReady() {
        if activeResponseId == nil {
            sendEvent(["type": "response.create"])
            appendDebug("sent response.create")
        } else {
            shouldCreateResponseAfterCurrentResponse = true
            appendDebug("queued response.create until response.done")
        }
    }

    private func setMicrophoneEnabled(_ enabled: Bool, reason: String) {
        guard audioTrack?.isEnabled != enabled else { return }
        audioTrack?.isEnabled = enabled
        appendDebug("mic \(enabled ? "enabled" : "muted") \(reason)")
    }

    private var shouldMuteMicrophoneDuringAssistantResponse: Bool {
        false
    }

    private func scheduleMicrophoneResume(afterNanoseconds delay: UInt64, reason: String) {
        micResumeTask?.cancel()
        micResumeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            await MainActor.run {
                guard let self, self.isSessionActive, self.activeResponseId == nil else { return }
                self.setMicrophoneEnabled(true, reason: reason)
                self.sendEvent(["type": "input_audio_buffer.clear"])
            }
        }
        appendDebug("mic resume scheduled \(Double(delay) / 1_000_000_000)s \(reason)")
    }

    private func stopPeerConnection(sendEndedEvent: Bool) {
        statsTask?.cancel()
        statsTask = nil
        micResumeTask?.cancel()
        micResumeTask = nil
        dataChannel?.close()
        dataChannel = nil
        peerConnection?.close()
        peerConnection = nil
        removeRouteChangeObserver()
        audioTrack = nil
        activeResponseId = nil
        pendingInitialQuestion = nil
        handledFunctionCallIds.removeAll()
        shouldCreateResponseAfterCurrentResponse = false
        lastAssistantResponseCompletedAt = nil
        lastEndSessionCommandAt = nil
        if sendEndedEvent {
            isSessionActive = false
            isPreparingRealtimeAudio = false
            status = "Realtime session ended"
            appendDebug("session ended")
            AudioSessionCoordinator.shared.deactivateAndNotifyOthers(reason: "realtime session ended")
            onSessionEnded?()
        }
    }

    private func encodedJSON<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value), let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    private func appendDebug(_ message: String) {
        logger.info("\(message, privacy: .public)")
        DiagnosticLog.shared.record("realtime", message)
        let line = "\(Date().formatted(date: .omitted, time: .standard)): \(message)"
        let combined = debugLog.isEmpty ? line : "\(line)\n\(debugLog)"
        debugLog = String(combined.prefix(1200))
    }

    private func summary(for event: [String: Any], type: String) -> String {
        if type == "conversation.item.input_audio_transcription.completed" {
            let text = event["transcript"] as? String ?? ""
            return "heard: \(String(text.prefix(80)))"
        }
        if type == "response.done", let response = event["response"] as? [String: Any] {
            let status = response["status"] as? String ?? "unknown"
            if let details = response["status_details"] as? [String: Any],
               let reason = details["reason"] as? String {
                return "event \(type) status=\(status) reason=\(reason)"
            }
            return "event \(type) status=\(status)"
        }
        return "event \(type)"
    }

    private func isStopCommand(_ text: String) -> Bool {
        let normalized = normalizedCommand(text)
        return [
            "stop", "stop talking", "stop audio", "stop the audio",
            "pause", "pause audio", "pause the audio",
            "be quiet", "quiet", "please stop"
        ].contains(normalized)
    }

    private func isEndSessionCommand(_ text: String) -> Bool {
        let normalized = normalizedCommand(text)
        let exactCommands = [
            "end session",
            "end sessions",
            "end the session",
            "end the sessions",
            "ending session",
            "terminate session",
            "terminate the session",
            "stop session",
            "stop the session",
            "stop this session",
            "stop conversation",
            "stop the conversation",
            "close session",
            "close the session",
            "hang up",
            "disconnect",
            "disconnect waytale",
            "we are done with this session",
            "we re done with this session",
            "i am done with this session",
            "i m done with this session",
            "that is all for this session",
            "that s all for this session"
        ]
        if exactCommands.contains(normalized) {
            return true
        }
        return normalized.contains("end the session")
            || normalized.contains("end the sessions")
            || normalized.contains("end session")
            || normalized.contains("end sessions")
            || normalized.contains("terminate session")
            || normalized.contains("close the session")
            || normalized.contains("stop the session")
            || normalized.contains("stop this session")
            || normalized.contains("stop the conversation")
            || normalized.contains("hang up")
            || normalized.contains("disconnect waytale")
            || normalized == "disconnect"
            || normalized.contains("you can end")
            || normalized.contains("you can stop the session")
            || normalized.contains("we are done with this session")
            || normalized.contains("we re done with this session")
            || normalized.contains("i am done with this session")
            || normalized.contains("i m done with this session")
            || normalized.contains("that is all for this session")
            || normalized.contains("that s all for this session")
    }

    private var recentlyHeardEndSessionCommand: Bool {
        guard let lastEndSessionCommandAt else { return false }
        return Date().timeIntervalSince(lastEndSessionCommandAt) < 8
    }

    private func shouldStartAssistantTurn(for text: String) -> Bool {
        let normalized = normalizedCommand(text)
        let words = normalized.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return false }

        let commandPrefixes = [
            "what", "why", "how", "where", "when", "who", "which",
            "tell", "tell me", "show", "check", "look", "find", "search",
            "explain", "describe", "give", "can", "could", "should",
            "weather", "road", "roads", "safety", "safe", "volcano", "eruption",
            "nearby", "food", "waterfalls", "waterfall", "history", "geology",
            "continue", "repeat", "again"
        ]
        let looksIntentional = commandPrefixes.contains { prefix in
            normalized == prefix || normalized.hasPrefix("\(prefix) ")
        }

        if looksIntentional {
            return true
        }

        if let completedAt = lastAssistantResponseCompletedAt,
           Date().timeIntervalSince(completedAt) < 8 {
            appendDebug("ignored likely echo after response: \(String(text.prefix(50)))")
            return false
        }

        if words.count < 4 {
            appendDebug("ignored short transcript: \(String(text.prefix(50)))")
            return false
        }

        return true
    }

    private func normalizedCommand(_ text: String) -> String {
        text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[^\w\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

}

extension RealtimeGuideService: RTCDataChannelDelegate {
    nonisolated func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        Task { @MainActor in
            self.appendDebug("data channel \(dataChannel.readyState.rawValue)")
            if dataChannel.readyState == .open {
                self.status = "Realtime listening"
                self.isSessionActive = true
                self.errorMessage = nil
                self.sendContextMessage(initialQuestion: self.pendingInitialQuestion)
                self.pendingInitialQuestion = nil
            }
        }
    }

    nonisolated func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        guard
            let string = String(data: buffer.data, encoding: .utf8),
            let data = string.data(using: .utf8),
            let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        Task { @MainActor in
            self.handleRealtimeEvent(event)
        }
    }
}

extension RealtimeGuideService: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        Task { @MainActor in self.appendDebug("signaling \(stateChanged.rawValue)") }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        Task { @MainActor in self.appendDebug("remote stream audio=\(stream.audioTracks.count)") }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        Task { @MainActor in self.appendDebug("ice \(newState.rawValue)") }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        Task { @MainActor in self.appendDebug("gathering \(newState.rawValue)") }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        dataChannel.delegate = self
        Task { @MainActor in
            self.dataChannel = dataChannel
            self.appendDebug("remote data channel opened")
        }
    }
}

private enum RealtimeError: LocalizedError {
    case connection(String)

    var errorDescription: String? {
        switch self {
        case .connection(let message): return message
        }
    }
}
