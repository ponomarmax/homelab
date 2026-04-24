import Foundation

struct MockCollectorTransport: CollectorTransporting {
    func prepareSessionBoundary(
        session: CollectionSession,
        streamTypes: [CollectorStream]
    ) -> PreparedSessionBoundary {
        PreparedSessionBoundary(
            sessionID: session.id,
            collectionModeTransportValue: session.metadata.mode.transportValue,
            startedAt: session.metadata.startedAt,
            streamTypes: streamTypes
        )
    }

    func prepareChunkBoundary(
        session: CollectionSession,
        stream: CollectorStream,
        sequenceNumber: Int,
        sampleCount: Int
    ) -> PreparedChunkBoundary {
        PreparedChunkBoundary(
            sessionID: session.id,
            stream: stream,
            sequenceNumber: sequenceNumber,
            sampleCount: sampleCount,
            preparedAt: Date()
        )
    }
}
