import Crypto
import Foundation
import FoundationNetworking
import SandboxRunner
import XCTest

@testable import Toolsmith
import ToolsmithSupport

final class ToolsmithVirtualizationTests: XCTestCase {
  private func makeManifest(
    imageName: String,
    qcow2Path: String,
    checksum: String
  ) -> ToolManifest {
    ToolManifest(
      image: .init(
        name: "demo-image",
        tarball: "demo-image.tar",
        sha256: checksum,
        qcow2: qcow2Path,
        qcow2_sha256: checksum
      ),
      tools: [:],
      operations: []
    )
  }

  func testEnsureImageAvailableSkipsRedownloadWhenCacheValid() async throws {
    let fm = FileManager.default
    let workspace = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let manifestDir = workspace.appendingPathComponent(".toolsmith")
    try fm.createDirectory(at: manifestDir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: workspace) }

    let imageName = "disk.qcow2"
    let imageData = Data("virtual-machine".utf8)
    let checksum = SHA256.hash(data: imageData).map { String(format: "%02x", $0) }.joined()
    let manifest = makeManifest(imageName: imageName, qcow2Path: imageName, checksum: checksum)
    let manifestURL = manifestDir.appendingPathComponent("tools.json")
    let sourceURL = manifestDir.appendingPathComponent(imageName)
    try imageData.write(to: sourceURL)

    let hydrator = ImageHydrator(manifest: manifest, manifestURL: manifestURL, fileManager: fm)
    let firstURL = try await hydrator.ensureImageAvailable()
    XCTAssertTrue(fm.fileExists(atPath: firstURL.path))
    XCTAssertEqual(try Data(contentsOf: firstURL), imageData)

