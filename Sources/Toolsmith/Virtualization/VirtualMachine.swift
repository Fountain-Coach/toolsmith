import Foundation
import SandboxRunner
import ToolsmithSupport

public actor VirtualMachine {
  public struct CommandResult: Sendable {
    public let updates: [CommandChannelAdapter.StatusUpdate]

    public init(updates: [CommandChannelAdapter.StatusUpdate]) {
      self.updates = updates
    }
  }

  private enum State {
    case stopped
    case running(instance: QemuRunner.Instance, channel: CommandChannelAdapter)
  }

  private let runner: QemuRunner
  private let workspace: URL
  private var state: State = .stopped

  public init(imageURL: URL, manifest: ToolManifest?, workspace: URL) {
    self.runner = QemuRunner(image: imageURL, manifest: manifest)
    self.workspace = workspace
  }

  @discardableResult
  public func start(writableExports: [QemuRunner.ExportMount] = []) async throws
    -> CommandChannelAdapter
  {
    switch state {
    case .running(_, let channel):
      return channel
    case .stopped:
      let instance = try runner.launchVirtualMachine(
        workspace: workspace, writableExports: writableExports)
      let adapter = CommandChannelAdapter(endpoint: instance.endpoint)
      try await adapter.connect()
      state = .running(instance: instance, channel: adapter)
      return adapter
    }
  }

  public func runCommand(
    _ invocation: CommandChannelAdapter.CommandInvocation
  ) async throws -> CommandResult {
    guard case .running(_, let channel) = state else {
      throw VirtualMachineError.notStarted
    }
    var collected: [CommandChannelAdapter.StatusUpdate] = []
    for try await update in channel.runCommand(invocation) {
      collected.append(update)
    }
    return CommandResult(updates: collected)
  }

  public func shutdown() async {
    guard case .running(let instance, let channel) = state else { return }
    try? await channel.requestShutdown()
    instance.shutdown()
    state = .stopped
  }
}

public enum VirtualMachineError: Error {
  case notStarted
}
