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

## VM-first execution model

Toolsmith prefers to execute tools inside a managed virtual machine (VM)
whenever a compatible image is available in the manifest. On the first
run the image is hydrated into `.toolsmith/cache/<image>/<version>` and
its SHA-256 digest is checked before the VM is booted. Subsequent runs
reuse the cached image as long as the digest still matches the manifest.

The VM exposes a command channel back to the host process for dispatching
tool invocations, streaming status updates, and delivering shutdown
signals. By default the workspace is mounted read-only; if a tool needs
to export artifacts you can opt into writable mounts via the adapters in
`Sources/Toolsmith/Adapters/`.

### Overriding execution placement

You can switch between host and VM execution without code changes by
setting the `TOOLSMITH_EXECUTION` environment variable:

```bash
export TOOLSMITH_EXECUTION=host   # force host execution
export TOOLSMITH_EXECUTION=vm     # force VM execution
```

Individual `Toolsmith.run` calls accept an `execution:` parameter so you
can override placement per invocation:

```swift
try toolsmith.run(tool: "ffmpeg", execution: .host) { context in
    // Runs on the host even if VM mode is enabled globally
}
```

This override is useful when mixing trusted helper binaries with
untrusted workloads in the same process.

## Package Modules

| Module             | Description                                                      |
|--------------------|------------------------------------------------------------------|
| **ToolsmithSupport** | Internal support types: logging, cryptographic helpers, metadata structures. |
| **Toolsmith**      | High‑level API for orchestrating tool runs with spans and logging. |
| **SandboxRunner**  | Concrete runners such as `BwrapRunner` and `QemuRunner` that execute commands in isolated sandboxes. |
| **ToolsmithAPI**   | Generated client for the Tools Factory HTTP service. |
| **toolsmith-cli**  | A command‑line interface that wraps `ToolsmithAPI` for user‑friendly interactions. |

## Documentation

Full documentation is available in the [docs directory](docs/index.md). For
details on publishing versioned VM images alongside source releases, see the
[release process guide](docs/release-process.md).

---
© 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.