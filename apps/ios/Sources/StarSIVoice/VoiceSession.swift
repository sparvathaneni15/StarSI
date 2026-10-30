// The voice-native conversation loop, honoring the contract: waveform over
// the wire, display text rendered locally (SFSpeechRecognizer on the mic;
// server transcripts arrive as metadata and are used as fallback captions).
//
//   capture → VAD end → WAV over WS → [stt → LLM → tts on AWS]
//   → sentence audio frames → queued playback; new speech = barge-in cancel.

import Foundation

#if canImport(AVFoundation) && canImport(Speech)
import AVFoundation
import Speech

public enum VoiceUIEvent: Sendable {
    case listening
    case localCaption(String)          // on-device recognition of the mic
    case serverTranscript(String)      // whisper's authoritative transcript
    case assistantSentence(String)
    case speaking
    case turnEnded
    case failed(String)
}

@MainActor
public final class VoiceSession {
    private let link: VoiceLink
    private let capture = AudioCapture()
    private let player = SpeechPlayer()
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var receiveTask: Task<Void, Never>?
    private var assistantSpeaking = false

    public var onEvent: (VoiceUIEvent) -> Void = { _ in }

    public init(gatewayWS: URL, token: String, model: String? = nil) {
        self.link = VoiceLink(url: gatewayWS, token: token, model: model)
    }

    public func start() throws {
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .voiceChat,
                                     options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true)
        #endif

        startLocalCaptions()

        let events = link.connect()
        receiveTask = Task { [weak self] in
            for await event in events {
                await MainActor.run { self?.handle(event) }
            }
        }

        try capture.start { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch event {
                case .level(let rms):
                    // barge-in: real speech while the assistant is talking
                    if self.assistantSpeaking, rms >= self.capture.speechThreshold {
                        self.player.stopAll()
                        self.link.cancel()
                        self.assistantSpeaking = false
                    }
                case .utterance(let wav):
                    self.onEvent(.listening)
                    self.link.sendUtterance(wav: wav)
                }
            }
        }
        onEvent(.listening)
    }

    public func stop() {
        capture.stop()
        player.stopAll()
        link.close()
        receiveTask?.cancel()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }

    private func handle(_ event: VoiceServerEvent) {
        switch event {
        case .transcript(let role, let text) where role == "user":
            onEvent(.serverTranscript(text))
        case .transcript:
            break
        case .sentence(let text):
            onEvent(.assistantSentence(text))
        case .audio(let wav):
            assistantSpeaking = true
            onEvent(.speaking)
            player.enqueue(wav)
        case .turnEnd:
            assistantSpeaking = false
            onEvent(.turnEnded)
        case .error(let message):
            onEvent(.failed(message))
        }
    }

    /// Local text rendering: on-device speech recognition over the mic feed.
    private func startLocalCaptions() {
        let recognizer = SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else { return }
        recognizer.supportsOnDeviceRecognition = true
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.recognizer = recognizer
        self.recognitionRequest = request

        let input = AVAudioEngineTapBridge.shared
        input.onBuffer = { [weak request] buffer in
            request?.append(buffer)
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let text = result?.bestTranscription.formattedString else { return }
            Task { @MainActor [weak self] in self?.onEvent(.localCaption(text)) }
        }
    }
}

/// AudioCapture owns the engine tap; captions need the same buffers. This
/// tiny bridge lets AudioCapture publish raw buffers without coupling the
/// modules. AudioCapture calls `publish` from its tap.
public final class AVAudioEngineTapBridge: @unchecked Sendable {
    public static let shared = AVAudioEngineTapBridge()
    public var onBuffer: (AVAudioPCMBuffer) -> Void = { _ in }
    public func publish(_ buffer: AVAudioPCMBuffer) { onBuffer(buffer) }
}
#endif
