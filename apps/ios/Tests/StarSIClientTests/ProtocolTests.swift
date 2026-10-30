import Foundation
import Testing
@testable import StarSIClient

@Suite("SSE parsing")
struct SSEParserTests {

    @Test("content delta becomes a token event")
    func parsesToken() {
        let line = #"data: {"choices":[{"index":0,"delta":{"content":"hello"},"finish_reason":null}]}"#
        #expect(SSEParser.parse(line: line) == .token("hello"))
    }

    @Test("[DONE] sentinel ends the stream")
    func parsesDone() {
        #expect(SSEParser.parse(line: "data: [DONE]") == .done)
    }

    @Test("finish_reason without content ends the stream")
    func parsesFinish() {
        let line = #"data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"#
        #expect(SSEParser.parse(line: line) == .done)
    }

    @Test("role-only first frame and blank lines are skipped")
    func skipsNoise() {
        let roleOnly = #"data: {"choices":[{"index":0,"delta":{"role":"assistant"},"finish_reason":null}]}"#
        #expect(SSEParser.parse(line: roleOnly) == nil)
        #expect(SSEParser.parse(line: "") == nil)
        #expect(SSEParser.parse(line: ": keepalive") == nil)
    }

    @Test("request encodes snake_case max_tokens")
    func encodesRequest() throws {
        let req = ChatCompletionRequest(
            messages: [ChatMessage(role: "user", content: "hi")], maxTokens: 64)
        let json = String(data: try JSONEncoder().encode(req), encoding: .utf8)!
        #expect(json.contains("\"max_tokens\":64"))
        #expect(json.contains("\"stream\":true"))
    }
}
