// Inference targets are now *tiers*, not machines: the Macs train, AWS
// serves. Both AWS tiers sit behind one gateway reached through the SSH
// tunnel; the tier is selected by the OpenAI `model` field.

import Foundation

public enum TargetID: String, Codable, CaseIterable, Sendable, Identifiable {
    case iphone
    case awsCPU = "aws-cpu"
    case awsGPU = "aws-gpu"
    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .iphone: "iPhone"
        case .awsCPU: "Cloud (fast)"
        case .awsGPU: "Cloud (deep)"
        }
    }

    /// The `model` value the gateway maps to an inference tier.
    public var modelID: String? {
        switch self {
        case .iphone: nil
        case .awsCPU: "starsi-cpu"
        case .awsGPU: "starsi-gpu"
        }
    }
}

public struct Target: Sendable, Codable, Hashable, Identifiable {
    public var id: TargetID
    /// Where the transport connects. For AWS tiers this is the tunnel's
    /// local forward (http://127.0.0.1:8484) — never a remote URL.
    public var endpoint: URL?
    public var enabled: Bool

    public init(id: TargetID, endpoint: URL? = nil, enabled: Bool) {
        self.id = id
        self.endpoint = endpoint
        self.enabled = enabled
    }
}
