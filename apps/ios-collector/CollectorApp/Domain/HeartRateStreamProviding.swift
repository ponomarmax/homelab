import Foundation

protocol CollectorStreamProviding: AnyObject {
    var streamType: CollectorStream { get }

    func start(onSample: @escaping @Sendable (HeartRateSample) -> Void)
    func stop()
}

typealias HeartRateStreamProviding = CollectorStreamProviding
