// Wire protocol — mirrors packages/starsi-core/starsi_core/protocol.py
// and protocol/starsi.schema.json. Keep the three in sync by hand until
// codegen is wired up.

import Foundation

public enum Role: String, Codable, Sendable { case system, user, assistant, tool }

public struct ChatMessage: Codable, Sendable {
    public var role: Role
    public var content: String
    public var toolCallId: String?
    public init(role: Role, content: String, toolCallId: String? = nil) {
        self.role = role; self.content = content; self.toolCallId = toolCallId
    }
}

public struct SamplingConfig: Codable, Sendable {
    public var temperature: Double = 1.0
    public var minP: Double = 0.05
    public var topP: Double? = nil
    public var maxTokens: Int = 2048
    public var reasoningEffort: String = "medium"
    public init() {}
}

public struct IdeationConfig: Codable, Sendable {
    public var enabled = false
    public var candidates = 8
    public var survivors = 2
    public var noveltyWeight = 0.5
    public var plausibilityWeight = 0.5
    public init() {}
}

public struct ChatRequest: Codable, Sendable {
    public var messages: [ChatMessage]
    public var model: String?
    public var sampling = SamplingConfig()
    public var ideation = IdeationConfig()
    public var tools: [String] = []
    public var stream = true
    public init(messages: [ChatMessage]) { self.messages = messages }
}

public struct StreamEvent: Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case token, thinking, toolCall = "tool_call", candidate, done, error }
    public var type: Kind
    public var content: String = ""
    public var toolName: String?
    public var toolArgs: [String: AnyCodable]?
    public var toolCallId: String?
    public var candidateIndex: Int?
    public var novelty: Double?
    public var plausibility: Double?
    public var servedBy: String?
    public var model: String?
}

/// Minimal type-erased JSON value for tool arguments.
public struct AnyCodable: Codable, Sendable {
    public let value: any Sendable
    public init(_ value: any Sendable) { self.value = value }
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self) { value = v }
        else if let v = try? c.decode(Int.self) { value = v }
        else if let v = try? c.decode(Double.self) { value = v }
        else if let v = try? c.decode(String.self) { value = v }
        else if let v = try? c.decode([AnyCodable].self) { value = v.map(\.value) }
        else if let v = try? c.decode([String: AnyCodable].self) { value = v.mapValues(\.value) }
        else { value = Optional<String>.none as Any as! any Sendable }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let v as Bool: try c.encode(v)
        case let v as Int: try c.encode(v)
        case let v as Double: try c.encode(v)
        case let v as String: try c.encode(v)
        default: try c.encodeNil()
        }
    }
}

extension JSONDecoder {
    /// Decoder matching the snake_case produced by the Python side.
    public static let starsi: JSONDecoder = {
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d
    }()
}
extension JSONEncoder {
    public static let starsi: JSONEncoder = {
        let e = JSONEncoder(); e.keyEncodingStrategy = .convertToSnakeCase; return e
    }()
}
