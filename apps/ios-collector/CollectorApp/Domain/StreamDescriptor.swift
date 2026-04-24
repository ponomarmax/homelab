import Foundation

struct StreamDescriptor: Equatable, Codable, Sendable {
    let streamName: String
    let streamType: String
    let unit: String
    let source: String
    let sampleKind: String
}
