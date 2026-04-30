import Foundation

enum PolarStreamProfile {
    static let hrLive = StreamMetadataProfile(
        schemaVersion: "1.0",
        streamType: "hr",
        streamIDPrefix: "hr",
        source: StreamMetadataProfile.Source(
            vendor: "polar",
            deviceModel: "Polar H10",
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
            deviceModel: "Polar H10",
            deviceID: nil
        ),
        collection: StreamMetadataProfile.Collection(mode: "online_live"),
        deviceTimeReference: "polar:ns_since_2000_epoch",
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
            deviceModel: "Polar H10",
            deviceID: nil
        ),
        collection: StreamMetadataProfile.Collection(mode: "online_live"),
        deviceTimeReference: "polar:ns_since_2000_epoch",
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
            deviceModel: "Polar H10",
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
        source: .init(vendor: "polar", deviceModel: "Polar Verity Sense", deviceID: nil),
        collection: .init(mode: "offline_recording"),
        deviceTimeReference: "collector:collectorObserved",
        transport: .init(encoding: "json", compression: "none", payloadSchema: "polar.offline.hr", payloadVersion: "v1-draft")
    )

    static let ppiOffline = StreamMetadataProfile(
        schemaVersion: "1.0",
        streamType: "ppi",
        streamIDPrefix: "offline-ppi",
        source: .init(vendor: "polar", deviceModel: "Polar Verity Sense", deviceID: nil),
        collection: .init(mode: "offline_recording"),
        deviceTimeReference: "polar:offline_recording",
        transport: .init(encoding: "json", compression: "none", payloadSchema: "polar.offline.ppi", payloadVersion: "v1-draft")
    )

    static let accOffline = StreamMetadataProfile(
        schemaVersion: "1.0",
        streamType: "acc",
        streamIDPrefix: "offline-acc",
        source: .init(vendor: "polar", deviceModel: "Polar Verity Sense", deviceID: nil),
        collection: .init(mode: "offline_recording"),
        deviceTimeReference: "polar:ns_since_2000_epoch",
        transport: .init(encoding: "json", compression: "none", payloadSchema: "polar.offline.acc", payloadVersion: "v1-draft")
    )

    static let ppgOffline = StreamMetadataProfile(
        schemaVersion: "1.0",
        streamType: "ppg",
        streamIDPrefix: "offline-ppg",
        source: .init(vendor: "polar", deviceModel: "Polar Verity Sense", deviceID: nil),
        collection: .init(mode: "offline_recording"),
        deviceTimeReference: "polar:ns_since_2000_epoch",
        transport: .init(encoding: "json", compression: "none", payloadSchema: "polar.offline.ppg", payloadVersion: "v1-draft")
    )

    static let magOffline = StreamMetadataProfile(
        schemaVersion: "1.0",
        streamType: "mag",
        streamIDPrefix: "offline-mag",
        source: .init(vendor: "polar", deviceModel: "Polar Verity Sense", deviceID: nil),
        collection: .init(mode: "offline_recording"),
        deviceTimeReference: "polar:ns_since_2000_epoch",
        transport: .init(encoding: "json", compression: "none", payloadSchema: "polar.offline.mag", payloadVersion: "v1-draft")
    )

    static let gyrOffline = StreamMetadataProfile(
        schemaVersion: "1.0",
        streamType: "gyro",
        streamIDPrefix: "offline-gyro",
        source: .init(vendor: "polar", deviceModel: "Polar Verity Sense", deviceID: nil),
        collection: .init(mode: "offline_recording"),
        deviceTimeReference: "polar:ns_since_2000_epoch",
        transport: .init(encoding: "json", compression: "none", payloadSchema: "polar.offline.gyr", payloadVersion: "v1-draft")
    )
}
