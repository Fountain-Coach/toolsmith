import Crypto
import Foundation

public struct ToolManifest: Codable, Sendable {
  public struct Image: Codable, Sendable {
    public let name: String
    public let tarball: String
    public let sha256: String
    public let qcow2: String
    public let qcow2_sha256: String

    public init(name: String, tarball: String, sha256: String, qcow2: String, qcow2_sha256: String)
    {
      self.name = name
      self.tarball = tarball
      self.sha256 = sha256
      self.qcow2 = qcow2
      self.qcow2_sha256 = qcow2_sha256
    }
  }
  public let image: Image
  public let tools: [String: String]
  public let operations: [String]

  public init(image: Image, tools: [String: String], operations: [String]) {
    self.image = image
    self.tools = tools
    self.operations = operations
  }

  public enum ManifestError: Error, Equatable {
    case imageNotListed
    case checksumMismatch(expected: String, actual: String)
  }

  public static func load(from url: URL) throws -> ToolManifest {
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(ToolManifest.self, from: data)
  }

  public static func sha256(of url: URL) throws -> String {
    let data = try Data(contentsOf: url)
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  public func verify(fileAt url: URL) throws {
    let name = url.lastPathComponent
    let expected: String?
    if name == image.qcow2 {
      expected = image.qcow2_sha256
    } else if name == image.tarball {
      expected = image.sha256
    } else {
      expected = nil
    }
    guard let exp = expected else { throw ManifestError.imageNotListed }
    let actual = try Self.sha256(of: url)
    guard actual == exp else { throw ManifestError.checksumMismatch(expected: exp, actual: actual) }
  }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
