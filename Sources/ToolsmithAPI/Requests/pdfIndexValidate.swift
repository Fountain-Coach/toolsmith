import Foundation

public struct pdfIndexValidate: APIRequest {
  public typealias Body = Index
  public typealias Response = ValidationResult
  public var method: String { "POST" }
  public var path: String { "/pdf/index/validate" }
  public var body: Body?

  public init(body: Body? = nil) {
    self.body = body
  }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
