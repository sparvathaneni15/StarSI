// OpenAI-compatible wire types — mirrors protocol/README.md and the
// gateway block (blocks/gateway). Keep in sync by hand.

import Foundation

public struct ChatMessage: Codable, Sendable, Equatable {
    public var role: String
    public var content: String
    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct ChatCompletionRequest: Encodable, Sendable {
    public var model: String?
    public var messages: [ChatMessage]
    public var stream = true
    public var maxTokens: Int?
    public var temperature: Double?

    public init(messages: [ChatMessage], model: String? = nil,
                maxTokens: Int? = nil, temperature: Double? = nil) {
        self.messages = messages
        self.model = model
        self.maxTokens = maxTokens
        self.temperature = temperature
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature
        case maxTokens = "max_tokens"
    }
}

/// GET /health on the gateway: per-tier reachability + GPU instance state.
public struct GatewayHealth: Decodable, Sendable {
    public struct Tier: Decodable, Sendable {
        public var up: Bool
    }

    public var status: String
    public var site: String
    public var tiers: [String: Tier]
    public var gpuState: String?

    public init(status: String, site: String, tiers: [String: Tier], gpuState: String? = nil) {
        self.status = status
        self.site = site
        self.tiers = tiers
        self.gpuState = gpuState
    }

    enum CodingKeys: String, CodingKey {
        case status, site, tiers
        case gpuState = "gpu_state"
    }
}

public enum TransportEvent: Sendable, Equatable {
    case token(String)
    case done
}

/// Parses one SSE line from /v1/chat/completions into an event.
/// Returns nil for lines that carry no delta (comments, role-only frames).
public enum SSEParser {
    private struct Chunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { var content: String? }
            var delta: Delta
            var finishReason: String?
            enum CodingKeys: String, CodingKey {
                case delta
                case finishReason = "finish_reason"
            }
        }
        var choices: [Choice]
    }

    public static func parse(line: String) -> TransportEvent? {
        guard line.hasPrefix("data: ") else { return nil }
        let payload = String(line.dropFirst(6))
        if payload == "[DONE]" { return .done }
        guard let chunk = try? JSONDecoder().decode(Chunk.self, from: Data(payload.utf8)),
              let choice = chunk.choices.first
        else { return nil }
        if let text = choice.delta.content, !text.isEmpty { return .token(text) }
        if choice.finishReason != nil { return .done }
        return nil
    }
}