    try fm.removeItem(at: sourceURL)
    let cachedURL = try await hydrator.ensureImageAvailable()
    XCTAssertEqual(cachedURL, firstURL)
    XCTAssertTrue(fm.fileExists(atPath: cachedURL.path))
    XCTAssertEqual(try Data(contentsOf: cachedURL), imageData)
  }

  func testEnsureImageAvailableThrowsOnChecksumMismatch() async throws {
    let fm = FileManager.default
    let workspace = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let manifestDir = workspace.appendingPathComponent(".toolsmith")
    try fm.createDirectory(at: manifestDir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: workspace) }

    let imageName = "disk.qcow2"
    let expectedData = Data("expected".utf8)
    let checksum = SHA256.hash(data: expectedData).map { String(format: "%02x", $0) }.joined()
    let manifest = makeManifest(imageName: imageName, qcow2Path: imageName, checksum: checksum)
    let manifestURL = manifestDir.appendingPathComponent("tools.json")
    let sourceURL = manifestDir.appendingPathComponent(imageName)
    let wrongData = Data("unexpected".utf8)
    try wrongData.write(to: sourceURL)

    let hydrator = ImageHydrator(manifest: manifest, manifestURL: manifestURL, fileManager: fm)

    do {
      _ = try await hydrator.ensureImageAvailable()
      XCTFail("Expected checksum mismatch")
    } catch let error as ToolManifest.ManifestError {
      switch error {
      case .checksumMismatch(let expected, let actual):
        XCTAssertEqual(expected, checksum)
        XCTAssertNotEqual(expected, actual)
      default:
        XCTFail("Unexpected manifest error: \(error)")
      }
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testRunHonorsExecutionOverrideAndLogsVM() throws {
    let fm = FileManager.default
    let workspace = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let manifestDir = workspace.appendingPathComponent(".toolsmith")
    try fm.createDirectory(at: manifestDir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: workspace) }

    let imageData = Data("cached".utf8)
    let checksum = SHA256.hash(data: imageData).map { String(format: "%02x", $0) }.joined()
    let imageName = "disk.qcow2"
    let manifest = makeManifest(imageName: imageName, qcow2Path: imageName, checksum: checksum)
    let manifestURL = manifestDir.appendingPathComponent("tools.json")
    try JSONEncoder().encode(manifest).write(to: manifestURL)

    let hydrator = ImageHydrator(manifest: manifest, manifestURL: manifestURL, fileManager: fm)
    try fm.createDirectory(
      at: hydrator.cacheDirectory(), withIntermediateDirectories: true, attributes: nil)
    try imageData.write(to: hydrator.cachedImageURL())

    let channel = FakeCommandChannel(endpoint: CommandChannelEndpoint(transport: .tcp(host: "127.0.0.1", port: 9)))
    let shutdownExpectation = expectation(description: "shutdown called")
    let fakeVM = FakeVirtualMachine(channel: channel, shutdownExpectation: shutdownExpectation)

    setenv("TOOLSMITH_EXECUTION", "vm", 1)
    defer { unsetenv("TOOLSMITH_EXECUTION") }

    let toolsmith = Toolsmith(
      imageDirectory: manifestDir,
      fileManager: fm,
      makeVirtualMachine: { _, _, _ in fakeVM }
    )

    let output = captureOutput {
      _ = toolsmith.run(tool: "format", requestID: "req-1") { context in
        XCTAssertEqual(context.mode, .vm)
        switch context.backend {
        case .virtualMachine:
          break
        case .host:
          XCTFail("Expected VM backend")
        }
      }
    }

    wait(for: [shutdownExpectation], timeout: 1)

    XCTAssertEqual(fakeVM.startCallCount, 1)
    XCTAssertEqual(fakeVM.shutdownCallCount, 1)
    XCTAssertEqual(channel.connectCallCount, 1)
    XCTAssertEqual(channel.shutdownCallCount, 1)

    let logs = parseLogs(output)
    let lifecycleStages = logs.lifecycle.map { $0.stage }
    XCTAssertEqual(logs.log.metadata["execution_mode"], "vm")
    XCTAssertTrue(lifecycleStages.contains("command_dispatch"))
    XCTAssertTrue(lifecycleStages.contains("checksum_verified"))
    XCTAssertTrue(lifecycleStages.contains("vm_boot"))
    XCTAssertTrue(lifecycleStages.contains("shutdown"))
  }

  func testHostModeOmitsVMLifecycleEvents() throws {
    setenv("TOOLSMITH_EXECUTION", "host", 1)
    defer { unsetenv("TOOLSMITH_EXECUTION") }

    let toolsmith = Toolsmith(makeVirtualMachine: { _, _, _ in
      XCTFail("Host mode should not create VM")
      return FakeVirtualMachine(
        channel: FakeCommandChannel(
          endpoint: CommandChannelEndpoint(transport: .tcp(host: "127.0.0.1", port: 9))))
    })

    let output = captureOutput {
      _ = toolsmith.run(tool: "lint", requestID: "host-req") { context in
        XCTAssertEqual(context.mode, .host)
        switch context.backend {
        case .host:
          break
        case .virtualMachine:
          XCTFail("Expected host backend")
        }
      }
    }

    let logs = parseLogs(output)
    XCTAssertEqual(logs.log.metadata["execution_mode"], "host")
    XCTAssertEqual(Set(logs.lifecycle.map { $0.stage }), Set(["command_dispatch"]))
  }

  private func parseLogs(_ output: String) -> (log: LogEntry, lifecycle: [LifecycleLogEntry]) {
    let decoder = JSONDecoder()
    let lines = output.split(whereSeparator: \.isNewline).map(String.init)
    var lifecycle: [LifecycleLogEntry] = []
    var logEntry: LogEntry?
    for line in lines {
      let data = line.data(using: .utf8) ?? Data()
      if let entry = try? decoder.decode(LifecycleLogEntry.self, from: data) {
        lifecycle.append(entry)
      } else if let entry = try? decoder.decode(LogEntry.self, from: data) {
        logEntry = entry
      } else {
        XCTFail("Unexpected log line: \(line)")
      }
    }
    XCTAssertNotNil(logEntry)
    return (logEntry!, lifecycle)
  }
}

private final class FakeCommandChannel: CommandChannel, @unchecked Sendable {
  let endpoint: CommandChannelEndpoint
  private(set) var connectCallCount = 0
  private(set) var shutdownCallCount = 0

  init(endpoint: CommandChannelEndpoint) {
    self.endpoint = endpoint
  }

  func connect() async throws {
    connectCallCount += 1
  }

  func runCommand(
    _ invocation: CommandChannelAdapter.CommandInvocation
  ) -> AsyncThrowingStream<CommandChannelAdapter.StatusUpdate, Error> {
    AsyncThrowingStream { continuation in
      continuation.finish()
    }
  }

  func requestShutdown() async throws {
    shutdownCallCount += 1
  }
}

private final class FakeVirtualMachine: VirtualMachineManaging, @unchecked Sendable {
  private let channel: FakeCommandChannel
  private let shutdownExpectation: XCTestExpectation?
  private(set) var startCallCount = 0
  private(set) var shutdownCallCount = 0

  init(channel: FakeCommandChannel, shutdownExpectation: XCTestExpectation? = nil) {
    self.channel = channel
    self.shutdownExpectation = shutdownExpectation
  }

  @discardableResult
  func start(writableExports: [QemuRunner.ExportMount]) async throws -> any CommandChannel {
    startCallCount += 1
    try await channel.connect()
    return channel
  }

  func shutdown() async {
    shutdownCallCount += 1
    try? await channel.requestShutdown()
    shutdownExpectation?.fulfill()
  }
}
