import XCTest
@testable import SandboxRunner

final class BwrapRunnerTests: XCTestCase {
    func testPrepareCgroupAndAdd() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let runner = BwrapRunner(bwrap: URL(fileURLWithPath: "/bin/echo"), cgroupRoot: root)
        let limits = CgroupLimits(memoryMax: "100M", cpuMax: "1000 1000", pidsMax: "10")
        let path = try runner.prepareCgroup(limits: limits)
        let mem = try String(contentsOf: path.appendingPathComponent("memory.max")).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(mem, "100M")
        let cpu = try String(contentsOf: path.appendingPathComponent("cpu.max")).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(cpu, "1000 1000")
        let pids = try String(contentsOf: path.appendingPathComponent("pids.max")).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(pids, "10")
        try runner.add(pid: 42, toCgroup: path)
        let procs = try String(contentsOf: path.appendingPathComponent("cgroup.procs")).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(procs, "42")
    }
}
