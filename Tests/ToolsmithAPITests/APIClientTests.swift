import XCTest
import Foundation
import FoundationNetworking
@testable import ToolsmithAPI

final class APIClientTests: XCTestCase {
    final class MockSession: HTTPSession {
        var lastRequest: URLRequest?
        var data: Data
        init(data: Data) { self.data = data }
        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            lastRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
    }

    func testSendEncodesBodyAndHeaders() async throws {
        let responseData = try JSONEncoder().encode(ValidationResult(issues: [], ok: true))
        let session = MockSession(data: responseData)
        let client = APIClient(baseURL: URL(string: "https://example.com")!, bearerToken: "TOKEN", session: session)
        let index = Index(documents: [])
        let result: ValidationResult = try await client.send(pdfIndexValidate(body: index))
        XCTAssertTrue(result.ok)
        let req = session.lastRequest
        XCTAssertEqual(req?.httpMethod, "POST")
        XCTAssertEqual(req?.url?.path, "/pdf/index/validate")
        XCTAssertEqual(req?.value(forHTTPHeaderField: "Authorization"), "Bearer TOKEN")
        XCTAssertEqual(req?.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }
}
