// The phone hosts MCP servers so the model can call into things only the
// phone has: calendar, location, health, photos, the Zettelkasten, etc.
//
// Shape: the node emits a `tool_call` StreamEvent → ChatSession hands it
// here → the matching server runs it on-device → result goes back as a
// `tool` message. The model never gets network access to the phone; the
// phone pulls work from the stream it already holds.

import Foundation
import MCP

public protocol PhoneTool: Sendable {
    var name: String { get }
    var description: String { get }
    var inputSchema: [String: Any] { get }
    func call(_ args: [String: Any]) async throws -> String
}

public actor MCPHost {
    private var tools: [String: any PhoneTool] = [:]

    public init() {}

    public func register(_ tool: any PhoneTool) { tools[tool.name] = tool }

    public var toolNames: [String] { Array(tools.keys).sorted() }

    public func call(name: String, args: [String: Any]) async throws -> String {
        guard let tool = tools[name] else { throw MCPHostError.unknownTool(name) }
        return try await tool.call(args)
    }
}

public enum MCPHostError: Error { case unknownTool(String) }
