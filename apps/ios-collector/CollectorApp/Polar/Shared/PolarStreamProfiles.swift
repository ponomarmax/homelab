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
}
