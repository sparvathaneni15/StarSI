// Carries ChatRequest → StreamEvent frames over a connection to one node.
// Transport is the open protocol question (gRPC / framed TCP / WebSocket);
// start with the HTTP streaming endpoint the node already exposes so the
// UI can be built, then swap the implementation behind this protocol.

import Foundation
import Network

public protocol Transport: Sendable {
    func send(_ request: ChatRequest, to node: DiscoveredNode) -> AsyncThrowingStream<StreamEvent, Error>
}

/// First implementation: POST /v1/chat, newline-delimited StreamEvent JSON.
public struct HTTPStreamTransport: Transport {
    public init() {}
    public func send(_ request: ChatRequest, to node: DiscoveredNode) -> AsyncThrowingStream<StreamEvent, Error> {
        // TODO: URLSession.bytes(for:) → split on "\n" → JSONDecoder.starsi
        AsyncThrowingStream { $0.finish() }
    }
}
