// Layer-2 routing labels and the model that produces them.
//
// The interface is shaped like TypeSafe's System One API (typed questions
// → calibrated probabilities) so the local Kev-0.8B and a hosted Jev
// (`POST /v1/systemone`) are interchangeable implementations.

import Foundation

public enum Reasoning: String, Codable, Sendable, Comparable {
    case low, medium, high
    private var rank: Int { self == .low ? 0 : self == .medium ? 1 : 2 }
    public static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }
}

public enum LatencyTolerance: String, Codable, Sendable { case instant, normal, patient }
public enum Sensitivity: String, Codable, Sendable { case normal, `private` }

public struct RouterLabels: Codable, Sendable, Equatable {
    public var reasoning: Reasoning
    public var latencyTolerance: LatencyTolerance
    public var needsLivePhoneData: Bool
    public var sensitivity: Sensitivity
    /// Lowest per-label confidence reported by the model, 0...1.
    public var confidence: Double

    public init(
        reasoning: Reasoning = .medium,
        latencyTolerance: LatencyTolerance = .normal,
        needsLivePhoneData: Bool = false,
        sensitivity: Sensitivity = .normal,
        confidence: Double = 0
    ) {
        self.reasoning = reasoning
        self.latencyTolerance = latencyTolerance
        self.needsLivePhoneData = needsLivePhoneData
        self.sensitivity = sensitivity
        self.confidence = confidence
    }

    /// Conservative defaults used when the model is unavailable or unsure.
    public static let fallback = RouterLabels()
}

public protocol RouterModel: Sendable {
    func labels(for prompt: String) async throws -> RouterLabels
}

/// Placeholder until Kev-0.8B lands on-device (Phase 4). Always returns
/// the conservative defaults, which route to the best reachable Mac.
public struct StubRouterModel: RouterModel {
    public init() {}
    public func labels(for prompt: String) async throws -> RouterLabels { .fallback }
}
