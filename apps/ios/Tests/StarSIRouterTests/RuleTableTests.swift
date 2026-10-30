import Foundation
import Testing
@testable import StarSIRouter

private let allTargets = [
    Target(id: .iphone, enabled: true),
    Target(id: .awsCPU, endpoint: URL(string: "http://127.0.0.1:8484"), enabled: true),
    Target(id: .awsGPU, endpoint: URL(string: "http://127.0.0.1:8484"), enabled: true),
]

private let gpuDisabled = [
    Target(id: .iphone, enabled: true),
    Target(id: .awsCPU, endpoint: URL(string: "http://127.0.0.1:8484"), enabled: true),
    Target(id: .awsGPU, endpoint: URL(string: "http://127.0.0.1:8484"), enabled: false),
]

private func labels(
    reasoning: Reasoning = .medium,
    latency: LatencyTolerance = .normal,
    liveData: Bool = false,
    sensitivity: Sensitivity = .normal
) -> RouterLabels {
    RouterLabels(reasoning: reasoning, latencyTolerance: latency,
                 needsLivePhoneData: liveData, sensitivity: sensitivity)
}

private func online(gpu: GPUState = .running) -> Layer1Signals {
    Layer1Signals(tunnelUp: true, tierHealthy: [.awsCPU, .awsGPU],
                  gpuState: gpu, network: .wifi)
}

@Suite("Rule table v3")
struct RuleTableTests {

    @Test("private stays on-device even with the tunnel up")
    func privateStaysOnDevice() {
        let d = routeDecision(labels: labels(sensitivity: .private),
                              signals: online(), targets: allTargets)
        #expect(d.target == .iphone)
        #expect(d.transport == .onDevice)
    }

    @Test("private may use the cloud once explicitly allowed")
    func privateOptInUsesCloud() {
        let d = routeDecision(labels: labels(sensitivity: .private),
                              signals: online(), targets: allTargets,
                              config: RoutingConfig(allowPrivateOverOwnCloud: true))
        #expect(d.target != .iphone)
    }

    @Test("live phone data pins to the iPhone")
    func liveDataGoesToPhone() {
        let d = routeDecision(labels: labels(reasoning: .high, liveData: true),
                              signals: online(), targets: allTargets)
        #expect(d.target == .iphone)
        #expect(d.transport == .onDevice)
    }

    @Test("instant + low reasoning stays on the iPhone")
    func instantLowStaysLocal() {
        let d = routeDecision(labels: labels(reasoning: .low, latency: .instant),
                              signals: online(), targets: allTargets)
        #expect(d.target == .iphone)
    }

    @Test("medium/high reasoning goes to the GPU tier when the tunnel is up")
    func reasoningGoesToGPU() {
        for r in [Reasoning.medium, .high] {
            let d = routeDecision(labels: labels(reasoning: r),
                                  signals: online(), targets: allTargets)
            #expect(d.target == .awsGPU)
            #expect(d.transport == .http)
            #expect(!d.requiresWake)
        }
    }

    @Test("a stopped GPU is still chosen but flagged for wake")
    func stoppedGPUWakes() {
        let d = routeDecision(labels: labels(reasoning: .high),
                              signals: online(gpu: .stopped), targets: allTargets)
        #expect(d.target == .awsGPU)
        #expect(d.requiresWake)
        #expect(d.fallbackChain == [.awsCPU, .iphone])
    }

    @Test("a disabled GPU tier routes reasoning to the CPU tier")
    func disabledGPUIgnored() {
        let d = routeDecision(labels: labels(reasoning: .high),
                              signals: online(), targets: gpuDisabled)
        #expect(d.target == .awsCPU)
    }

    @Test("default (low reasoning, normal latency) rides the CPU tier")
    func defaultPrefersCPU() {
        let d = routeDecision(labels: labels(reasoning: .low),
                              signals: online(), targets: allTargets)
        #expect(d.target == .awsCPU)
    }

    @Test("tunnel down means on-device with the offline flag")
    func offlineFallback() {
        let d = routeDecision(labels: labels(reasoning: .high),
                              signals: Layer1Signals(network: .offline),
                              targets: allTargets)
        #expect(d.target == .iphone)
        #expect(d.isOfflineFallback)
    }

    @Test("fallback chain orders GPU → CPU → iPhone")
    func fallbackChainOrder() {
        let d = routeDecision(labels: labels(reasoning: .high),
                              signals: online(), targets: allTargets)
        #expect(d.target == .awsGPU)
        #expect(d.fallbackChain == [.awsCPU, .iphone])
    }

    @Test("forced target overrides every rule and flags wake if stopped")
    func forcedTargetWins() {
        let d = routeDecision(labels: labels(liveData: true),
                              signals: online(gpu: .stopped), targets: allTargets,
                              forced: .awsGPU)
        #expect(d.target == .awsGPU)
        #expect(d.rule == "forced")
        #expect(d.requiresWake)
    }

    @Test("an unhealthy CPU tier with the tunnel up is still attempted")
    func tunnelUpUnhealthyCPUStillTried() {
        let signals = Layer1Signals(tunnelUp: true, tierHealthy: [],
                                    gpuState: .stopped, network: .cellular)
        let d = routeDecision(labels: labels(reasoning: .low),
                              signals: signals, targets: gpuDisabled)
        #expect(d.target == .awsCPU)
        #expect(!d.isOfflineFallback)
    }
}
