import Foundation

public final class BwrapRunner: SandboxRunner {
    private let bwrap: URL
    private let cgroupRoot: URL

    public init(bwrap: URL = URL(fileURLWithPath: "/usr/bin/bwrap"),
                cgroupRoot: URL = URL(fileURLWithPath: "/sys/fs/cgroup")) {
        self.bwrap = bwrap
        self.cgroupRoot = cgroupRoot
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
        try guardWritePaths(arguments: arguments, workDirectory: workDirectory)
        var cgPath: URL?
        if let limits = limits {
            cgPath = try prepareCgroup(limits: limits)
        }

        var args: [String] = ["--die-with-parent"]
        if let seccomp = Bundle.module.url(forResource: "restricted", withExtension: "json") {
            args += ["--seccomp", seccomp.path]
        }
        args += ["--bind", workDirectory.path, "/work"]
        args += ["--bind", workDirectory.path, "/scratch"]
        if !allowNetwork {
            args.append("--unshare-net")
        }
        for input in inputs {
            let target = "/inputs/\(input.lastPathComponent)"
            args.append(contentsOf: ["--ro-bind", input.path, target])
        }
        args.append(contentsOf: [executable])
        args.append(contentsOf: arguments)

        let process = Process()
        process.executableURL = bwrap
        process.arguments = args
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()

        if let cgPath = cgPath {
            try add(pid: process.processIdentifier, toCgroup: cgPath)
        }

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

        if let cgPath = cgPath {
            try? FileManager.default.removeItem(at: cgPath)
        }

        if timedOut {
            throw NSError(domain: "BwrapRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Process timed out"])
        }

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        return SandboxResult(
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }

    func prepareCgroup(limits: CgroupLimits) throws -> URL {
        let path = cgroupRoot.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        if let m = limits.memoryMax {
            try (m + "\n").write(to: path.appendingPathComponent("memory.max"), atomically: true, encoding: .utf8)
        }
        if let c = limits.cpuMax {
            try (c + "\n").write(to: path.appendingPathComponent("cpu.max"), atomically: true, encoding: .utf8)
        }
        if let p = limits.pidsMax {
            try (p + "\n").write(to: path.appendingPathComponent("pids.max"), atomically: true, encoding: .utf8)
        }
        return path
    }

    func add(pid: Int32, toCgroup path: URL) throws {
        try "\(pid)\n".write(to: path.appendingPathComponent("cgroup.procs"), atomically: true, encoding: .utf8)
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.