import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct JSONLogger {
    public init() {}

    public func log(_ entry: LogEntry) {
        if let data = try? JSONEncoder().encode(entry), let line = String(data: data, encoding: .utf8) {
            print(line)
        }
    }

    public func exportSpan(_ span: Span) {
        guard let urlString = ProcessInfo.processInfo.environment["OTEL_EXPORT_URL"],
              let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(span)
        URLSession.shared.dataTask(with: request).resume()
    }
}

public struct LogEntry: Codable {
    public let request_id: String
    public let tool: String
    public let duration_ms: Int
    public let metadata: [String: String]
}

public struct Span: Codable {
    public let trace_id: String
    public let span_id: String
    public let parent_id: String?
    public let name: String
    public let start: Date
    public let end: Date
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.