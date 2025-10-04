import Foundation
import ToolsmithAPI
import ToolsmithSupport

@main
struct ToolsmithCLI {
  static func main() async throws {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let command = args.first else {
      printUsage()
      return
    }
    let baseURL = URL(
      string: ProcessInfo.processInfo.environment["TOOLSERVER_URL"] ?? "http://localhost:8080")!
    let client = APIClient(baseURL: baseURL)
    switch command {
    case "convert-image":
      guard args.count >= 3 else {
        print("Usage: toolsmith-cli convert-image <input> <output>")
        return
      }
      let input = args[1]
      let output = args[2]
      let ext = URL(fileURLWithPath: output).pathExtension
      let body = ToolRequest(args: [input, "\(ext):-"], request_id: UUID().uuidString)
      let out = try await client.send(runImageMagick(body: body))
      try Data(out).write(to: URL(fileURLWithPath: output))
      print("wrote \(output)")
    case "transcode-audio":
      guard args.count >= 3 else {
        print("Usage: toolsmith-cli transcode-audio <input> <output>")
        return
      }
      let input = args[1]
      let output = args[2]
      let ext = URL(fileURLWithPath: output).pathExtension
      let body = ToolRequest(
        args: ["-i", input, "-f", ext, "pipe:1"], request_id: UUID().uuidString)
      let out = try await client.send(runFFmpeg(body: body))
      try Data(out).write(to: URL(fileURLWithPath: output))
      print("wrote \(output)")
    case "convert-plist":
      guard args.count >= 3 else {
        print("Usage: toolsmith-cli convert-plist <input> <output>")
        return
      }
      let input = args[1]
      let output = args[2]
      let format = URL(fileURLWithPath: output).pathExtension == "xml" ? "xml1" : "binary1"
      let body = ToolRequest(
        args: ["-convert", format, "-o", "-", input], request_id: UUID().uuidString)
      let out = try await client.send(runLibPlist(body: body))
      try Data(out).write(to: URL(fileURLWithPath: output))
      print("wrote \(output)")
    case "pdf-scan":
      guard args.count >= 2 else {
        print("Usage: toolsmith-cli pdf-scan [pdf1 pdf2...]")
        return
      }
      let inputs = Array(args.dropFirst())
      let body = ScanRequest(includeText: true, inputs: inputs, sha256: false)
      let index = try await client.send(pdfScan(body: body))
      let data = try JSONEncoder().encode(index)
      if let text = String(data: data, encoding: .utf8) { print(text) }
    case "pdf-query":
      guard args.count >= 3 else {
        print("Usage: toolsmith-cli pdf-query <index.json> <query> [pageRange]")
        return
      }
      let indexURL = URL(fileURLWithPath: args[1])
      let indexData = try Data(contentsOf: indexURL)
      let index = try JSONDecoder().decode(Index.self, from: indexData)
      let q = args[2]
      let pageRange = args.count > 3 ? args[3] : ""
      let body = QueryRequest(index: index, pageRange: pageRange, q: q)
      let result = try await client.send(pdfQuery(body: body))
      let data = try JSONEncoder().encode(result)
      if let text = String(data: data, encoding: .utf8) { print(text) }
    case "pdf-index-validate":
      guard args.count >= 2 else {
        print("Usage: toolsmith-cli pdf-index-validate <index.json>")
        return
      }
      let indexURL = URL(fileURLWithPath: args[1])
      let indexData = try Data(contentsOf: indexURL)
      let index = try JSONDecoder().decode(Index.self, from: indexData)
      let result = try await client.send(pdfIndexValidate(body: index))
      let data = try JSONEncoder().encode(result)
      if let text = String(data: data, encoding: .utf8) { print(text) }
    case "pdf-export-matrix":
      guard args.count >= 2 else {
        print("Usage: toolsmith-cli pdf-export-matrix <index.json>")
        return
      }
      let indexURL = URL(fileURLWithPath: args[1])
      let indexData = try Data(contentsOf: indexURL)
      let index = try JSONDecoder().decode(Index.self, from: indexData)
      let body = ExportMatrixRequest(bitfields: false, enums: false, index: index, ranges: false)
      let matrix = try await client.send(pdfExportMatrix(body: body))
      let data = try JSONEncoder().encode(matrix)
      if let text = String(data: data, encoding: .utf8) { print(text) }
    default:
      printUsage()
    }
  }

  static func printUsage() {
    print(
      """
      Usage: toolsmith-cli [args]
      Commands:
        convert-image <input> <output>
        transcode-audio <input> <output>
        convert-plist <input> <output>
        pdf-scan [pdf1 pdf2...]
        pdf-query <index.json> <query> [pageRange]
        pdf-index-validate <index.json>
        pdf-export-matrix <index.json>
      """)
  }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
