import Foundation

public struct pdfQuery: APIRequest {
    public typealias Body = QueryRequest
    public typealias Response = QueryResponse
    public var method: String { "POST" }
    public var path: String { "/pdf/query" }
    public var body: Body?

    public init(body: Body? = nil) {
        self.body = body
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.