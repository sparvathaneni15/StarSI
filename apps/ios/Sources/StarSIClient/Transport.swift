// Transport: send(messages, target) → stream of tokens, plus the gateway
// health probe. The endpoint is always a tunnel-local URL (127.0.0.1) —
// SSHTunnelTransport in StarSITunnel owns the SSH connection and delegates
// the HTTP/SSE work back to HTTPSSETransport here.

import Foundation
import StarSIRouter

public protocol Transport: Sendable {
    func health(of target: Target) async -> GatewayHealth?
    func send(_ messages: [ChatMessage], to target: Target)
        -> AsyncThrowingStream<TransportEvent, Error>
}

public enum TransportError: Error, LocalizedError {
    case noEndpoint(TargetID)
    case badStatus(Int)
    case unavailable(TransportKind)
    case tunnelDown

    public var errorDescription: String? {
        switch self {
        case .noEndpoint(let id): "No endpoint configured for \(id.displayName)"
        case .badStatus(let code): "Server returned HTTP \(code)"
        case .unavailable(let kind):
            kind == .onDevice
                ? "On-device model isn't available yet (Phase 4)"
                : "No transport available for \(kind.rawValue)"
        case .tunnelDown: "The SSH tunnel is not connected"
        }
    }
}

public struct HTTPSSETransport: Transport {
    let token: @Sendable () -> String?

    public init(token: @escaping @Sendable () -> String?) {
        self.token = token
    }

    public func health(of target: Target) async -> GatewayHealth? {
        guard let endpoint = target.endpoint else { return nil }
        var request = URLRequest(url: endpoint.appendingPathComponent("health"))
        request.timeoutInterval = 2
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return try? JSONDecoder().decode(GatewayHealth.self, from: data)
    }

    public func send(_ messages: [ChatMessage], to target: Target)
        -> AsyncThrowingStream<TransportEvent, Error>
    {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let endpoint = target.endpoint else {
                        throw TransportError.noEndpoint(target.id)
                    }
                    var request = URLRequest(
                        url: endpoint.appendingPathComponent("v1/chat/completions"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if let token = token() {
                        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    }
                    request.httpBody = try JSONEncoder().encode(
                        ChatCompletionRequest(messages: messages, model: target.id.modelID))
                    request.timeoutInterval = 120

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        throw TransportError.badStatus(http.statusCode)
                    }
                    for try await line in bytes.lines {
                        switch SSEParser.parse(line: line) {
                        case .token(let text): continuation.yield(.token(text))
                        case .done:
                            continuation.yield(.done)
                            continuation.finish()
                            return
                        case nil: continue
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
