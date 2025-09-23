import Foundation
import ToolsmithSupport

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public enum ToolsmithError: Error {
  case manifestUnavailable
}

public struct Toolsmith {
  let logger = JSONLogger()
  public let manifest: ToolManifest?
  private let imageHydrator: ImageHydrator?

  public init(imageDirectory: URL = URL(fileURLWithPath: "."), session: URLSession = .shared) {
    let manifestURL = imageDirectory.appendingPathComponent("tools.json")
    let manifest = try? ToolManifest.load(from: manifestURL)
    self.manifest = manifest
    if let manifest = manifest {
      self.imageHydrator = ImageHydrator(
        manifest: manifest, manifestURL: manifestURL, session: session)
    } else {
      self.imageHydrator = nil
    }
  }

  @discardableResult
  public func run(
    tool: String, metadata: [String: String] = [:], requestID: String = UUID().uuidString,
    operation: () throws -> Void
  ) rethrows -> String {
    var meta = metadata
    let start = Date()
    defer {
      let end = Date()
      let duration = Int(end.timeIntervalSince(start) * 1000)
      if ProcessInfo.processInfo.environment["OTEL_EXPORT_URL"] != nil {
        let spanID = UUID().uuidString
        let span = Span(
          trace_id: requestID, span_id: spanID, parent_id: nil, name: tool, start: start, end: end)
        logger.exportSpan(span)
        meta["span_id"] = spanID
      }
      let entry = LogEntry(request_id: requestID, tool: tool, duration_ms: duration, metadata: meta)
      logger.log(entry)
    }
    try operation()
    return requestID
  }

  public func ensureVirtualMachineImage() async throws -> URL {
    guard let hydrator = imageHydrator else { throw ToolsmithError.manifestUnavailable }
    return try await hydrator.ensureImageAvailable()
  }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
