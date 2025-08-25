import XCTest
@testable import SandboxRunner

final class PathGuardTests: XCTestCase {
    func testAllowsWorkDirectory() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        XCTAssertNoThrow(try guardWritePaths(arguments: ["file.txt", "-v"], workDirectory: tmp))
    }

    func testRejectsAbsolutePath() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        XCTAssertThrowsError(try guardWritePaths(arguments: ["/etc/passwd"], workDirectory: tmp))
    }

    func testRejectsParentReference() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        XCTAssertThrowsError(try guardWritePaths(arguments: ["../outside"], workDirectory: tmp))
    }
}
