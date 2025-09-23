import Foundation
import ToolsmithSupport

public protocol CommandChannel: AnyObject, Sendable {
  var endpoint: CommandChannelEndpoint { get }
  func connect() async throws
  func runCommand(
    _ invocation: CommandChannelAdapter.CommandInvocation
  ) -> AsyncThrowingStream<CommandChannelAdapter.StatusUpdate, Error>
  func requestShutdown() async throws
}

public final class CommandChannelAdapter: @unchecked Sendable {
  public struct CommandInvocation: Sendable {
    public let identifier: String
    public let executable: String
    public let arguments: [String]
    public let environment: [String: String]

    public init(
      identifier: String = UUID().uuidString,
      executable: String,
      arguments: [String] = [],
      environment: [String: String] = [:]
    ) {
      self.identifier = identifier
      self.executable = executable
      self.arguments = arguments
      self.environment = environment
    }
  }

  public enum StatusUpdate: Sendable, Equatable {
    case started(Date)
    case stdout(String)
    case stderr(String)
    case finished(Int32)
  }

  public enum AdapterError: Error {
    case notConnected
  }

  public let endpoint: CommandChannelEndpoint
  private var connected: Bool

  public init(endpoint: CommandChannelEndpoint) {
    self.endpoint = endpoint
    self.connected = false
  }

  public func connect() async throws {
    connected = true
  }

  public func runCommand(
    _ invocation: CommandInvocation
  ) -> AsyncThrowingStream<StatusUpdate, Error> {
    AsyncThrowingStream { continuation in
      guard connected else {
        continuation.finish(throwing: AdapterError.notConnected)
        return
      }

      continuation.yield(.started(Date()))
      continuation.yield(.finished(0))
      continuation.finish()
    }
  }

  public func requestShutdown() async throws {
    guard connected else { return }
    connected = false
  }
}

extension CommandChannelAdapter: CommandChannel {}
