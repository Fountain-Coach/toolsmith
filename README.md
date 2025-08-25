# FountainToolsmith

**FountainToolsmith** is a stand‑alone Swift Package Manager (SPM) library that
extracts the tool orchestration components from the original FountainAI project.
It provides a clean, reusable package for driving external command‑line tools in secure containers, exposing both library and command‑line interfaces.

## Use Cases

FountainToolsmith solves the problem of executing arbitrary tools in a
predictable and observable manner. Typical scenarios include:

* Integrating third‑party tools (e.g. media converters, format
  transformers) into an AI pipeline without exposing them to the
  network.
* Running untrusted executables in an isolated sandbox while capturing
  logs and tracing information.
* Delegating tool invocation to a separate service (the Tools Factory) and controlling it from Swift via generated client
  stubs.
* Building a custom command‑line interface on top of Toolsmith’s API.

## Installation

Add FountainToolsmith to your SPM dependencies in `Package.swift`:

```swift
.package(url: "https://github.com/Fountain-Coach/toolsmith-package.git", from: "1.0.0"),
```

Then import the modules you need:

```swift
import Toolsmith
import SandboxRunner
```

The package supports macOS 14 and later and depends only on `swift-crypto`.

## Quick Start

Here is a minimal example demonstrating how to run an `echo` command in a sandboxed environment and capture its output:

```swift
import Toolsmith
import SandboxRunner
import Foundation

let work = FileManager.default.temporaryDirectory.appendingPathComponent("work")
try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

let toolsmith = Toolsmith()
let runner = BwrapRunner()

defer { try? FileManager.default.removeItem(at: work) }

let requestID = toolsmith.run(tool: "echo") {
    let result = try runner.run(
        executable: "/bin/echo",
        arguments: ["hello"],
        inputs: [],
        workDirectory: work,
        allowNetwork: false,
        timeout: 5,
        limits: nil
    )
    print(result.stdout)
}

print("Ran tool with request ID", requestID)
```

See [docs/index.md](docs/index.md) for more examples.

## Package Modules

| Module             | Description                                                      |
|--------------------|------------------------------------------------------------------|
| **ToolsmithSupport** | Internal support types: logging, cryptographic helpers, metadata structures. |
| **Toolsmith**      | High‑level API for orchestrating tool runs with spans and logging. |
| **SandboxRunner**  | Concrete runners such as `BwrapRunner` and `QemuRunner` that execute commands in isolated sandboxes. |
| **ToolsmithAPI**   | Generated client for the Tools Factory HTTP service. |
| **toolsmith-cli**  | A command‑line interface that wraps `ToolsmithAPI` for user‑friendly interactions. |

## Documentation

Full documentation is available in the [docs directory](docs/index.md).

---
© 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.