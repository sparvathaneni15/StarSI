// A loopback listener that pipes each accepted TCP connection into an SSH
// direct-tcpip channel: `127.0.0.1:localPort` on the phone becomes
// `targetHost:targetPort` as seen from the SSH server.

import NIOCore
import NIOPosix
import NIOSSH

public struct Forward: Sendable, Equatable {
    public var localPort: Int
    public var targetHost: String
    public var targetPort: Int

    public init(localPort: Int, targetHost: String = "127.0.0.1", targetPort: Int) {
        self.localPort = localPort
        self.targetHost = targetHost
        self.targetPort = targetPort
    }
}

final class LocalForwarder: @unchecked Sendable {
    private let serverChannel: Channel

    var localPort: Int { serverChannel.localAddress?.port ?? 0 }

    private init(serverChannel: Channel) {
        self.serverChannel = serverChannel
    }

    static func start(forward: Forward, connection: SSHConnection) async throws -> LocalForwarder {
        let bootstrap = ServerBootstrap(group: connection.group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.autoRead, value: false)
            .childChannelInitializer { local in
                let setup = local.eventLoop.makePromise(of: Void.self)
                setup.completeWithTask {
                    let sshChild = try await connection.openForwardChannel(
                        targetHost: forward.targetHost,
                        targetPort: forward.targetPort
                    ) { sshChannel in
                        sshChannel.pipeline.addHandler(SSHToLocalPump(peer: local))
                    }
                    try await local.pipeline.addHandler(LocalToSSHPump(peer: sshChild)).get()
                    try await local.setOption(ChannelOptions.autoRead, value: true).get()
                }
                return setup.futureResult
            }
        let server = try await bootstrap
            .bind(host: "127.0.0.1", port: forward.localPort).get()
        return LocalForwarder(serverChannel: server)
    }

    func stop() async {
        try? await serverChannel.close().get()
    }
}

/// Local socket → SSH child channel (wraps bytes in SSHChannelData).
final class LocalToSSHPump: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    let peer: Channel

    init(peer: Channel) { self.peer = peer }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        peer.writeAndFlush(SSHChannelData(type: .channel, data: .byteBuffer(buffer)),
                           promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        peer.close(promise: nil)
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        peer.close(promise: nil)
        context.close(promise: nil)
    }
}

/// SSH child channel → local socket (unwraps SSHChannelData).
final class SSHToLocalPump: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData
    let peer: Channel

    init(peer: Channel) { self.peer = peer }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)
        guard case .byteBuffer(let buffer) = channelData.data, case .channel = channelData.type
        else { return }
        peer.writeAndFlush(buffer, promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        peer.close(promise: nil)
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        peer.close(promise: nil)
        context.close(promise: nil)
    }
}
