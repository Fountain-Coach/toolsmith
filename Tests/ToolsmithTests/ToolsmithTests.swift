import Foundation
import FoundationNetworking
import XCTest

@testable import Toolsmith

final class ToolsmithTests: XCTestCase {
  func captureOutput(_ work: () -> Void) -> String {
    let pipe = Pipe()
    let fd = dup(STDOUT_FILENO)
    dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
    work()
    fflush(nil)
    dup2(fd, STDOUT_FILENO)
    pipe.fileHandleForWriting.closeFile()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
  }

  func testRunLogsAndReturnsID() throws {
    let toolsmith = Toolsmith()
    let out = captureOutput {
      _ = toolsmith.run(tool: "demo", metadata: ["k": "v"], operation: {})
    }
    let data = out.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8)!
    let entry = try JSONDecoder().decode(LogEntry.self, from: data)
    XCTAssertEqual(entry.tool, "demo")
    XCTAssertEqual(entry.metadata["k"], "v")
    XCTAssertGreaterThanOrEqual(entry.duration_ms, 0)
  }

  func testRunExportsSpanWhenEnvSet() throws {
    setenv("OTEL_EXPORT_URL", "http://example.com", 1)
    let toolsmith = Toolsmith()
    let out = captureOutput {
      _ = toolsmith.run(tool: "demo", operation: {})
    }
    unsetenv("OTEL_EXPORT_URL")
    let data = out.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8)!
    let entry = try JSONDecoder().decode(LogEntry.self, from: data)
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
}
