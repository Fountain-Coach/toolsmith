import Foundation
import FoundationNetworking
import XCTest

@testable import Toolsmith

final class ToolsmithTests: XCTestCase {
  func testRunLogsAndReturnsID() throws {
    let toolsmith = Toolsmith()
    let out = captureOutput {
      _ = toolsmith.run(tool: "demo", metadata: ["k": "v"], operation: { _ in })
    }
    let (entry, lifecycle) = try decodeOutput(out)
    XCTAssertEqual(entry.tool, "demo")
    XCTAssertEqual(entry.metadata["k"], "v")
    XCTAssertGreaterThanOrEqual(entry.duration_ms, 0)
    XCTAssertEqual(entry.metadata["execution_mode"], ExecutionMode.host.rawValue)
    XCTAssertEqual(lifecycle.map { $0.stage }, ["command_dispatch"])
  }

  func testRunExportsSpanWhenEnvSet() throws {
    setenv("OTEL_EXPORT_URL", "http://example.com", 1)
    let toolsmith = Toolsmith()
    let out = captureOutput {
      _ = toolsmith.run(tool: "demo", operation: { _ in })
    }
    unsetenv("OTEL_EXPORT_URL")
    let (entry, _) = try decodeOutput(out)
    XCTAssertNotNil(entry.metadata["span_id"])
  }

  func testEnsureVirtualMachineImageHydratesCache() async throws {
    let fm = FileManager.default
    let workspace = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let manifestDir = workspace.appendingPathComponent(".toolsmith")
    try fm.createDirectory(at: manifestDir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: workspace) }

    let imageName = "disk.qcow2"
    let imageData = Data("hello".utf8)
    let sourceURL = manifestDir.appendingPathComponent(imageName)
    try imageData.write(to: sourceURL)

    let checksum = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
    let manifestJSON = """
      {
          "image": {
              "name": "demo-image",
              "tarball": "demo-image.tar",
              "sha256": "\(checksum)",
              "qcow2": "\(imageName)",
              "qcow2_sha256": "\(checksum)"
          },
          "tools": {},
          "operations": []
      }
      """
    let manifestURL = manifestDir.appendingPathComponent("tools.json")
    try manifestJSON.data(using: .utf8)!.write(to: manifestURL)

    let toolsmith = Toolsmith(imageDirectory: manifestDir)
    let hydratedURL = try await toolsmith.ensureVirtualMachineImage()

    let expectedURL =
      workspace
      .appendingPathComponent(".toolsmith")
      .appendingPathComponent("cache")
      .appendingPathComponent("demo-image")
      .appendingPathComponent(checksum)
      .appendingPathComponent(imageName)
    XCTAssertEqual(hydratedURL, expectedURL)
    XCTAssertTrue(fm.fileExists(atPath: hydratedURL.path))
    XCTAssertEqual(try Data(contentsOf: hydratedURL), imageData)

    try fm.removeItem(at: sourceURL)
    let cachedURL = try await toolsmith.ensureVirtualMachineImage()
    XCTAssertEqual(cachedURL, expectedURL)
    XCTAssertEqual(try Data(contentsOf: cachedURL), imageData)
  }

  private func decodeOutput(_ output: String) throws -> (LogEntry, [LifecycleLogEntry]) {
    let decoder = JSONDecoder()
    let lines = output.split(whereSeparator: \.isNewline).map(String.init)
    var lifecycle: [LifecycleLogEntry] = []
    var logEntry: LogEntry?
    for line in lines {
      guard let data = line.data(using: .utf8) else { continue }
      if let entry = try? decoder.decode(LifecycleLogEntry.self, from: data) {
        lifecycle.append(entry)
      } else if let entry = try? decoder.decode(LogEntry.self, from: data) {
        logEntry = entry
      }
    }
    let entry = try XCTUnwrap(logEntry)
    return (entry, lifecycle)
  }
}
