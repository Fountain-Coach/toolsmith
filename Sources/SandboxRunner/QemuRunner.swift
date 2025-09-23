import Foundation
import ToolsmithSupport

public final class QemuRunner: SandboxRunner {
  public struct Instance {
    public let process: Process
    public let endpoint: CommandChannelEndpoint

    public func shutdown() {
      if process.isRunning {
        process.terminate()
        process.waitUntilExit()
      }
    }
  }

  public struct ExportMount: Sendable {
    public let url: URL
    public let tag: String

    public init(url: URL, tag: String) {
      self.url = url
      self.tag = tag
    }
  }

  private let qemu: URL
  private let image: URL
  private let manifest: ToolManifest?
  public private(set) var forwardedPort: UInt16?

  public init(
    qemu: URL = URL(fileURLWithPath: "/usr/bin/qemu-system-x86_64"),
    image: URL,
    manifest: ToolManifest? = nil
  ) {
    self.qemu = qemu
    self.image = image
    self.manifest = manifest
  }

  @discardableResult
  public func run(
    executable: String,
    arguments: [String] = [],
    inputs: [URL] = [],
    workDirectory: URL,
    allowNetwork: Bool = false,
    timeout: TimeInterval? = nil,
    limits: CgroupLimits? = nil
  ) throws -> SandboxResult {
    _ = limits
    try guardWritePaths(arguments: arguments, workDirectory: workDirectory)
    if let manifest = manifest {
      try manifest.verify(fileAt: image)
    }
    var args: [String] = []
    #if os(macOS)
      args += ["-accel", "hvf"]
    #else
      args += ["-enable-kvm"]
    #endif
    args += ["-drive", "file=\(image.path),if=virtio,snapshot=on"]
    args += [
      "-virtfs",
      "local,path=\(workDirectory.path),mount_tag=work,security_model=none,readonly",
    ]
    args += [
      "-virtfs",
      "local,path=\(workDirectory.path),mount_tag=scratch,security_model=none,readonly",
    ]
    for (idx, input) in inputs.enumerated() {
      let tag = "input\(idx)"
      args += ["-virtfs", "local,path=\(input.path),mount_tag=\(tag),security_model=none,readonly"]
    }
    if allowNetwork {
      let port = UInt16.random(in: 40000..<60000)
      forwardedPort = port
      args += [
        "-netdev", "user,id=net0,hostfwd=tcp:127.0.0.1:\(port)-:8080",
        "-device", "virtio-net-pci,netdev=net0",
      ]
    } else {
      forwardedPort = nil
      args += ["-net", "none"]
    }
    if let seccomp = Bundle.module.url(forResource: "restricted", withExtension: "json") {
      args += ["-seccomp", seccomp.path]
    }
    args += ["-nographic"]
    let command = ([executable] + arguments).joined(separator: " ")
    args += ["-append", command]

    let process = Process()
    process.executableURL = qemu
    process.arguments = args
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()

    var timedOut = false
    if let timeout = timeout {
      let group = DispatchGroup()
      group.enter()
      process.terminationHandler = { _ in group.leave() }
      if group.wait(timeout: .now() + timeout) == .timedOut {
        timedOut = true
        process.terminate()
        process.waitUntilExit()
      }
    } else {
      process.waitUntilExit()
    }
    if timedOut {
      throw NSError(
        domain: "QemuRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Process timed out"])
    }
    let outData = stdout.fileHandleForReading.readDataToEndOfFile()
    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
    return SandboxResult(
      stdout: String(data: outData, encoding: .utf8) ?? "",
      stderr: String(data: errData, encoding: .utf8) ?? "",
      exitCode: process.terminationStatus
    )
  }
  public func launchVirtualMachine(
    workspace: URL,
    writableExports: [ExportMount] = [],
    additionalArguments: [String] = []
  ) throws -> Instance {
    if let manifest = manifest {
      try manifest.verify(fileAt: image)
    }

    var args: [String] = []
    #if os(macOS)
      args += ["-accel", "hvf"]
    #else
      args += ["-enable-kvm"]
    #endif
    args += ["-drive", "file=\(image.path),if=virtio,snapshot=on"]
    args += [
      "-virtfs",
      "local,path=\(workspace.path),mount_tag=work,security_model=none,readonly",
    ]
    for export in writableExports {
      args += [
        "-virtfs",
        "local,path=\(export.url.path),mount_tag=\(export.tag),security_model=none",
      ]
    }
    let commandPort = UInt16.random(in: 40000..<60000)
    forwardedPort = commandPort
    args += [
      "-netdev", "user,id=net0,hostfwd=tcp:127.0.0.1:\(commandPort)-:3023",
      "-device", "virtio-net-pci,netdev=net0",
    ]
    if let seccomp = Bundle.module.url(forResource: "restricted", withExtension: "json") {
      args += ["-seccomp", seccomp.path]
    }
    args += ["-nographic"]
    args += additionalArguments

    let process = Process()
    process.executableURL = qemu
    process.arguments = args
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try process.run()

    let endpoint = CommandChannelEndpoint(transport: .tcp(host: "127.0.0.1", port: commandPort))
    return Instance(process: process, endpoint: endpoint)
  }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
