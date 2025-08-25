import Foundation

public struct runLibPlist: APIRequest {
    public typealias Body = ToolRequest
    public typealias Response = Data
    public var method: String { "POST" }
    public var path: String { "/libplist" }
    public var body: Body?

    public init(body: Body? = nil) {
        self.body = body
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.