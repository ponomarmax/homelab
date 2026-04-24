import Foundation

struct CollectorDevice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let vendor: String
    let model: String
}
