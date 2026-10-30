// ChatEngine: the full send pipeline, UI-free so it can be tested.
//
//   user text → Layer-1 signals → Layer-2 labels (RouterModel)
//   → rule table → transport (by decision) → token stream → routing log
//
// Transports are keyed by TransportKind: .http (the SSE path through the
// SSH tunnel's local forward) and .onDevice (Phase-4 local model).

import Foundation
import StarSIRouter

public struct ChatReply: Sendable {
    public var decision: RoutingDecision
    public var stream: AsyncThrowingStream<TransportEvent, Error>
}

public actor ChatEngine {
    private let routerModel: any RouterModel
    private let transports: [TransportKind: any Transport]
    private let log: RoutingLog
    public private(set) var messages: [ChatMessage] = []

    public init(routerModel: any RouterModel,
                transports: [TransportKind: any Transport],
                log: RoutingLog) {
        self.routerModel = routerModel
        self.transports = transports
        self.log = log
    }

    /// Layer 1: one /health call to the gateway through the tunnel tells us
    /// everything — tunnel liveness, per-tier upstream health, GPU state.
    public func gatherSignals(targets: [Target], tunnelUp: Bool,
                              network: NetworkKind, lowPowerMode: Bool) async -> Layer1Signals {
        var tierHealthy: Set<TargetID> = []
        var gpuState = GPUState.unknown

        if tunnelUp, let http = transports[.http],
           let gatewayTarget = targets.first(where: { $0.id != .iphone && $0.enabled
                                                      && $0.endpoint != nil }),
           let health = await http.health(of: gatewayTarget) {
            for id in TargetID.allCases {
                if let model = id.modelID, health.tiers[model]?.up == true {
                    tierHealthy.insert(id)
                }
            }
            gpuState = GPUState(rawValue: health.gpuState ?? "") ?? .unknown
        }

        return Layer1Signals(tunnelUp: tunnelUp, tierHealthy: tierHealthy,
                             gpuState: gpuState, network: network,
                             lowPowerMode: lowPowerMode)
    }

    public func send(_ text: String, targets: [Target], signals: Layer1Signals,
                     config: RoutingConfig = RoutingConfig(),
                     forced: TargetID? = nil) async -> ChatReply {
        messages.append(ChatMessage(role: "user", content: text))
        let labels = (try? await routerModel.labels(for: text)) ?? .fallback
        let decision = routeDecision(labels: labels, signals: signals,
                                     targets: targets, config: config, forced: forced)
        await log.append(RoutingLogEntry(signals: signals, labels: labels, decision: decision))

        guard let target = targets.first(where: { $0.id == decision.target }),
              let transport = transports[decision.transport]
        else {
            let problem: Error = transports[decision.transport] == nil
                ? TransportError.unavailable(decision.transport)
                : TransportError.noEndpoint(decision.target)
            return ChatReply(decision: decision, stream: AsyncThrowingStream {
                $0.finish(throwing: problem)
            })
        }
        return ChatReply(decision: decision, stream: transport.send(messages, to: target))
    }

    public func recordReply(_ content: String) {
        messages.append(ChatMessage(role: "assistant", content: content))
    }
}
