import Foundation
import ToolsmithSupport

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public enum ToolsmithError: Error {
  case manifestUnavailable
}

public enum ExecutionMode: String {
  case automatic
  case host
  case vm
}

public struct ExecutionContext {
  public enum Backend {
    case host(HostRunner)
    case virtualMachine(any CommandChannel)
  }

  public struct HostRunner {
    public struct Result {
      public let stdout: String
      public let stderr: String
      public let exitCode: Int32

      public init(stdout: String, stderr: String, exitCode: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
      }
    }

    public init() {}

    public func run(
      executable: String,
      arguments: [String] = [],
      environment: [String: String] = [:],
      currentDirectory: URL? = nil
    ) throws -> Result {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: executable)
      process.arguments = arguments
      if !environment.isEmpty {
        process.environment = environment
      }
      if let dir = currentDirectory {
        process.currentDirectoryURL = dir
      }
      let stdout = Pipe()
      let stderr = Pipe()
      process.standardOutput = stdout
      process.standardError = stderr
      try process.run()
      process.waitUntilExit()

      let outData = stdout.fileHandleForReading.readDataToEndOfFile()
      let errData = stderr.fileHandleForReading.readDataToEndOfFile()
      return Result(
        stdout: String(data: outData, encoding: .utf8) ?? "",
        stderr: String(data: errData, encoding: .utf8) ?? "",
        exitCode: process.terminationStatus)
    }
  }

  public let mode: ExecutionMode
  public let backend: Backend

  public init(mode: ExecutionMode, backend: Backend) {
    self.mode = mode
    self.backend = backend
  }
}

public final class Toolsmith {
  private let logger: JSONLogger
  public let manifest: ToolManifest?
  private let imageHydrator: ImageHydrator?
  private let makeVirtualMachine: @Sendable (URL, ToolManifest?, URL) -> VirtualMachineManaging

  public init(
    imageDirectory: URL = URL(fileURLWithPath: "."),
    session: URLSession = .shared,
    fileManager: FileManager = .default,
    logger: JSONLogger = JSONLogger(),
    makeVirtualMachine: @escaping @Sendable (URL, ToolManifest?, URL) -> VirtualMachineManaging = {
      imageURL, manifest, workspace in
      VirtualMachine(imageURL: imageURL, manifest: manifest, workspace: workspace)
    }
  ) {
    self.logger = logger
    let manifestURL = imageDirectory.appendingPathComponent("tools.json")
    let manifest = try? ToolManifest.load(from: manifestURL)
    self.manifest = manifest
    if let manifest = manifest {
      self.imageHydrator = ImageHydrator(
        manifest: manifest, manifestURL: manifestURL, session: session, fileManager: fileManager)
    } else {
      self.imageHydrator = nil
    }
    self.makeVirtualMachine = makeVirtualMachine
  }

  @discardableResult
  public func run(
    tool: String,
    metadata: [String: String] = [:],
    requestID: String = UUID().uuidString,
    execution: ExecutionMode = .automatic,
    operation: (ExecutionContext) throws -> Void
  ) rethrows -> String {
    var meta = metadata
    let start = Date()
    var executionModeValue: String?
    defer {
      let end = Date()
      let duration = Int(end.timeIntervalSince(start) * 1000)
      if let executionModeValue {
        meta["execution_mode"] = executionModeValue
      }
      if ProcessInfo.processInfo.environment["OTEL_EXPORT_URL"] != nil {
        let spanID = UUID().uuidString
        let attributes = executionModeValue.map { ["execution_mode": $0] }
        let span = Span(
          trace_id: requestID, span_id: spanID, parent_id: nil, name: tool, start: start,
          end: end, attributes: attributes)
        logger.exportSpan(span)
        meta["span_id"] = spanID
      }
      let entry = LogEntry(request_id: requestID, tool: tool, duration_ms: duration, metadata: meta)
      logger.log(entry)
    }

    let (context, cleanup, lifecycleMetadata) = resolveExecutionContext(
      preferred: execution, requestID: requestID)
    executionModeValue = context.mode.rawValue
    logger.lifecycleCommandDispatched(
      requestID: requestID, executionMode: context.mode.rawValue, metadata: lifecycleMetadata)
    defer { cleanup?() }

    try operation(context)
    return requestID
  }

  public func ensureVirtualMachineImage() async throws -> URL {
    guard let hydrator = imageHydrator else { throw ToolsmithError.manifestUnavailable }
    return try await hydrator.ensureImageAvailable()
  }

