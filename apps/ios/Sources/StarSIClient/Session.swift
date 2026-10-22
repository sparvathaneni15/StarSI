// A conversation with whichever node is best right now. Owns discovery,
// picks a node, routes tool_call events to the phone's MCP host, and
// appends the tool result as the next message.

import Foundation

public actor ChatSession {
    public private(set) var messages: [ChatMessage]
    private let discovery: NodeDiscovery
    private let transport: Transport

    public init(system: String, discovery: NodeDiscovery, transport: Transport) {
        self.messages = [ChatMessage(role: .system, content: system)]
        self.discovery = discovery
        self.transport = transport
    }

    public func send(_ text: String, sampling: SamplingConfig = .init(), ideation: IdeationConfig = .init())
        -> AsyncThrowingStream<StreamEvent, Error>
    {
        messages.append(ChatMessage(role: .user, content: text))
        // TODO: pick node (prefer hub > edge, by reachability), build request,
        //       forward tool_call events to StarSIMCP host, feed results back.
        return AsyncThrowingStream { $0.finish() }
    }
}
