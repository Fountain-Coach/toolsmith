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

    // Resolve source and support OCI (GHCR) references via `oras`.
    let sourceURL = try self.sourceURL()
    if let scheme = sourceURL.scheme, scheme.lowercased() == "oci" || scheme.lowercased() == "ghcr" {
      try downloadOCIArtifact(ref: sourceURL.absoluteString, to: cachedImageURL)
    } else if sourceURL.isFileURL {
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

  // MARK: - OCI (GHCR) support using `oras`

  private func downloadOCIArtifact(ref: String, to destination: URL) throws {
    // Use `oras` CLI to pull the artifact to a temp directory, then locate a .qcow2 payload.
    // Env vars:
    // - TOOLSMITH_ORAS: path to the oras binary (default: "oras")
    // - GHCR_USERNAME / GHCR_TOKEN or GITHUB_TOKEN for authenticated pulls of private artifacts
    let oras = ProcessInfo.processInfo.environment["TOOLSMITH_ORAS"] ?? "oras"
    let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    try fileManager.createDirectory(at: tmpDir, withIntermediateDirectories: true)

    // Build arguments. Prefer `-o <dir>` if supported; otherwise invoke in CWD.
    // We'll invoke in CWD=tmpDir to be broadly compatible.
    // Try authenticated login first if creds are provided, then pull.
    let env = ProcessInfo.processInfo.environment
    if let token = env["GHCR_TOKEN"], let user = env["GHCR_USERNAME"] ?? env["GITHUB_ACTOR"] {
      _ = try runCommand(executable: oras, arguments: ["login", "ghcr.io", "-u", user, "-p", token], currentDirectory: tmpDir)
    }

    // Pull into tmpDir (CWD controls output location across ORAS versions).
    let result = try runCommand(executable: oras, arguments: ["pull", ref], currentDirectory: tmpDir)
    if result.exitCode != 0 {
      throw NSError(
        domain: "ImageHydrator", code: Int(result.exitCode),
        userInfo: [NSLocalizedDescriptionKey: "oras pull failed: \(result.stderr)"])
    }

    // Find the qcow2 file (first match if multiple).
    let contents = try fileManager.subpathsOfDirectory(atPath: tmpDir.path)
    guard let qcowRel = contents.first(where: { $0.lowercased().hasSuffix(".qcow2") }) else {
      throw NSError(
        domain: "ImageHydrator", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "No .qcow2 payload found in OCI artifact \(ref)"])
    }
    let pulled = tmpDir.appendingPathComponent(qcowRel)
    if fileManager.fileExists(atPath: destination.path) {
      try fileManager.removeItem(at: destination)
    }
    try fileManager.moveItem(at: pulled, to: destination)
    // Cleanup tmp dir best-effort
    try? fileManager.removeItem(at: tmpDir)
  }

  private struct CommandResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
  }

  private func runCommand(
    executable: String,
    arguments: [String],
    currentDirectory: URL
  ) throws -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [executable] + arguments
    process.currentDirectoryURL = currentDirectory
    let stdout = Pipe(); let stderr = Pipe()
    process.standardOutput = stdout; process.standardError = stderr
    try process.run(); process.waitUntilExit()
    let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return CommandResult(stdout: out, stderr: err, exitCode: process.terminationStatus)
  }
}
