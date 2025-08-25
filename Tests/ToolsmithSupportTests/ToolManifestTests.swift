import XCTest
@testable import ToolsmithSupport

final class ToolManifestTests: XCTestCase {
    func testLoadAndVerify() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let imageURL = tmp.appendingPathComponent("image.qcow2")
        try Data("hello".utf8).write(to: imageURL)
        let sha = try ToolManifest.sha256(of: imageURL)
        let manifest = ToolManifest(image: .init(name: "img", tarball: "image.tar", sha256: sha, qcow2: "image.qcow2", qcow2_sha256: sha), tools: [:], operations: [])
        let manifestURL = tmp.appendingPathComponent("tools.json")
        try JSONEncoder().encode(manifest).write(to: manifestURL)
        let loaded = try ToolManifest.load(from: manifestURL)
        XCTAssertEqual(loaded.image.qcow2, "image.qcow2")
        XCTAssertNoThrow(try loaded.verify(fileAt: imageURL))
    }

    func testVerifyChecksumMismatch() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let imageURL = tmp.appendingPathComponent("image.qcow2")
        try Data("data".utf8).write(to: imageURL)
        let manifest = ToolManifest(image: .init(name: "img", tarball: "image.tar", sha256: "bad", qcow2: "image.qcow2", qcow2_sha256: "bad"), tools: [:], operations: [])
        do {
            try manifest.verify(fileAt: imageURL)
            XCTFail("Expected checksum mismatch")
        } catch ToolManifest.ManifestError.checksumMismatch(let expected, let actual) {
            XCTAssertEqual(expected, "bad")
            XCTAssertNotEqual(expected, actual)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testVerifyImageNotListed() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let otherURL = tmp.appendingPathComponent("other.qcow2")
        try Data().write(to: otherURL)
        let manifest = ToolManifest(image: .init(name: "img", tarball: "image.tar", sha256: "", qcow2: "image.qcow2", qcow2_sha256: ""), tools: [:], operations: [])
        XCTAssertThrowsError(try manifest.verify(fileAt: otherURL)) { error in
            XCTAssertEqual(error as? ToolManifest.ManifestError, .imageNotListed)
        }
    }
}
