// Finds StarSI nodes. Three mechanisms behind one interface so the chat
// layer never knows which carried the connection (README → Request path).
//
//   Bonjour (_starsi._tcp)   same Wi-Fi, home
//   MultipeerConnectivity    no router — Bluetooth + peer-to-peer Wi-Fi
//   Tailscale                away from home; static names from Settings

import Foundation
import Network

public struct DiscoveredNode: Sendable, Identifiable, Hashable {
    public var id: String { name }
    public let name: String          // "studio", "macbook"
    public let kind: String          // "hub" | "edge"
    public let endpoint: NWEndpoint
    public let loadedModels: [String]
}

public protocol NodeDiscovery: Sendable {
    /// Emits the current set of reachable nodes whenever it changes.
    func nodes() -> AsyncStream<[DiscoveredNode]>
}

/// Bonjour browser for `_starsi._tcp`. TXT records carry kind + models.
public final class BonjourDiscovery: NodeDiscovery, @unchecked Sendable {
    public init() {}
    public func nodes() -> AsyncStream<[DiscoveredNode]> {
        // TODO: NWBrowser(for: .bonjourWithTXTRecord(type: "_starsi._tcp", domain: nil))
        AsyncStream { $0.finish() }
    }
}

/// Static entries (Tailscale names) the user configures.
public struct StaticDiscovery: NodeDiscovery {
    public let entries: [DiscoveredNode]
    public init(entries: [DiscoveredNode]) { self.entries = entries }
    public func nodes() -> AsyncStream<[DiscoveredNode]> {
        AsyncStream { c in c.yield(entries); c.finish() }
    }
}

// TODO: MultipeerDiscovery — MCSession-based, for router-less proximity.
