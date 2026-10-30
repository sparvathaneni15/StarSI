// The routing decision is a pure function of signals + labels + config —
// deliberately plain code, not the model, so it is testable and auditable.
// Order matters; first matching rule wins.
//
// v3: targets are tiers (AWS CPU / AWS GPU / on-device) and reachability is
// a single fact — is the SSH tunnel up — plus per-tier health read from the
// gateway's /health through that tunnel.

import Foundation

public enum NetworkKind: String, Codable, Sendable { case wifi, cellular, offline }
public enum TransportKind: String, Codable, Sendable { case http, onDevice }

public enum GPUState: String, Codable, Sendable { case running, starting, stopped, unknown }

/// Layer-1 facts gathered by plain code before any model runs.
public struct Layer1Signals: Codable, Sendable, Equatable {
    /// The SSH tunnel to the AWS rendezvous is connected.
    public var tunnelUp: Bool
    /// Tiers whose upstream the gateway reported `up` in /health.
    public var tierHealthy: Set<TargetID>
    /// EC2 GPU instance state (from the gateway/capacity controller).
    public var gpuState: GPUState
    public var network: NetworkKind
    public var lowPowerMode: Bool

    public init(
        tunnelUp: Bool = false,
        tierHealthy: Set<TargetID> = [],
        gpuState: GPUState = .unknown,
        network: NetworkKind = .offline,
        lowPowerMode: Bool = false
    ) {
        self.tunnelUp = tunnelUp
        self.tierHealthy = tierHealthy
        self.gpuState = gpuState
        self.network = network
        self.lowPowerMode = lowPowerMode
    }
}

public struct RoutingDecision: Codable, Sendable, Equatable {
    public var target: TargetID
    public var transport: TransportKind
    /// True when the iPhone answered only because nothing else was
    /// reachable — drives the "offline answer" badge.
    public var isOfflineFallback: Bool
    /// True when the GPU tier was chosen while its instance is not yet
    /// running — drives the "waking GPU…" indicator; the gateway's touch
    /// starts the instance and the CPU tier serves meanwhile.
    public var requiresWake: Bool
    public var rule: String
    /// Remaining targets to try, in order, on timeout or error.
    public var fallbackChain: [TargetID]

    public init(target: TargetID, transport: TransportKind, isOfflineFallback: Bool = false,
                requiresWake: Bool = false, rule: String, fallbackChain: [TargetID]) {
        self.target = target
        self.transport = transport
        self.isOfflineFallback = isOfflineFallback
        self.requiresWake = requiresWake
        self.rule = rule
        self.fallbackChain = fallbackChain
    }
}

public struct RoutingConfig: Sendable, Equatable {
    /// "Private" prompts stay on-device by default; the user may opt in to
    /// letting them ride the (SSH-encrypted) path to their own AWS account.
    public var allowPrivateOverOwnCloud: Bool
    public init(allowPrivateOverOwnCloud: Bool = false) {
        self.allowPrivateOverOwnCloud = allowPrivateOverOwnCloud
    }
}

public func routeDecision(
    labels: RouterLabels,
    signals: Layer1Signals,
    targets: [Target],
    config: RoutingConfig = RoutingConfig(),
    forced: TargetID? = nil
) -> RoutingDecision {
    let enabled = Set(targets.filter(\.enabled).map(\.id))
    func cloudUsable(_ id: TargetID) -> Bool {
        enabled.contains(id) && signals.tunnelUp
    }
    func healthy(_ id: TargetID) -> Bool {
        cloudUsable(id) && signals.tierHealthy.contains(id)
    }

    // Fallback chain: GPU → CPU (usable members only), iPhone always last.
    func chain(after chosen: TargetID) -> [TargetID] {
        var c: [TargetID] = [.awsGPU, .awsCPU].filter { cloudUsable($0) }
        c.append(.iphone)
        return c.filter { $0 != chosen }
    }

    func decide(_ target: TargetID, _ rule: String,
                offline: Bool = false, wake: Bool = false) -> RoutingDecision {
        RoutingDecision(
            target: target,
            transport: target == .iphone ? .onDevice : .http,
            isOfflineFallback: offline,
            requiresWake: wake,
            rule: rule,
            fallbackChain: chain(after: target)
        )
    }

    if let forced, enabled.contains(forced) {
        return decide(forced, "forced",
                      wake: forced == .awsGPU && signals.gpuState != .running)
    }

    // 1. Private prompts stay on hardware you hold unless you explicitly
    //    allowed your own cloud (everything is SSH-encrypted either way).
    if labels.sensitivity == .private && !config.allowPrivateOverOwnCloud {
        return decide(.iphone, "private→on-device")
    }

    // 2. Live sensor data exists only on the phone.
    if labels.needsLivePhoneData {
        return decide(.iphone, "live-phone-data")
    }

    // 3. Trivial + urgent: don't pay a network round trip.
    if labels.latencyTolerance == .instant && labels.reasoning == .low {
        return decide(.iphone, "instant-low")
    }

    // 4. Real reasoning goes to the GPU tier, waking it if necessary;
    //    the fallback chain serves from the CPU tier meanwhile.
    if labels.reasoning >= .medium && cloudUsable(.awsGPU) {
        return decide(.awsGPU, "reasoning→aws-gpu", wake: signals.gpuState != .running)
    }

    // 5. Anything else the cloud can serve rides the always-on CPU tier.
    if healthy(.awsCPU) || cloudUsable(.awsCPU) {
        return decide(.awsCPU, "default→aws-cpu")
    }

    // 6. Nothing reachable: answer on-device, flagged.
    return decide(.iphone, "offline-fallback", offline: true)
}
