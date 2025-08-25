import Foundation
import ToolsmithSupport

public final class QemuRunner: SandboxRunner {
    private let qemu: URL
    private let image: URL
    private let manifest: ToolManifest?
    public private(set) var forwardedPort: UInt16?

    public init(qemu: URL = URL(fileURLWithPath: "/usr/bin/qemu-system-x86_64"),
                image: URL,
                manifest: ToolManifest? = nil) {
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
        args += ["-virtfs", "local,path=\(workDirectory.path),mount_tag=work,security_model=none"]
        args += ["-virtfs", "local,path=\(workDirectory.path),mount_tag=scratch,security_model=none"]
        for (idx, input) in inputs.enumerated() {
            let tag = "input\(idx)"
            args += ["-virtfs", "local,path=\(input.path),mount_tag=\(tag),security_model=none,readonly"]
        }
        if allowNetwork {
            let port = UInt16.random(in: 40000..<60000)
            forwardedPort = port
            args += ["-netdev", "user,id=net0,hostfwd=tcp:127.0.0.1:\(port)-:8080",
                     "-device", "virtio-net-pci,netdev=net0"]
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
            throw NSError(domain: "QemuRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Process timed out"])
        }
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        return SandboxResult(
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.