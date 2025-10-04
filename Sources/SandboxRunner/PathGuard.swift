import Foundation

/// Ensures arguments do not reference paths outside the provided work directory.
/// Paths beginning with `-` are treated as flags and ignored.
func guardWritePaths(arguments: [String], workDirectory: URL) throws {
  let base = workDirectory.standardizedFileURL.path
  for arg in arguments {
    guard !arg.hasPrefix("-") else { continue }
    if arg.hasPrefix("/inputs/") || arg.hasPrefix("/scratch/") {
      continue
    }
    if arg.hasPrefix("/") || arg.contains("..") {
      let resolved = URL(fileURLWithPath: arg, relativeTo: workDirectory).standardizedFileURL.path
      if !resolved.hasPrefix(base) {
        throw NSError(
          domain: "SandboxRunner", code: 2,
          userInfo: [NSLocalizedDescriptionKey: "Write outside /work is not allowed"])
      }
    }
  }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
