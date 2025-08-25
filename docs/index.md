# FountainToolsmith Documentation

Welcome to the documentation for **FountainToolsmith**, a reusable
Swift library for orchestrating external tools in a controlled
environment. This document provides an overview of the package,
installation instructions, module descriptions, quick start examples,
and guidance for development and testing.

## Overview

FountainToolsmith grew out of the FountainAI project as a way to
separate the tool execution subsystem into its own package. It offers:

* A high‑level API (`Toolsmith`) for managing tool runs with consistent logging and tracing semantics.
* Pluggable runners (e.g. `BwrapRunner` and `QemuRunner`) that execute commands in
  isolated sandboxes using bubblewrap or QEMU.
* A generated HTTP client (`ToolsmithAPI`) for interacting with a Tools Factory service that hosts tools remotely.
* A command‑line interface (`toolsmith-cli`) for testing and development.

By factoring these components into their own SPM package, the
FountainAI ecosystem can reuse them across multiple services or share
them with other projects needing similar capabilities.

## Installation

Add FountainToolsmith to your project’s dependencies in `Package.swift`:

```swift
.package(url: "https://github.com/Fountain-Coach/toolsmith-package.git", from: "1.0.0"),
```

Then import the modules you need:

```swift
import Toolsmith
import SandboxRunner
import ToolsmithAPI  // if using the HTTP client
```

The package targets macOS 14 or later and requires Swift 6.

## Modules and APIs

### Toolsmith

The `Toolsmith` type is the primary entry point when executing tools
locally. It manages request IDs, aggregates metadata and logs
execution spans. The `run(tool:metadata:requestID:operation:)` method
wraps your work closure and emits a `LogEntry` when finished.
If OpenTelemetry (OTEL) environment variables are configured, a trace
span will be exported automatically.

### SandboxRunner

`SandboxRunner` and its implementations, such as `BwrapRunner` and
`QemuRunner`, provide the actual mechanics of launching processes in
isolated contexts. Runners support configuring a working directory,
passing arguments, restricting network access, timeouts and resource
limits.

### ToolsmithSupport

This internal target contains shared types used by the other modules,
such as `JSONLogger`, `LogEntry`, `Span` and cryptographic helpers.

### ToolsmithAPI

`ToolsmithAPI` is a client library generated from the shared
`tools-factory.yml` specification. It exposes functions for
discovering available tools, registering new tool endpoints and
triggering conversions on a remote Tools Factory server.

### toolsmith-cli

The CLI executable provides convenient wrappers around
`ToolsmithAPI`. Once built, you can set `TOOLSERVER_URL` to the base
URL of your Tools Factory and invoke commands such as:

```bash
toolsmith-cli health-check
toolsmith-cli manifest
toolsmith-cli convert-image input.png output.jpg
toolsmith-cli transcode-audio input.wav output.mp3
toolsmith-cli convert-plist input.plist output.xml
toolsmith-cli pdf-scan [pdf2...]
toolsmith-cli pdf-query  [pageRange]
toolsmith-cli pdf-index-validate 
toolsmith-cli pdf-export-matrix 
```

## Quick Start Example

Here is a more complete example of executing a tool with custom
metadata and capturing errors:

```swift
import Toolsmith
import SandboxRunner
import Foundation

let toolsmith = Toolsmith()
let runner = BwrapRunner()
let work = URL(fileURLWithPath: "/tmp/myjob")

do {
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: work) }
    let requestID = toolsmith.run(tool: "ffmpeg", metadata: ["user":"alice"]) {
        let result = try runner.run(
            executable: "/usr/local/bin/ffmpeg",
            arguments: ["-i", "input.mov", "-codec:a", "libmp3lame", "output.mp3"],
            inputs: [work.appendingPathComponent("input.mov")],
            workDirectory: work,
            allowNetwork: false,
            timeout: 120,
            limits: nil
        )
        print("stdout:", result.stdout)
        print("stderr:", result.stderr)
    }
    print("completed request: \(requestID)")
} catch {
    print("failed:", error)
}
```

Use metadata to correlate runs across systems and logs.

## Tools Factory and Client Generation

FountainToolsmith optionally integrates with a Tools Factory service.
The service exposes an HTTP API described in the original FountainAI
repository. To regenerate the `ToolsmithAPI` client after updating
that spec, run the appropriate script.

## Development and Testing

* Run unit tests with `swift test`.
* Verify the CLI end‑to‑end by executing the smoke test script
  from the original repository.
* When modifying sandbox profiles, review the security implications
  carefully; bubblewrap rules determine the isolation level.
* Contributions should follow the same coding conventions as the
  FountainAI project.

## Contributing

Contributions are welcome! Whether you’re fixing a bug, adding a
feature or improving the documentation, please open an issue first to
discuss your proposal.

## License

The contents of this package are subject to the same copyright and
license terms as the original FountainAI project. Unless otherwise
noted, all code is © 2025 Contexter alias Benedikt Eickhoff 🛡️ All
rights reserved.
