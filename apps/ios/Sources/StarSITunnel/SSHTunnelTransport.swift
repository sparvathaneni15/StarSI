// SSHTunnelTransport: the "all networking rides SSH" rule, as a Transport.
//
// It owns one SSH connection + the local forwards, and delegates the actual
// HTTP/SSE work to the existing HTTPSSETransport pointed at 127.0.0.1.
// Reconnects with exponential backoff (cellular NAT rebinds kill idle SSH).

import Crypto
import Foundation
import StarSIClient
import StarSIRouter

public actor TunnelManager {
    public enum State: Sendable, Equatable {
        case down, connecting, up
    }

    private let endpoint: SSHEndpoint
    private let forwards: [Forward]
    private let key: Curve25519.Signing.PrivateKey
    private var connection: SSHConnection?
    private var forwarders: [LocalForwarder] = []
    private var backoff: Duration = .seconds(1)
    public private(set) var state: State = .down

    public init(endpoint: SSHEndpoint, forwards: [Forward],
                key: Curve25519.Signing.PrivateKey) {
        self.endpoint = endpoint
        self.forwards = forwards
        self.key = key
    }

    public var isUp: Bool {
        state == .up && connection?.isActive == true
    }

    /// Connect if needed. Safe to call before every request.
    public func ensureUp() async -> Bool {
        if isUp { return true }
        if state == .connecting { return false }
        state = .connecting
        await teardown()
        do {
            let conn = try await SSHConnection.connect(to: endpoint, key: key)
            var started: [LocalForwarder] = []
            for forward in forwards {
                started.append(try await LocalForwarder.start(forward: forward,
                                                              connection: conn))
            }
            connection = conn
            forwarders = started
            state = .up
            backoff = .seconds(1)
            return true
        } catch {
            state = .down
            try? await Task.sleep(for: backoff)
            backoff = min(backoff * 2, .seconds(60))
            return false
        }
    }

    public func disconnect() async {
        await teardown()
        state = .down
    }

    private func teardown() async {
        for forwarder in forwarders { await forwarder.stop() }
        forwarders = []
        if let connection { await connection.close() }
        connection = nil
    }
}

public struct SSHTunnelTransport: Transport {
    let tunnel: TunnelManager
    let inner: HTTPSSETransport
    /// Where the gateway appears locally once the tunnel is up.
    let localEndpoint: URL

    public init(tunnel: TunnelManager, localEndpoint: URL,
                token: @escaping @Sendable () -> String?) {
        self.tunnel = tunnel
        self.inner = HTTPSSETransport(token: token)
        self.localEndpoint = localEndpoint
    }

    private func rewritten(_ target: Target) -> Target {
        var local = target
        local.endpoint = localEndpoint
        return local
    }

    public func health(of target: Target) async -> GatewayHealth? {
        guard await tunnel.ensureUp() else { return nil }
        return await inner.health(of: rewritten(target))
    }

    public func send(_ messages: [ChatMessage], to target: Target)
        -> AsyncThrowingStream<TransportEvent, Error>
    {
        AsyncThrowingStream { continuation in
            let task = Task {
                guard await tunnel.ensureUp() else {
                    continuation.finish(throwing: TransportError.tunnelDown)
                    return
                }
                do {
                    for try await event in inner.send(messages, to: rewritten(target)) {
                        continuation.yield(event)
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
