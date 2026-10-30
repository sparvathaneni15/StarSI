// App-wide state: settings, the SSH tunnel, the chat engine, the voice
// session, and the bubble list the UI renders.

import Foundation
import Network
import Observation
import StarSIClient
import StarSIRouter
import StarSITunnel
import StarSIVoice
import UIKit

struct ChatBubble: Identifiable {
    let id = UUID()
    var role: String
    var text: String
    var servedBy: TargetID?
    var isOfflineFallback = false
    var isWakingGPU = false
    var isVoice = false
    var firstTokenMs: Int?
    var failed = false
}

@MainActor
@Observable
final class AppState {
    // MARK: Settings (hosts in UserDefaults, token + device key in Keychain)
    var awsHost: String {
        didSet { UserDefaults.standard.set(awsHost, forKey: "awsHost") }
    }
    var awsHostKey: String {
        didSet { UserDefaults.standard.set(awsHostKey, forKey: "awsHostKey") }
    }
    var gpuEnabled: Bool {
        didSet { UserDefaults.standard.set(gpuEnabled, forKey: "gpuEnabled") }
    }
    var allowPrivateOverOwnCloud: Bool {
        didSet { UserDefaults.standard.set(allowPrivateOverOwnCloud,
                                           forKey: "allowPrivateOverOwnCloud") }
    }
    var forcedTarget: TargetID? {
        didSet { UserDefaults.standard.set(forcedTarget?.rawValue ?? "", forKey: "forcedTarget") }
    }
    var deviceToken: String {
        didSet { Keychain.set(deviceToken, for: "device-token") }
    }

    /// The phone's SSH public key — what you paste into authorized_keys.d/aws.
    let devicePublicKey: String

    // MARK: Chat + voice
    var bubbles: [ChatBubble] = []
    var isStreaming = false
    var voiceActive = false
    var voiceStatus = ""

    let log = RoutingLog()
    private let engine: ChatEngine
    private let tunnel: TunnelManager
    private var voice: VoiceSession?
    private let pathMonitor = NWPathMonitor()
    private var network: NetworkKind = .offline

    /// Local ports are fixed by infra/tunnels/tunnels.toml.
    static let gatewayLocalURL = URL(string: "http://127.0.0.1:8484")!
    static let voiceWSURL = URL(string: "ws://127.0.0.1:8484/v1/voice")!

    init() {
        let defaults = UserDefaults.standard
        awsHost = defaults.string(forKey: "awsHost") ?? ""
        awsHostKey = defaults.string(forKey: "awsHostKey") ?? ""
        gpuEnabled = defaults.object(forKey: "gpuEnabled") as? Bool ?? true
        allowPrivateOverOwnCloud = defaults.bool(forKey: "allowPrivateOverOwnCloud")
        forcedTarget = TargetID(rawValue: defaults.string(forKey: "forcedTarget") ?? "")
        let token = Keychain.get("device-token") ?? ""
        deviceToken = token

        let key = DeviceKey.loadOrCreate()
        devicePublicKey = DeviceKey.openSSHPublicKey(key)

        tunnel = TunnelManager(
            endpoint: SSHEndpoint(
                host: defaults.string(forKey: "awsHost") ?? "",
                hostKey: defaults.string(forKey: "awsHostKey") ?? ""
            ),
            forwards: [
                Forward(localPort: 8484, targetPort: 30086),  // gateway
                Forward(localPort: 8486, targetPort: 18484),  // Pi memory (reverse tunnel)
            ],
            key: key
        )

        let tokenProvider: @Sendable () -> String? = { Keychain.get("device-token") }
        engine = ChatEngine(
            routerModel: StubRouterModel(),
            transports: [
                .http: SSHTunnelTransport(tunnel: tunnel,
                                          localEndpoint: Self.gatewayLocalURL,
                                          token: tokenProvider),
            ],
            log: log
        )

        pathMonitor.pathUpdateHandler = { [weak self] path in
            let kind: NetworkKind =
                path.status != .satisfied ? .offline
                : path.usesInterfaceType(.cellular) ? .cellular : .wifi
            Task { @MainActor in self?.network = kind }
        }
        pathMonitor.start(queue: DispatchQueue(label: "starsi.path"))
    }

