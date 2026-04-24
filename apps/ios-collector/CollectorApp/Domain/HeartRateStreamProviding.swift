import Foundation

protocol HeartRateStreamProviding: AnyObject {
    var streamType: CollectorStream { get }

    func start(onSample: @escaping @Sendable (HeartRateSample) -> Void)
    func stop()
}
