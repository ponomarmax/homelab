import Foundation

protocol CollectorStreamProviding: AnyObject {
    var streamType: CollectorStream { get }

    func start(onSample: @escaping @Sendable (CollectorSample) -> Void)
    func stop()
}

typealias HeartRateStreamProviding = CollectorStreamProviding