    var targets: [Target] {
        [
            Target(id: .iphone, enabled: false),  // on-device model lands in Phase 4
            Target(id: .awsCPU, endpoint: Self.gatewayLocalURL, enabled: !awsHost.isEmpty),
            Target(id: .awsGPU, endpoint: Self.gatewayLocalURL,
                   enabled: gpuEnabled && !awsHost.isEmpty),
        ]
    }

    // MARK: Text chat

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }
        isStreaming = true
        defer { isStreaming = false }

        bubbles.append(ChatBubble(role: "user", text: trimmed))
        let sendStart = Date()

        var tunnelUp = false
        if network != .offline && !awsHost.isEmpty {
            tunnelUp = await tunnel.ensureUp()
        }
        let signals = await engine.gatherSignals(
            targets: targets,
            tunnelUp: tunnelUp,
            network: network,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
        let reply = await engine.send(
            trimmed, targets: targets, signals: signals,
            config: RoutingConfig(allowPrivateOverOwnCloud: allowPrivateOverOwnCloud),
            forced: forcedTarget)

        var bubble = ChatBubble(role: "assistant", text: "",
                                servedBy: reply.decision.target,
                                isOfflineFallback: reply.decision.isOfflineFallback,
                                isWakingGPU: reply.decision.requiresWake)
        bubbles.append(bubble)
        let index = bubbles.count - 1

        do {
            for try await event in reply.stream {
                if case .token(let text) = event {
                    if bubble.firstTokenMs == nil {
                        bubble.firstTokenMs = Int(Date().timeIntervalSince(sendStart) * 1000)
                    }
                    bubble.text += text
                    bubbles[index] = bubble
                }
            }
            await engine.recordReply(bubble.text)
        } catch {
            bubble.failed = true
            bubble.text = bubble.text.isEmpty
                ? "Couldn't reach \(reply.decision.target.displayName): \(error.localizedDescription)"
                : bubble.text
            bubbles[index] = bubble
        }
    }

    // MARK: Voice

    func toggleVoice() async {
        if voiceActive {
            voice?.stop()
            voice = nil
            voiceActive = false
            voiceStatus = ""
            return
        }
        guard await tunnel.ensureUp() else {
            voiceStatus = "tunnel down"
            return
        }
        let session = VoiceSession(gatewayWS: Self.voiceWSURL, token: deviceToken,
                                   model: forcedTarget?.modelID)
        session.onEvent = { [weak self] event in self?.handleVoice(event) }
        do {
            try session.start()
            voice = session
            voiceActive = true
            voiceStatus = "listening"
        } catch {
            voiceStatus = "mic unavailable: \(error.localizedDescription)"
        }
    }

    private func handleVoice(_ event: VoiceUIEvent) {
        switch event {
        case .listening:
            voiceStatus = "listening"
        case .localCaption(let text):
            upsertVoiceBubble(role: "user", text: text)
        case .serverTranscript(let text):
            upsertVoiceBubble(role: "user", text: text, freeze: true)
        case .assistantSentence(let text):
            appendAssistantSentence(text)
        case .speaking:
            voiceStatus = "speaking"
        case .turnEnded:
            voiceStatus = "listening"
            frozenVoiceBubble = nil
            assistantVoiceBubble = nil
        case .failed(let message):
            voiceStatus = "error: \(message)"
        }
    }

    private var frozenVoiceBubble: UUID?
    private var assistantVoiceBubble: UUID?

    /// Live local captions update one bubble in place; the server transcript
    /// (authoritative) freezes it.
    private func upsertVoiceBubble(role: String, text: String, freeze: Bool = false) {
        if let id = frozenVoiceBubble, !freeze { _ = id; return }
        if let index = bubbles.lastIndex(where: { $0.role == role && $0.isVoice
                                                  && $0.id != frozenVoiceBubble }) {
            bubbles[index].text = text
            if freeze { frozenVoiceBubble = bubbles[index].id }
        } else {
            var bubble = ChatBubble(role: role, text: text)
            bubble.isVoice = true
            bubbles.append(bubble)
            if freeze { frozenVoiceBubble = bubble.id }
        }
    }

    private func appendAssistantSentence(_ text: String) {
        if let id = assistantVoiceBubble,
           let index = bubbles.firstIndex(where: { $0.id == id }) {
            bubbles[index].text += " " + text
        } else {
            var bubble = ChatBubble(role: "assistant", text: text)
            bubble.isVoice = true
            bubbles.append(bubble)
            assistantVoiceBubble = bubble.id
        }
    }
}
