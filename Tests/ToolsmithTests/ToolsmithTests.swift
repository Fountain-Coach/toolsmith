import XCTest
import Foundation
import FoundationNetworking
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
            _ = try? toolsmith.run(tool: "demo", metadata: ["k":"v"], operation: {})
        }
        let data = out.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8)!
        let entry = try JSONDecoder().decode(LogEntry.self, from: data)
        XCTAssertEqual(entry.tool, "demo")
        XCTAssertEqual(entry.metadata["k"], "v")
        XCTAssertGreaterThanOrEqual(entry.duration_ms, 0)
    }

    func testRunExportsSpanWhenEnvSet() throws {
        class MockProtocol: URLProtocol {
            nonisolated(unsafe) static var onRequest: (() -> Void)?
            override class func canInit(with request: URLRequest) -> Bool { true }
            override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
            override func startLoading() {
                MockProtocol.onRequest?()
                let response = HTTPURLResponse(url: self.request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocolDidFinishLoading(self)
            }
            override func stopLoading() {}
        }
        URLProtocol.registerClass(MockProtocol.self)
        defer { URLProtocol.unregisterClass(MockProtocol.self) }
        setenv("OTEL_EXPORT_URL", "http://example.com", 1)
        let toolsmith = Toolsmith()
        let exp = expectation(description: "span sent")
        MockProtocol.onRequest = { exp.fulfill() }
        let out = captureOutput {
            _ = toolsmith.run(tool: "demo", operation: {})
        }
        wait(for: [exp], timeout: 1)
        unsetenv("OTEL_EXPORT_URL")
        let data = out.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8)!
        let entry = try JSONDecoder().decode(LogEntry.self, from: data)
        XCTAssertNotNil(entry.metadata["span_id"])
    }
}
