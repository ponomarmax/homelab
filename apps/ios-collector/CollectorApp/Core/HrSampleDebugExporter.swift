import Foundation

final class HrSampleDebugExporter {
    private struct SampleLine: Codable {
        let session_id: String
        let stream: String
        let sample_seq: Int
        let hr_bpm: Int?
        let collector_received_at_utc: String
        let payload: CollectorSamplePayload
    }

    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let timestampFormatter = ISO8601DateFormatter()

    private var fileHandle: FileHandle?
    private(set) var currentFileURL: URL?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    deinit {
        stopSession()
    }

    @discardableResult
    func startSession(sessionID: UUID) -> URL? {
        stopSession()

        let fileURL = documentsDirectoryURL()
            .appendingPathComponent("hr-samples-\(sessionID.uuidString).jsonl")

        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: nil)
        }

        do {
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            fileHandle = handle
            currentFileURL = fileURL
            return fileURL
        } catch {
            fileHandle = nil
            currentFileURL = nil
            print("Failed to open HR sample export file: \(error)")
            return nil
        }
    }

    func appendSample(
        sessionID: UUID,
        sample: HeartRateSample
    ) {
        guard let fileHandle else { return }

        let line = SampleLine(
            session_id: sessionID.uuidString,
            stream: sample.stream.transportType,
            sample_seq: sample.sampleSequenceNumber,
            hr_bpm: sample.stream == .heartRate ? sample.hrBPM : nil,
            collector_received_at_utc: timestampFormatter.string(from: sample.collectorReceivedAtUTC),
            payload: sample.payload
        )

        do {
            let data = try encoder.encode(line)
            try fileHandle.write(contentsOf: data)
            try fileHandle.write(contentsOf: Data([0x0A]))
        } catch {
            print("Failed to append HR sample to debug export: \(error)")
        }
    }

    func stopSession() {
        do {
            try fileHandle?.close()
        } catch {
            print("Failed to close HR sample export file: \(error)")
        }

        fileHandle = nil
    }

    private func documentsDirectoryURL() -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}
