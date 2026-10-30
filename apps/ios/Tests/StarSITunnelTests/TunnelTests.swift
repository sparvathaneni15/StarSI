// End-to-end tunnel test against an in-process NIOSSH server: a loopback
// forward is opened, bytes written to the local port come back through the
// SSH direct-tcpip channel (the test server echoes), and a wrong pinned
// host key must fail the connection.

import Crypto
import Foundation
import NIOCore
import NIOPosix
import NIOSSH
import Testing
@testable import StarSITunnel

// ── test SSH server ──────────────────────────────────────────────────────────

final class AcceptAllAuthDelegate: NIOSSHServerUserAuthenticationDelegate {
    var supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods { .publicKey }
    func requestReceived(request: NIOSSHUserAuthenticationRequest,
                         responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>) {
        responsePromise.succeed(.success)
    }
}

/// Echoes every data frame straight back on the SSH child channel.
final class SSHEchoHandler: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData
    typealias OutboundOut = SSHChannelData
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        context.writeAndFlush(wrapOutboundOut(unwrapInboundIn(data)), promise: nil)
    }
}

func startEchoSSHServer(hostKey: Curve25519.Signing.PrivateKey) async throws -> Channel {
    let bootstrap = ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
        .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        .childChannelInitializer { channel in
            channel.pipeline.addHandler(NIOSSHHandler(
                role: .server(.init(
                    hostKeys: [NIOSSHPrivateKey(ed25519Key: hostKey)],
                    userAuthDelegate: AcceptAllAuthDelegate()
                )),
                allocator: channel.allocator,
                inboundChildChannelInitializer: { childChannel, channelType in
                    guard case .directTCPIP = channelType else {
                        return childChannel.eventLoop.makeFailedFuture(
                            SSHTunnelError.channelNotSSH)
                    }
                    return childChannel.pipeline.addHandler(SSHEchoHandler())
                }
            ))
        }
    return try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
}

// ── plain TCP probe client ───────────────────────────────────────────────────

final class CollectHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    let received: EventLoopPromise<String>
    init(received: EventLoopPromise<String>) { self.received = received }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        received.succeed(buffer.readString(length: buffer.readableBytes) ?? "")
        context.close(promise: nil)
    }
}

func roundTrip(port: Int, message: String) async throws -> String {
    let group = MultiThreadedEventLoopGroup.singleton
    let promise = group.next().makePromise(of: String.self)
    let channel = try await ClientBootstrap(group: group)
        .channelInitializer { $0.pipeline.addHandler(CollectHandler(received: promise)) }
        .connect(host: "127.0.0.1", port: port).get()
    var buffer = channel.allocator.buffer(capacity: message.utf8.count)
    buffer.writeString(message)
    try await channel.writeAndFlush(buffer).get()
    return try await promise.futureResult.get()
}

// ── tests ────────────────────────────────────────────────────────────────────

@Suite("SSH tunnel")
struct TunnelTests {

    @Test("bytes round-trip through a local forward and the SSH channel")
    func forwardRoundTrip() async throws {
        let hostKey = Curve25519.Signing.PrivateKey()
        let server = try await startEchoSSHServer(hostKey: hostKey)
        defer { _ = server.close() }

        let endpoint = SSHEndpoint(
            host: "127.0.0.1",
            port: server.localAddress!.port!,
            hostKey: DeviceKey.openSSHPublicKey(hostKey, comment: "test-host")
        )
        let connection = try await SSHConnection.connect(
            to: endpoint, key: Curve25519.Signing.PrivateKey())
        let forwarder = try await LocalForwarder.start(
            forward: Forward(localPort: 0, targetPort: 9999),
            connection: connection)

        let reply = try await roundTrip(port: forwarder.localPort, message: "hello starsi")
        #expect(reply == "hello starsi")

        await forwarder.stop()
        await connection.close()
    }

    @Test("a wrong pinned host key refuses to connect")
    func hostKeyPinningRejectsImpostor() async throws {
        let hostKey = Curve25519.Signing.PrivateKey()
        let server = try await startEchoSSHServer(hostKey: hostKey)
        defer { _ = server.close() }

        let wrongPin = DeviceKey.openSSHPublicKey(
            Curve25519.Signing.PrivateKey(), comment: "impostor")
        let endpoint = SSHEndpoint(
            host: "127.0.0.1",
            port: server.localAddress!.port!,
            hostKey: wrongPin
        )
        await #expect(throws: Error.self) {
            _ = try await SSHConnection.connect(
                to: endpoint, key: Curve25519.Signing.PrivateKey())
        }
    }

    @Test("openSSH public key export is well-formed")
    func publicKeyExport() {
        let key = Curve25519.Signing.PrivateKey()
        let line = DeviceKey.openSSHPublicKey(key, comment: "starsi-iphone")
        #expect(line.hasPrefix("ssh-ed25519 "))
        #expect(line.hasSuffix(" starsi-iphone"))
        // must parse back as a NIOSSH public key
        #expect((try? NIOSSHPublicKey(
            openSSHPublicKey: line)) != nil)
    }
}
