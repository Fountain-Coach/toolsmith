import Foundation

public struct SandboxResult {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32

    public init(stdout: String, stderr: String, exitCode: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

public struct CgroupLimits {
    public var memoryMax: String?
    public var cpuMax: String?
    public var pidsMax: String?

    public init(memoryMax: String? = nil, cpuMax: String? = nil, pidsMax: String? = nil) {
        self.memoryMax = memoryMax
        self.cpuMax = cpuMax
        self.pidsMax = pidsMax
    }
}

public protocol SandboxRunner {
    @discardableResult
    func run(
        executable: String,
        arguments: [String],
        inputs: [URL],
        workDirectory: URL,
        allowNetwork: Bool,
        timeout: TimeInterval?,
        limits: CgroupLimits?
    ) throws -> SandboxResult
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.