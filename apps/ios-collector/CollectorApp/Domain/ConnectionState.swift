import Foundation

enum ConnectionState: Equatable, Sendable {
    case disconnected
    case deviceSelected
    case connecting
    case connected
}
