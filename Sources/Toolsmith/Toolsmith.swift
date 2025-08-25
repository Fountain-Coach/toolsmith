import Foundation
import ToolsmithSupport

public struct Toolsmith {
    let logger = JSONLogger()
    public let manifest: ToolManifest?

    public init(imageDirectory: URL = URL(fileURLWithPath: ".")) {
        let manifestURL = imageDirectory.appendingPathComponent("tools.json")
        self.manifest = try? ToolManifest.load(from: manifestURL)
    }

    @discardableResult
    public func run(tool: String, metadata: [String: String] = [:], requestID: String = UUID().uuidString, operation: () throws -> Void) rethrows -> String {
        var meta = metadata
        let start = Date()
        defer {
            let end = Date()
            let duration = Int(end.timeIntervalSince(start) * 1000)
            if ProcessInfo.processInfo.environment["OTEL_EXPORT_URL"] != nil {
                let spanID = UUID().uuidString
                let span = Span(trace_id: requestID, span_id: spanID, parent_id: nil, name: tool, start: start, end: end)
                logger.exportSpan(span)
                meta["span_id"] = spanID
            }
            let entry = LogEntry(request_id: requestID, tool: tool, duration_ms: duration, metadata: meta)
            logger.log(entry)
        }
        try operation()
        return requestID
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.