  private func resolveExecutionContext(preferred execution: ExecutionMode, requestID: String)
    -> (ExecutionContext, (() -> Void)?, [String: String])
  {
    let env = ProcessInfo.processInfo.environment["TOOLSMITH_EXECUTION"].flatMap {
      ExecutionMode(rawValue: $0)
    }
    let requestedMode: ExecutionMode
    if execution != .automatic {
      requestedMode = execution
    } else if let env = env {
      requestedMode = env
    } else {
      requestedMode = execution
    }

    let resolvedMode: ExecutionMode
    switch requestedMode {
    case .automatic:
      resolvedMode = imageHydrator == nil ? .host : .vm
    case .host, .vm:
      resolvedMode = requestedMode
    }

    switch resolvedMode {
    case .host:
      let context = ExecutionContext(mode: .host, backend: .host(.init()))
      return (context, nil, ["backend": "host"])
    case .vm:
      guard let imageHydrator else {
        let context = ExecutionContext(mode: .host, backend: .host(.init()))
        return (context, nil, ["backend": "host", "reason": "missing_image"])
      }
      let cacheDirectory = imageHydrator.cacheDirectory()
      let image = imageHydrator.image
      let downloadRequired = !imageHydrator.cachedImageIsValid()
      let sourceURL = try? imageHydrator.sourceURL()
      if downloadRequired {
        logger.lifecycleDownloadStarted(
          requestID: requestID, executionMode: ExecutionMode.vm.rawValue, imageName: image.name,
          cacheURL: cacheDirectory, source: sourceURL)
      }
      do {
        let imageURL = try waitForAsync { try await imageHydrator.ensureImageAvailable() }
        if downloadRequired {
          logger.lifecycleDownloadFinished(
            requestID: requestID, executionMode: ExecutionMode.vm.rawValue, imageName: image.name,
            cacheURL: cacheDirectory, source: sourceURL, success: true)
        }
        logger.lifecycleChecksumVerified(
          requestID: requestID, executionMode: ExecutionMode.vm.rawValue, imageName: image.name,
          imageURL: imageURL, digest: image.qcow2_sha256)
        let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let machine = makeVirtualMachine(imageURL, manifest, workspace)
        let channel = try waitForAsync { try await machine.start() }
        let channelMetadata: [String: String]
        switch channel.endpoint.transport {
        case .tcp(let host, let port):
          channelMetadata = [
            "transport": "tcp",
            "host": host,
            "port": String(port),
          ]
        case .unixDomainSocket(let path):
          channelMetadata = [
            "transport": "unix",
            "path": path,
          ]
        }
        logger.lifecycleVMBooted(
          requestID: requestID, executionMode: ExecutionMode.vm.rawValue, imageName: image.name,
          imageURL: imageURL, channelMetadata: channelMetadata)
        var lifecycleMetadata = channelMetadata
        lifecycleMetadata["backend"] = "vm"
        lifecycleMetadata["image_name"] = image.name
        lifecycleMetadata["image_path"] = imageURL.path
        lifecycleMetadata["cache_path"] = cacheDirectory.path
        let context = ExecutionContext(mode: .vm, backend: .virtualMachine(channel))
        let cleanup = { [logger = self.logger, requestID, lifecycleMetadata] in
          logger.lifecycleShutdown(
            requestID: requestID, executionMode: ExecutionMode.vm.rawValue,
            metadata: lifecycleMetadata)
          _ = Task { await machine.shutdown() }
        }
        return (context, cleanup, lifecycleMetadata)
      } catch {
        if downloadRequired {
          logger.lifecycleDownloadFinished(
            requestID: requestID, executionMode: ExecutionMode.vm.rawValue, imageName: image.name,
            cacheURL: cacheDirectory, source: sourceURL, success: false,
            errorDescription: String(describing: error))
        }
        return (
          ExecutionContext(mode: .host, backend: .host(.init())), nil,
          [
            "backend": "host",
            "reason": "vm_unavailable",
            "error": String(describing: error),
          ]
        )
      }
    case .automatic:
      return (ExecutionContext(mode: .host, backend: .host(.init())), nil, ["backend": "host"])
    }
  }

  private func waitForAsync<T>(
    _ work: @escaping @Sendable () async throws -> T
  ) throws -> T {
    let box = ResultBox<T>()
    let semaphore = DispatchSemaphore(value: 0)
    Task.detached {
      do {
        let value = try await work()
        box.result = .success(value)
      } catch {
        box.result = .failure(error)
      }
      semaphore.signal()
    }
    semaphore.wait()
    guard let outcome = box.result else {
      throw ToolsmithError.manifestUnavailable
    }
    return try outcome.get()
  }

  private final class ResultBox<Value>: @unchecked Sendable {
    var result: Result<Value, Error>?
  }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
