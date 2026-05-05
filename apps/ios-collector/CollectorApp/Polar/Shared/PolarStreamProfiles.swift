import Foundation

enum PolarStreamProfile {
    static let hrLive = StreamMetadataProfile(
        schemaVersion: "1.0",
        streamType: "hr",
        streamIDPrefix: "hr",
        source: StreamMetadataProfile.Source(
            vendor: "polar",
            deviceModel: "h10",
            deviceID: nil
        ),
        collection: StreamMetadataProfile.Collection(mode: "online_live"),
        deviceTimeReference: "collector:collectorObserved",
        transport: StreamMetadataProfile.Transport(
            encoding: "json",
            compression: "none",
            payloadSchema: "polar.hr",
            payloadVersion: "1.0"
        )
    )

    static let ecgLive = StreamMetadataProfile(
        schemaVersion: "1.0",
        streamType: "ecg",
        streamIDPrefix: "ecg",
        source: StreamMetadataProfile.Source(
            vendor: "polar",
            deviceModel: "h10",
            deviceID: nil
        ),
        collection: StreamMetadataProfile.Collection(mode: "online_live"),
        deviceTimeReference: "polar",
        transport: StreamMetadataProfile.Transport(
            encoding: "json",
            compression: "none",
            payloadSchema: "polar.ecg",
            payloadVersion: "1.0"
        )
    )

    static let accLive = StreamMetadataProfile(
        schemaVersion: "1.0",
        streamType: "acc",
        streamIDPrefix: "acc",
        source: StreamMetadataProfile.Source(
            vendor: "polar",
            deviceModel: "h10",
            deviceID: nil
        ),
        collection: StreamMetadataProfile.Collection(mode: "online_live"),
        deviceTimeReference: "polar",
        transport: StreamMetadataProfile.Transport(
            encoding: "json",
            compression: "none",
            payloadSchema: "polar.acc",
            payloadVersion: "1.0"
        )
    )

    static let batteryLive = StreamMetadataProfile(
        schemaVersion: "1.0",
        streamType: "battery",
        streamIDPrefix: "battery",
        source: StreamMetadataProfile.Source(
            vendor: "polar",
            deviceModel: "h10",
            deviceID: nil
        ),
        collection: StreamMetadataProfile.Collection(mode: "online_live"),
        deviceTimeReference: "collector:collectorObserved",
        transport: StreamMetadataProfile.Transport(
            encoding: "json",
            compression: "none",
            payloadSchema: "polar.device_battery",
            payloadVersion: "1.0"
        )
    )

    static let hrOffline = StreamMetadataProfile(
        schemaVersion: "1.0",
        streamType: "hr",
        streamIDPrefix: "offline-hr",
        source: .init(vendor: "polar", deviceModel: "verity_sense", deviceID: nil),
        collection: .init(mode: "offline_recording"),
        deviceTimeReference: "polar",
        transport: .init(encoding: "json", compression: "none", payloadSchema: "polar.offline.hr", payloadVersion: "1.0")
    )

    static let ppiOffline = StreamMetadataProfile(
        schemaVersion: "1.0",
        streamType: "ppi",
        streamIDPrefix: "offline-ppi",
        source: .init(vendor: "polar", deviceModel: "verity_sense", deviceID: nil),
        collection: .init(mode: "offline_recording"),
        deviceTimeReference: "polar",
        transport: .init(encoding: "json", compression: "none", payloadSchema: "polar.offline.ppi", payloadVersion: "1.0")
    )

    static let accOffline = StreamMetadataProfile(
        schemaVersion: "1.0",
        streamType: "acc",
        streamIDPrefix: "offline-acc",
        source: .init(vendor: "polar", deviceModel: "verity_sense", deviceID: nil),
        collection: .init(mode: "offline_recording"),
        deviceTimeReference: "polar",
        transport: .init(encoding: "json", compression: "none", payloadSchema: "polar.offline.acc", payloadVersion: "1.0")
    )

    static let ppgOffline = StreamMetadataProfile(
        schemaVersion: "1.0",
        streamType: "ppg",
        streamIDPrefix: "offline-ppg",
        source: .init(vendor: "polar", deviceModel: "verity_sense", deviceID: nil),
        collection: .init(mode: "offline_recording"),
        deviceTimeReference: "polar",
        transport: .init(encoding: "json", compression: "none", payloadSchema: "polar.offline.ppg", payloadVersion: "1.0")
    )

    static let magOffline = StreamMetadataProfile(
        schemaVersion: "1.0",
        streamType: "mag",
        streamIDPrefix: "offline-mag",
        source: .init(vendor: "polar", deviceModel: "verity_sense", deviceID: nil),
        collection: .init(mode: "offline_recording"),
        deviceTimeReference: "polar",
        transport: .init(encoding: "json", compression: "none", payloadSchema: "polar.offline.mag", payloadVersion: "1.0")
    )

    static let gyrOffline = StreamMetadataProfile(
        schemaVersion: "1.0",
        streamType: "gyro",
        streamIDPrefix: "offline-gyro",
        source: .init(vendor: "polar", deviceModel: "verity_sense", deviceID: nil),
        collection: .init(mode: "offline_recording"),
        deviceTimeReference: "polar",
        transport: .init(encoding: "json", compression: "none", payloadSchema: "polar.offline.gyro", payloadVersion: "1.0")
    )
}
