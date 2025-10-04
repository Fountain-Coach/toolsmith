import Foundation

public struct pdfScan: APIRequest {
  public typealias Body = ScanRequest
  public typealias Response = Index
  public var method: String { "POST" }
  public var path: String { "/pdf/scan" }
  public var body: Body?

  public init(body: Body? = nil) {
    self.body = body
  }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
