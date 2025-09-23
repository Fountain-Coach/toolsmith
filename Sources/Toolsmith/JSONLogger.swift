import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public struct JSONLogger {
  public init() {}

  public func log(_ entry: LogEntry) {
    emit(entry)
  }

  public func logLifecycle(_ entry: LifecycleLogEntry) {
    emit(entry)
  }

  public func lifecycleDownloadStarted(
    requestID: String,
    executionMode: String,
    imageName: String,
    cacheURL: URL,
    source: URL? = nil
  ) {
    var metadata: [String: String] = [
      "image_name": imageName,
      "cache_path": cacheURL.path,
    ]
    if let source {
      metadata["source"] = source.absoluteString
    }
    logLifecycle(
      LifecycleLogEntry(
        request_id: requestID,
        stage: "download_start",
        timestamp: Date(),
        execution_mode: executionMode,
        metadata: metadata))
  }

  public func lifecycleDownloadFinished(
    requestID: String,
    executionMode: String,
    imageName: String,
    cacheURL: URL,
    source: URL? = nil,
    success: Bool,
    errorDescription: String? = nil
  ) {
    var metadata: [String: String] = [
      "image_name": imageName,
      "cache_path": cacheURL.path,
      "status": success ? "success" : "failed",
    ]
    if let source {
      metadata["source"] = source.absoluteString
    }
    if let errorDescription {
      metadata["error"] = errorDescription
    }
    logLifecycle(
      LifecycleLogEntry(
        request_id: requestID,
        stage: "download_end",
        timestamp: Date(),
        execution_mode: executionMode,
        metadata: metadata))
  }

  public func lifecycleChecksumVerified(
    requestID: String,
    executionMode: String,
    imageName: String,
    imageURL: URL,
    digest: String
  ) {
    let metadata: [String: String] = [
      "image_name": imageName,
      "image_path": imageURL.path,
      "digest": digest,
    ]
    logLifecycle(
      LifecycleLogEntry(
        request_id: requestID,
        stage: "checksum_verified",
        timestamp: Date(),
        execution_mode: executionMode,
        metadata: metadata))
  }

  public func lifecycleVMBooted(
    requestID: String,
    executionMode: String,
    imageName: String,
    imageURL: URL,
    channelMetadata: [String: String]
  ) {
    var metadata: [String: String] = [
      "image_name": imageName,
      "image_path": imageURL.path,
    ]
    metadata.merge(channelMetadata) { _, new in new }
    logLifecycle(
      LifecycleLogEntry(
        request_id: requestID,
        stage: "vm_boot",
        timestamp: Date(),
        execution_mode: executionMode,
        metadata: metadata))
  }

  public func lifecycleCommandDispatched(
    requestID: String,
    executionMode: String,
    metadata: [String: String]
  ) {
    logLifecycle(
      LifecycleLogEntry(
        request_id: requestID,
        stage: "command_dispatch",
        timestamp: Date(),
        execution_mode: executionMode,
        metadata: metadata))
  }

  public func lifecycleShutdown(
    requestID: String,
    executionMode: String,
    metadata: [String: String]
  ) {
    logLifecycle(
      LifecycleLogEntry(
        request_id: requestID,
        stage: "shutdown",
        timestamp: Date(),
        execution_mode: executionMode,
        metadata: metadata))
  }

  public func exportSpan(_ span: Span) {
    guard let urlString = ProcessInfo.processInfo.environment["OTEL_EXPORT_URL"],
      let url = URL(string: urlString)
    else { return }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONEncoder().encode(span)
    URLSession.shared.dataTask(with: request).resume()
  }

  private func emit<T: Encodable>(_ value: T) {
    if let data = try? JSONEncoder().encode(value), let line = String(data: data, encoding: .utf8) {
      print(line)
    }
  }
}

public struct LogEntry: Codable {
  public let request_id: String
  public let tool: String
  public let duration_ms: Int
  public let metadata: [String: String]
}

public struct LifecycleLogEntry: Codable {
  public let request_id: String
  public let stage: String
  public let timestamp: Date
  public let execution_mode: String
  public let metadata: [String: String]
}

public struct Span: Codable {
  public let trace_id: String
  public let span_id: String
  public let parent_id: String?
  public let name: String
  public let start: Date
  public let end: Date
  public let attributes: [String: String]?
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
