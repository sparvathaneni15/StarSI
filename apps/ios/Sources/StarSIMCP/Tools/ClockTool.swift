// Smallest possible tool, to prove the round-trip end to end.

import Foundation

public struct ClockTool: PhoneTool {
    public let name = "clock.now"
    public let description = "Current date and time on the phone, in the user's timezone."
    public let inputSchema: [String: Any] = ["type": "object", "properties": [:]]
    public init() {}
    public func call(_ args: [String: Any]) async throws -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
