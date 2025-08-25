import Foundation

public struct pdfExportMatrix: APIRequest {
    public typealias Body = ExportMatrixRequest
    public typealias Response = Matrix
    public var method: String { "POST" }
    public var path: String { "/pdf/export-matrix" }
    public var body: Body?

    public init(body: Body? = nil) {
        self.body = body
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.