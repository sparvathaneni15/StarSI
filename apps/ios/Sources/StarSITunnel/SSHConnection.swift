// One SSH connection to a StarSI host (the AWS rendezvous, or the Pi at
// home), authenticated with the device key and a pinned host key. Used only
// for port forwarding — the tunnel user has no shell.

import Crypto
import Foundation
import NIOCore
import NIOPosix
import NIOSSH

public struct SSHEndpoint: Sendable, Equatable {
    public var host: String
    public var port: Int
    public var username: String
    /// OpenSSH-format pinned host public key ("ssh-ed25519 AAAA...").
    public var hostKey: String

    public init(host: String, port: Int = 22, username: String = "starsi", hostKey: String) {
        self.host = host
        self.port = port
        self.username = username
        self.hostKey = hostKey
    }
}

enum SSHTunnelError: Error {
    case hostKeyMismatch
    case notConnected
    case channelNotSSH
    case handshakeFailed
}

/// Completes once user auth succeeds, or fails if the connection dies first
/// (e.g. the pinned host key rejected the server). connect() waits on this so
/// a bad host never looks "connected".
final class HandshakeGate: ChannelInboundHandler {
    typealias InboundIn = Any
    let done: EventLoopPromise<Void>

    init(done: EventLoopPromise<Void>) { self.done = done }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is UserAuthSuccessEvent {
            done.succeed(())
        }
        context.fireUserInboundEventTriggered(event)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        done.fail(error)
        context.fireErrorCaught(error)
    }

    func channelInactive(context: ChannelHandlerContext) {
        done.fail(SSHTunnelError.handshakeFailed)
        context.fireChannelInactive()
    }
}

final class DeviceKeyAuthDelegate: NIOSSHClientUserAuthenticationDelegate {
    let username: String
    let key: Curve25519.Signing.PrivateKey

    init(username: String, key: Curve25519.Signing.PrivateKey) {
        self.username = username
        self.key = key
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        guard availableMethods.contains(.publicKey) else {
            nextChallengePromise.succeed(nil)
            return
        }
        nextChallengePromise.succeed(NIOSSHUserAuthenticationOffer(
            username: username,
            serviceName: "",
            offer: .privateKey(.init(privateKey: NIOSSHPrivateKey(ed25519Key: key)))
        ))
    }
}

final class PinnedHostKeyDelegate: NIOSSHClientServerAuthenticationDelegate {
    let pinned: NIOSSHPublicKey?

    init(openSSHKey: String) {
        self.pinned = try? NIOSSHPublicKey(openSSHPublicKey: openSSHKey)
    }

    func validateHostKey(hostKey: NIOSSHPublicKey,
                         validationCompletePromise: EventLoopPromise<Void>) {
        if let pinned, pinned == hostKey {
            validationCompletePromise.succeed(())
        } else {
            validationCompletePromise.fail(SSHTunnelError.hostKeyMismatch)
        }
    }
}

/// Owns the TCP+SSH channel. Create direct-tcpip child channels from it.
public final class SSHConnection: @unchecked Sendable {
    let group: EventLoopGroup
    private let channel: Channel

    public var isActive: Bool { channel.isActive }

    private init(group: EventLoopGroup, channel: Channel) {
        self.group = group
        self.channel = channel
    }

    public static func connect(
        to endpoint: SSHEndpoint,
        key: Curve25519.Signing.PrivateKey,
        group: EventLoopGroup = MultiThreadedEventLoopGroup.singleton
    ) async throws -> SSHConnection {
        let handshake = group.next().makePromise(of: Void.self)
        let bootstrap = ClientBootstrap(group: group)
            .channelInitializer { channel in
                let ssh = NIOSSHHandler(
                    role: .client(.init(
                        userAuthDelegate: DeviceKeyAuthDelegate(
                            username: endpoint.username, key: key),
                        serverAuthDelegate: PinnedHostKeyDelegate(
                            openSSHKey: endpoint.hostKey)
                    )),
                    allocator: channel.allocator,
                    inboundChildChannelInitializer: nil
                )
                return channel.pipeline.addHandlers(
                    [ssh, HandshakeGate(done: handshake), SSHErrorSilencer()])
            }
            .connectTimeout(.seconds(10))
        let channel: Channel
        do {
            channel = try await bootstrap.connect(
                host: endpoint.host, port: endpoint.port).get()
        } catch {
            handshake.fail(error)
            throw error
        }
        do {
            try await handshake.futureResult.get()
        } catch {
            try? await channel.close().get()
            throw error
        }
        return SSHConnection(group: group, channel: channel)
    }

    /// Opens a direct-tcpip channel to `targetHost:targetPort` (as seen from
    /// the SSH server — i.e. its loopback NodePorts).
    func openForwardChannel(
        targetHost: String, targetPort: Int,
        initializer: @escaping @Sendable (Channel) -> EventLoopFuture<Void>
    ) async throws -> Channel {
        let handler = try await channel.pipeline.handler(type: NIOSSHHandler.self).get()
        let promise = channel.eventLoop.makePromise(of: Channel.self)
        let originator = try SocketAddress(ipAddress: "127.0.0.1", port: 0)
        // createChannel touches the SSH channel's pipeline — loop-hop first.
        channel.eventLoop.execute {
            handler.createChannel(
                promise,
                channelType: .directTCPIP(.init(
                    targetHost: targetHost,
                    targetPort: targetPort,
                    originatorAddress: originator
                ))
            ) { childChannel, _ in
                initializer(childChannel)
            }
        }
        return try await promise.futureResult.get()
    }

    public func close() async {
        try? await channel.close().get()
    }
}

/// SSH connections surface errors via errorCaught; without a tail handler
/// NIO would just crash the pipeline loudly. Log-and-close is correct here —
/// the tunnel manager reconnects.
final class SSHErrorSilencer: ChannelInboundHandler {
    typealias InboundIn = Any
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}
