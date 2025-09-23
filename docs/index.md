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

## VM execution model

Toolsmith defaults to a VM-first posture. When the manifest exposes a
virtual machine image, the runtime hydrates that artifact into
`.toolsmith/cache/<image>/<version>` and validates the advertised
SHA-256 digest before any command is dispatched. Cached images are
reused until their digest diverges from the manifest, at which point the
hydrator re-downloads the artifact.

### Hydration lifecycle

1. `Toolsmith.run` evaluates the manifest and resolves the execution
   mode (automatic, host, or vm).
2. If VM mode is selected, `ImageHydrator.ensureImageAvailable()`
   downloads or reuses the cached image and verifies its digest.
3. Successful verification triggers `VirtualMachine.start()` which boots
   the VM and establishes a command channel endpoint.

Lifecycle progress is emitted through `JSONLogger.lifecycle*` calls. For
example:

```json
{"stage":"download_start","execution_mode":"vm","metadata":{"image_name":"ubuntu-22","cache_path":"/workspace/.toolsmith/cache/ubuntu-22/1.2.3"}}
{"stage":"checksum_verified","execution_mode":"vm","metadata":{"digest":"abc123","image_path":"/workspace/.toolsmith/cache/ubuntu-22/1.2.3/ubuntu-22.qcow2"}}
{"stage":"vm_boot","execution_mode":"vm","metadata":{"backend":"vm","host":"127.0.0.1","port":"9000"}}
```

If hydration fails (e.g. checksum mismatch or missing manifest), the
logger emits a `download_end` entry with `status:"failed"` and VM mode
falls back to host execution.

### Command channel usage

Once booted, `VirtualMachine.start()` returns a
`CommandChannelAdapter`. The adapter exposes `connect()`,
`runCommand(_:)`, and `requestShutdown()` APIs for interacting with the
guest. Each `runCommand` call produces a stream of status updates
(`started`, `stdout`, `stderr`, `finished`) to mirror the guest process
lifecycle. The command channel is also where health probes or adapter
extensions can be injected.

### Optional write-through exports

By default the VM sees the workspace mounted read-only. When a tool must
export artifacts, provide writable mounts by passing `writableExports`
into `VirtualMachine.start()`. Adapters under `Sources/Toolsmith/Adapters`
contain helpers for defining the mount points and propagating them to
`QemuRunner`.

### Verification and troubleshooting

* **Confirm VM mode** — Inspect lifecycle log entries for
  `metadata.backend == "vm"` and observe the `execution_mode` field in
  both lifecycle and final `LogEntry` metadata. When available, the
  `cache_path` metadata should resolve to `.toolsmith/cache/...`.
* **Command-channel probe** — Issue a lightweight invocation such as
  `CommandChannelAdapter.CommandInvocation(executable: "/bin/true")` and
  ensure `StatusUpdate.started` and `StatusUpdate.finished(0)` arrive.
  Failure to receive updates typically indicates a stale connection.
* **Digest mismatch** — Look for `download_end` entries with
  `status:"failed"` and an accompanying `error` describing the mismatch.
  Clearing the cache directory forces a fresh hydration.
* **Adapter cross-reference** — When extending integrations, consult the
  APIs documented in `Sources/Toolsmith/Adapters/CommandChannelAdapter.swift`
  and `Sources/Toolsmith/Virtualization/VirtualMachine.swift` to align
  guest-side changes with host orchestration.

If issues persist, enable host execution via `TOOLSMITH_EXECUTION=host`
to isolate whether failures are VM-specific before filing a bug.

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
