// The /v1/voice WebSocket protocol, platform-neutral and testable.
// Binary frames are waveforms; text frames are JSON metadata. Mirrors
// blocks/gateway/starsi_gateway/voice.py.

import Foundation

public enum VoiceServerEvent: Sendable, Equatable {
    case transcript(role: String, text: String)
    case sentence(String)
    case audio(Data)
    case turnEnd
    case error(String)
}

public final class VoiceLink: NSObject, @unchecked Sendable {
    private var task: URLSessionWebSocketTask?
    private let url: URL
    private let token: String
    private let model: String?

    public init(url: URL, token: String, model: String? = nil) {
        self.url = url
        self.token = token
        self.model = model
    }

    public func connect() -> AsyncStream<VoiceServerEvent> {
        let task = URLSession.shared.webSocketTask(with: url)
        self.task = task
        task.resume()

        var start: [String: String] = ["type": "start", "token": token, "format": "wav"]
        if let model { start["model"] = model }
        send(json: start)

        return AsyncStream { continuation in
            func receiveLoop() {
                task.receive { [weak self] result in
                    switch result {
                    case .failure:
                        continuation.finish()
                    case .success(let message):
                        if let event = Self.decode(message) {
                            continuation.yield(event)
                        }
                        receiveLoop()
                        _ = self
                    }
                }
            }
            receiveLoop()
            continuation.onTermination = { _ in task.cancel(with: .goingAway, reason: nil) }
        }
    }

    static func decode(_ message: URLSessionWebSocketTask.Message) -> VoiceServerEvent? {
        switch message {
        case .data(let data):
            return .audio(data)
        case .string(let text):
            guard let obj = try? JSONSerialization.jsonObject(
                with: Data(text.utf8)) as? [String: Any],
                let kind = obj["type"] as? String
            else { return nil }
            switch kind {
            case "transcript":
                return .transcript(role: obj["role"] as? String ?? "user",
                                   text: obj["text"] as? String ?? "")
            case "sentence": return .sentence(obj["text"] as? String ?? "")
            case "turn_end": return .turnEnd
            case "error": return .error(obj["text"] as? String ?? "unknown")
            default: return nil
            }
        @unknown default:
            return nil
        }
    }

    public func sendUtterance(wav: Data) {
        task?.send(.data(wav)) { _ in }
        send(json: ["type": "end"])
    }

    public func cancel() {
        send(json: ["type": "cancel"])
    }

    public func close() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func send(json: [String: String]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let text = String(data: data, encoding: .utf8)
        else { return }
        task?.send(.string(text)) { _ in }
    }
}
