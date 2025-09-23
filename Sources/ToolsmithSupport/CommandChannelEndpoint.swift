import Foundation

public struct CommandChannelEndpoint: Sendable, Equatable {
  public enum Transport: Sendable, Equatable {
    case tcp(host: String, port: UInt16)
    case unixDomainSocket(path: String)
  }

  public let transport: Transport

  public init(transport: Transport) {
    self.transport = transport
  }
}
