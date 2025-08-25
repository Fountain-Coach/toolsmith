// Models for Tool Server

public struct BitField: Codable, Sendable {
    public let bits: [Int]
    public let name: String
    public init(bits: [Int], name: String) {
        self.bits = bits
        self.name = name
    }
}

public struct EnumCase: Codable, Sendable {
    public let name: String
    public let value: Int
    public init(name: String, value: Int) {
        self.name = name
        self.value = value
    }
}

public struct EnumSpec: Codable, Sendable {
    public let cases: [EnumCase]
    public let field: String
    public init(cases: [EnumCase], field: String) {
        self.cases = cases
        self.field = field
    }
}

public struct ExportMatrixRequest: Codable, Sendable {
    public let bitfields: Bool?
    public let enums: Bool?
    public let index: Index
    public let ranges: Bool?
    public init(bitfields: Bool? = nil, enums: Bool? = nil, index: Index, ranges: Bool? = nil) {
        self.bitfields = bitfields
        self.enums = enums
        self.index = index
        self.ranges = ranges
    }
}

public struct Index: Codable, Sendable {
    public let documents: [IndexedDocument]
    public init(documents: [IndexedDocument]) {
        self.documents = documents
    }
}

public struct IndexedDocument: Codable, Sendable {
    public let id: String
    public let fileName: String
    public let size: Int
    public let sha256: String?
    public let pages: [IndexedPage]?

    public init(id: String, fileName: String, size: Int, sha256: String? = nil, pages: [IndexedPage]? = nil) {
        self.id = id
        self.fileName = fileName
        self.size = size
        self.sha256 = sha256
        self.pages = pages
    }

    public struct IndexedPage: Codable, Sendable {
        public let number: Int?
        public let text: String?
        public init(number: Int? = nil, text: String? = nil) {
            self.number = number
            self.text = text
        }
    }
}

public struct Matrix: Codable, Sendable {
    public let bitfields: [BitField]?
    public let enums: [EnumSpec]?
    public let messages: [MatrixEntry]
    public let ranges: [RangeSpec]?
    public let schemaVersion: String
    public let terms: [MatrixEntry]
    public init(bitfields: [BitField]? = nil, enums: [EnumSpec]? = nil, messages: [MatrixEntry], ranges: [RangeSpec]? = nil, schemaVersion: String, terms: [MatrixEntry]) {
        self.bitfields = bitfields
        self.enums = enums
        self.messages = messages
        self.ranges = ranges
        self.schemaVersion = schemaVersion
        self.terms = terms
    }
}

public struct MatrixEntry: Codable, Sendable {
    public let page: Int
    public let text: String
    public let x: Int
    public let y: Int
    public init(page: Int, text: String, x: Int, y: Int) {
        self.page = page
        self.text = text
        self.x = x
        self.y = y
    }
}

public struct QueryRequest: Codable, Sendable {
    public let index: Index
    public let pageRange: String
    public let q: String
    public init(index: Index, pageRange: String, q: String) {
        self.index = index
        self.pageRange = pageRange
        self.q = q
    }
}

public struct QueryHit: Codable, Sendable {
    public let docId: String?
    public let page: Int?
    public let snippet: String?
    public init(docId: String? = nil, page: Int? = nil, snippet: String? = nil) {
        self.docId = docId
        self.page = page
        self.snippet = snippet
    }
}

public struct QueryResponse: Codable, Sendable {
    public let hits: [QueryHit]
    public init(hits: [QueryHit]) {
        self.hits = hits
    }
}

public struct RangeSpec: Codable, Sendable {
    public let field: String
    public let max: Int
    public let min: Int
    public init(field: String, max: Int, min: Int) {
        self.field = field
        self.max = max
        self.min = min
    }
}

public struct ScanRequest: Codable, Sendable {
    public let includeText: Bool
    public let inputs: [String]
    public let sha256: Bool
    public init(includeText: Bool, inputs: [String], sha256: Bool) {
        self.includeText = includeText
        self.inputs = inputs
        self.sha256 = sha256
    }
}

public struct ToolRequest: Codable, Sendable {
    public let args: [String]
    public let request_id: String
    public init(args: [String], request_id: String) {
        self.args = args
        self.request_id = request_id
    }
}

public struct ValidationResult: Codable, Sendable {
    public let issues: [String]
    public let ok: Bool
    public init(issues: [String], ok: Bool) {
        self.issues = issues
        self.ok = ok
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.