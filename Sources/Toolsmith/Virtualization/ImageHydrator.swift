import Foundation
import ToolsmithSupport

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public struct ImageHydrator: @unchecked Sendable {
  private let manifest: ToolManifest
  private let manifestURL: URL
  private let session: URLSession
  private let fileManager: FileManager

  public init(
    manifest: ToolManifest, manifestURL: URL, session: URLSession = .shared,
    fileManager: FileManager = .default
  ) {
    self.manifest = manifest
    self.manifestURL = manifestURL
    self.session = session
    self.fileManager = fileManager
  }

  public var image: ToolManifest.Image { manifest.image }

  public func cacheDirectory() -> URL {
    workspaceRoot()
      .appendingPathComponent(".toolsmith", isDirectory: true)
      .appendingPathComponent("cache", isDirectory: true)
      .appendingPathComponent(manifest.image.name, isDirectory: true)
      .appendingPathComponent(manifest.image.qcow2_sha256, isDirectory: true)
  }

  public func cachedImageURL() -> URL {
    cacheDirectory().appendingPathComponent(manifest.image.qcow2, isDirectory: false)
  }

  public func cachedImageIsValid() -> Bool {
    let url = cachedImageURL()
    guard fileManager.fileExists(atPath: url.path) else { return false }
    do {
      try manifest.verify(fileAt: url)
      return true
    } catch {
      return false
    }
  }

  public func sourceURL() throws -> URL {
    try resolveSourceURL(relativeTo: manifestURL.deletingLastPathComponent())
  }

  public func ensureImageAvailable() async throws -> URL {
    let cacheDirectory = cacheDirectory()
    try fileManager.createDirectory(
      at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
    let cachedImageURL = cachedImageURL()

    if fileManager.fileExists(atPath: cachedImageURL.path) {
      do {
        try manifest.verify(fileAt: cachedImageURL)
        return cachedImageURL
      } catch {
        try? fileManager.removeItem(at: cachedImageURL)
      }
    }

    let sourceURL = try self.sourceURL()
    if sourceURL.isFileURL {
      try copyLocalImage(from: sourceURL, to: cachedImageURL)
    } else {
      try await downloadRemoteImage(from: sourceURL, to: cachedImageURL)
    }

    try manifest.verify(fileAt: cachedImageURL)
    return cachedImageURL
  }

  private func resolveSourceURL(relativeTo base: URL) throws -> URL {
    let path = manifest.image.qcow2
    if let absoluteURL = URL(string: path), let scheme = absoluteURL.scheme, !scheme.isEmpty {
      return absoluteURL
    }
    if path.hasPrefix("/") {
      return URL(fileURLWithPath: path)
    }
    return base.appendingPathComponent(path)
  }

  private func copyLocalImage(from source: URL, to destination: URL) throws {
    if fileManager.fileExists(atPath: destination.path) {
      try fileManager.removeItem(at: destination)
    }
    if fileManager.fileExists(atPath: source.path) {
      try fileManager.copyItem(at: source, to: destination)
    } else {
      throw NSError(
        domain: "ImageHydrator", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Source image missing: \(source.path)"])
    }
  }

  private func workspaceRoot() -> URL {
    let manifestDirectory = manifestURL.deletingLastPathComponent()
    if manifestDirectory.lastPathComponent == ".toolsmith" {
      return manifestDirectory.deletingLastPathComponent()
    }
    return manifestDirectory
  }

  private func downloadRemoteImage(from source: URL, to destination: URL) async throws {
    let (tempURL, _) = try await session.download(from: source)
    if fileManager.fileExists(atPath: destination.path) {
      try fileManager.removeItem(at: destination)
    }
    try fileManager.moveItem(at: tempURL, to: destination)
  }
}
