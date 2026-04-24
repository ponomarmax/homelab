import Foundation

protocol CollectorTransporting {
    func prepareSessionBoundary(
        session: CollectionSession,
        streamTypes: [CollectorStream]
    ) -> PreparedSessionBoundary

    func prepareChunkBoundary(
        session: CollectionSession,
        stream: CollectorStream,
        sequenceNumber: Int,
        sampleCount: Int
    ) -> PreparedChunkBoundary
}
