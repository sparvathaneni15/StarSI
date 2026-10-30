// Every routing decision is appended to a local JSONL file: the signals,
// the labels, the chosen target, and (once known) first-token latency.
// The Settings screen reads this back for debugging.

import Foundation

public struct RoutingLogEntry: Codable, Sendable, Identifiable {
    public var id: UUID
    public var ts: Date
    public var signals: Layer1Signals
    public var labels: RouterLabels
    public var decision: RoutingDecision
    public var firstTokenMs: Int?
    public var totalMs: Int?
    public var error: String?

    public init(signals: Layer1Signals, labels: RouterLabels, decision: RoutingDecision) {
        self.id = UUID()
        self.ts = Date()
        self.signals = signals
        self.labels = labels
        self.decision = decision
    }
}

public actor RoutingLog {
    private let fileURL: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    public init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("routing-log.jsonl")
    }

    public func append(_ entry: RoutingLogEntry) {
        guard let data = try? encoder.encode(entry), let line = String(data: data, encoding: .utf8)
        else { return }
        let text = line + "\n"
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(text.utf8))
        } else {
            try? Data(text.utf8).write(to: fileURL)
        }
    }

    public func recent(limit: Int = 200) -> [RoutingLogEntry] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").suffix(limit).compactMap {
            try? decoder.decode(RoutingLogEntry.self, from: Data($0.utf8))
        }.reversed()
    }
}
