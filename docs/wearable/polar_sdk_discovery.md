# Polar SDK Discovery Checkpoint (H10 + Verity Sense)

Status: documentation/research spike only. No production integration in this checkpoint.

Scope:
- map official Polar BLE SDK capabilities to current HomeLab wearable architecture
- define what to validate in the official iOS example app
- document data/timing implications for raw ingestion and later normalization

Out of scope:
- no runtime collector code changes
- no ingestion API behavior changes
- no new always-on service

## Official Sources Used

- Polar BLE SDK repository: <https://github.com/polarofficial/polar-ble-sdk>
- SDK README (iOS requirements, setup, examples): <https://github.com/polarofficial/polar-ble-sdk/blob/master/README.md>
- iOS example app path: <https://github.com/polarofficial/polar-ble-sdk/tree/master/examples/example-ios/polar-sensor-data-collector>
- Example iOS source (current SwiftUI app and manager):
  - <https://github.com/polarofficial/polar-ble-sdk/blob/master/examples/example-ios/polar-sensor-data-collector/PSDC/PSDCApp.swift>
  - <https://github.com/polarofficial/polar-ble-sdk/blob/master/examples/example-ios/polar-sensor-data-collector/PSDC/Views/ContentView.swift>
  - <https://github.com/polarofficial/polar-ble-sdk/blob/master/examples/example-ios/polar-sensor-data-collector/PSDC/PolarBleSdkManager.swift>
- Firmware update notes: <https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/FirmwareUpdate.md>
- First-time-use notes: <https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/FirstTimeUse.md>
- Known issues: <https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/KnownIssues.md>
- Migration 5.0.0: <https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/MigrationGuide5.0.0.md>
- PPI notes: <https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/PPIData.md>
- SDK mode: <https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/SdkModeExplained.md>
- SDK offline recording: <https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/SdkOfflineRecordingExplained.md>
- Sync guideline: <https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/SyncImplementationGuideline.md>
- Time system: <https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/TimeSystemExplained.md>
- H10 product page: <https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/products/PolarH10.md>
- Verity Sense product page: <https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/products/PolarVeritySense.md>
- Technical docs:
  - `technical_documentation/H10_ECG_Explained.docx`
  - `technical_documentation/online_measurement.pdf`
  - `technical_documentation/offline_measurement.pdf`

## 1) Official Example: How To Run

### Requirements

From official SDK docs and example project files:
- Xcode: `13.2+` (README minimum)
- iOS target: README says `iOS 14+`; current example `podfile` sets platform `iOS 15.0`
- Dependencies used by the example project:
  - CocoaPods (`podfile` exists in `examples/example-ios/polar-sensor-data-collector`)
  - Pod versions in sample: `PolarBleSdk 7.1.0`, `RxSwift`, `Zip`
- App capabilities and plist permissions are required:
  - Background mode: Bluetooth central
  - `NSBluetoothAlwaysUsageDescription`

Practical recommendation for local run now: use Xcode with an iOS 15+ device/simulator profile and CocoaPods flow.

### Minimal commands

```bash
# from a parent folder of the SDK repo

git clone https://github.com/polarofficial/polar-ble-sdk.git
cd polar-ble-sdk/examples/example-ios/polar-sensor-data-collector
pod install
open PSDC.xcworkspace
```

In Xcode:
1. Select `PSDC` scheme.
2. Use a real iPhone for BLE testing (required for real sensor integration tests).
3. Build and run.

### What screens/features the current example exposes

From `ContentView.swift` + views directory:
- Device search/connect/disconnect and switching between connected devices
- Online streaming tab
- Offline recording tab
- H10 Exercise tab (shown when connected device name contains `H10`)
- Device settings tab (time, disk space, firmware update, SDK mode toggle, restart, factory reset, physical data)
- Sensor datalog settings
- Offline Exercise V2 tab (device-dependent)
- HR broadcast listener screen

### What to click/test for H10 and Verity Sense

Common initial flow:
1. `Select device`
2. Connect to target sensor
3. Verify feature readiness in UI (stream/offline buttons enabled only when supported)

H10 focus:
- Online tab: start/stop `HR`, `ECG`, `ACC`
- H10 Exercise tab:
  - `Start H10 recording` / `Stop H10 recording`
  - `List exercises`, `Read exercise`, `Remove exercise`
- Device settings: set/get time, restart/factory reset (if needed in a controlled test)

Verity Sense focus:
- Online tab: start/stop `HR`, `PPI`, `PPG`, `ACC`, `GYRO`, `MAGNETOMETER` (availability depends on mode and firmware)
- Offline tab:
  - Start offline recording per type
  - Trigger settings (disabled/system start/exercise start)
  - List recordings, open details, fetch content, remove recordings
- Device settings: SDK mode enable/disable, set/get time, get disk space, firmware update path selection

### What to observe when device is connected

- Device enters connected state and connected-device list updates.
- Supported features become enabled (`bleSdkFeatureReady` flow in manager).
- Stream values update per data type:
  - HR: bpm + RR list + contact flags
  - ECG: voltage + timestamp
  - ACC/GYRO/MAG: x/y/z + timestamp
  - PPG: channel samples + optional status bits + timestamp
  - PPI: pp interval, error estimate, blocker, contact flags, timestamp
- Offline list populates entries and allows read/remove workflow.
- Device settings actions report result messages (time set/get, disk space, SDK mode status, firmware state).

## 2) Why SDK Is Needed vs Generic BLE HR Only

Generic BLE HR alone gives only a narrow HR profile. Polar BLE SDK adds:
- Stream discovery by device capability (`getAvailableOnlineStreamDataTypes`, feature-ready callbacks)
- Online streaming across multiple data types (not just HR)
- Offline recording lifecycle:
  - start/stop
  - status
  - list/fetch/remove files
  - optional trigger modes
- SDK mode for higher or alternative sampling/range profiles
- Device time operations (`setLocalTime`, `getLocalTime`) and known caveats
- File-oriented workflows and storage management (`listOfflineRecordings`, `getOfflineRecord`, `removeOfflineRecord`, disk space checks)
- Rich data families where supported: ECG, ACC, PPG, PPI, gyro, magnetometer
- Device management operations (firmware update, restart, factory reset, physical data config)

Conclusion: generic BLE HR is insufficient for multi-stream raw-first ingestion and offline sync use cases.

## 3) Device Comparison: Polar H10 vs Polar Verity Sense

| Capability | Polar H10 | Polar Verity Sense |
| --- | --- | --- |
| HR | Yes, bpm, ~1 Hz stream in product notes | Yes |
| RR / PPI / PP interval | RR via HR stream (`rrsMs`); no optical PPI mode | PPI/PP interval supported (with quality flags) |
| ECG | Yes, 130 Hz, microvolts | No |
| ACC | Yes, 25/50/100/200 Hz, ±2/4/8 g, mG | Yes, default 52 Hz ±8 g; wider options in SDK mode |
| PPG | No | Yes (multiple frame types/channels depending on mode/fw) |
| Gyro | No | Yes (default 52 Hz, ±2000 deg/s; more options in SDK mode) |
| Magnetometer | No | Yes (10/20/50/100 Hz online; to 50 Hz offline in SDK mode table) |
| Online streaming | Yes | Yes |
| Offline recording | H10 internal recording API for HR-type exercise recording | Yes (SDK offline recording feature, fw >= 2.1.0 per docs) |
| SDK mode | Not documented as H10 capability in product page | Supported from fw 1.1.5+ |
| Time ops | Supported via device control/time setup features | Supported |
| File listing/fetch/delete | H10 has list/read/remove for stored internal recording | Explicit offline file list/fetch/delete supported |
| Known limitations | Must terminate streams explicitly; disconnect behavior when removed from strap | SDK mode disables computed metrics (HR/PPI), PPI warmup/limitations, sensor mode/system busy constraints |
| Units | ECG µV, ACC mG, HR bpm, RR ms | HR bpm, PPI ms, ACC mG, gyro deg/s, mag Gauss, PPG raw channel ints |
| Config options | Stream settings for ECG/ACC; H10 recording controls | Rich stream/offline settings, triggers, SDK mode expanded settings |

Notes:
- Verity Sense docs explicitly state HR and PPI are not available while SDK mode is enabled.
- Known issue docs include timestamp update caveat after `setLocalTime` until power cycle on some devices/firmwares.

## 4) Mode Comparison Matrix

| Device + mode | Available streams | Unavailable streams | Sample rate/range options | Data format | Timestamp model | Device-time dependency | Expected use case | Risks / limitations |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| H10 online streaming | HR(+RR), ECG, ACC | PPG, gyro, magnetometer | ECG 130 Hz; ACC 25/50/100/200 Hz, ±2/4/8 g | SDK typed objects (`PolarHrData`, `PolarEcgData`, `PolarAccData`) | Per-sample timestamp for ECG/ACC; HR event style | Medium-high if absolute alignment needed | Live sessions, immediate monitoring | Must stop streams cleanly; BLE link required |
| H10 offline/internal recording | Stored HR exercise recording (H10-specific APIs) | No PPG/gyro/mag offline path documented | HR with 1s sampletime in product note | Retrieved exercise data objects | Start/stop/event-time semantics | Medium; depends on device clock handling | Strap-only delayed sync experiments | Single recording at a time; disconnect edge cases |
| H10 SDK mode | Not a primary H10 flow in docs | N/A | N/A | N/A | N/A | N/A | Not prioritized | Treat as not-target for spike |
| Verity Sense online streaming (normal mode) | HR, PPI, PPG, ACC, gyro, magnetometer | ECG | Defaults documented; settings query via SDK | SDK typed objects + frame types | Timestamped sensor streams; HR/PPI may be event-like | Medium-high | Live capture with app-connected sensor | BLE drop causes live gap; PPI quality sensitive to motion |
| Verity Sense offline recording (normal mode) | HR, PPI, PPG, ACC, gyro, magnetometer, temperature/skin temp where supported | ECG | Typically lower ceilings than online; setting query required | Offline files + SDK parsed objects | Offline metadata includes ISO start time + frames | High | Delayed sync / low-connectivity scenarios | Must avoid premature delete; files may appear after buffering delay |
| Verity Sense SDK mode (online/offline) | High-rate/raw sensor options (ACC/GYR/PPG/MAG) | Computed streams unavailable (`HR`, `PPI`) | Expanded rates/ranges from product table | Rawer sensor stream focus | Sensor timestamp model remains PMD-based | High | Advanced raw data experiments | Higher BLE/storage load; invalid state if toggled while recording/streaming |

## 5) Data Format Examples

Important: examples below are intentionally raw-first and keep device/collector timing fields. No canonical `ts_utc` assignment here.

### 5.1 H10 examples

#### H10 HR + RR (SDK-level visible shape)

```json
{
  "hr": 72,
  "rrsMs": [832, 835],
  "rrAvailable": true,
  "contactStatus": true,
  "contactStatusSupported": true
}
```

Proposed UploadChunkContract payload (`stream_type=hr`, `payload_schema=polar.hr`, `payload_version=1.0`):

```json
{
  "samples": [
    {
      "hr_bpm": 72,
      "rr_ms": [832, 835],
      "rr_available": true,
      "contact_status": true,
      "contact_status_supported": true,
      "collector_received_ns": 1714147200123456789
    }
  ],
  "units": { "hr_bpm": "bpm", "rr_ms": "ms" },
  "channels": ["hr_bpm", "rr_ms"],
  "sample_rate_hz": 1
}
```

#### H10 ECG (SDK-level visible shape)

```json
{
  "timeStamp": 694512749912654440,
  "voltage": -214
}
```

Proposed payload (`stream_type=ecg`, new schema suggested `polar.ecg`):

```json
{
  "samples": [
    {
      "device_time_ns": 694512749912654440,
      "ecg_uv": -214
    }
  ],
  "units": { "ecg_uv": "uV", "device_time_ns": "ns_since_2000_epoch" },
  "channels": ["ecg_uv"],
  "sample_rate_hz": 130
}
```

#### H10 ACC (SDK-level visible shape)

```json
{
  "timeStamp": 694512749912654440,
  "x": -12,
  "y": 45,
  "z": 998
}
```

Proposed payload (`stream_type=acc`, existing `polar.acc` can be reused if compatible; otherwise version bump/new schema):

```json
{
  "samples": [
    {
      "device_time_ns": 694512749912654440,
      "x_mg": -12,
      "y_mg": 45,
      "z_mg": 998
    }
  ],
  "units": { "x_mg": "mg", "y_mg": "mg", "z_mg": "mg" },
  "channels": ["x_mg", "y_mg", "z_mg"],
  "sample_rate_hz": 100
}
```

#### H10 offline HR recording (if used)

```json
{
  "samples": [72, 73, 72, 71]
}
```

Proposed payload (`session_mode=offline_recording`, schema candidate `polar.h10.offline_hr`):

```json
{
  "recording_entry": {
    "entry_id": "h10_entry_123",
    "path": "/H10/EXERCISE/...",
    "device_recording_started_local": "2026-04-26T07:10:00+02:00"
  },
  "samples": [
    { "hr_bpm": 72 },
    { "hr_bpm": 73 }
  ],
  "units": { "hr_bpm": "bpm" },
  "sample_rate_hz": 1
}
```

### 5.2 Verity Sense examples

#### Verity HR (SDK-level)

```json
{
  "hr": 67,
  "rrsMs": [],
  "rrAvailable": false,
  "contactStatus": true,
  "contactStatusSupported": false
}
```

Proposed payload (`stream_type=hr`, `polar.hr`):

```json
{
  "samples": [
    {
      "hr_bpm": 67,
      "rr_ms": [],
      "rr_available": false,
      "contact_status": true,
      "contact_status_supported": false,
      "collector_received_ns": 1714147300123456789
    }
  ],
  "units": { "hr_bpm": "bpm" },
  "channels": ["hr_bpm"],
  "sample_rate_hz": 1
}
```

#### Verity PPI / PP interval (SDK-level)

```json
{
  "timeStamp": 724060800000123456,
  "ppInMs": 910,
  "hr": 66,
  "ppErrorEstimate": 8,
  "blockerBit": 0,
  "skinContactSupported": 1,
  "skinContactStatus": 1
}
```

Proposed payload (`stream_type=ppi`, `polar.ppi`):

```json
{
  "samples": [
    {
      "device_time_ns": 724060800000123456,
      "pp_ms": 910,
      "hr_bpm": 66,
      "pp_error_estimate_ms": 8,
      "blocker": 0,
      "skin_contact_supported": 1,
      "skin_contact": 1
    }
  ],
  "units": { "pp_ms": "ms", "pp_error_estimate_ms": "ms", "hr_bpm": "bpm" },
  "channels": ["pp_ms", "pp_error_estimate_ms", "blocker", "skin_contact"],
  "sample_rate_hz": null
}
```

#### Verity PPG (SDK-level)

```json
{
  "type": "ppg3_ambient1",
  "samples": [
    {
      "timeStamp": 724060800000223456,
      "channelSamples": [120034, 118992, 119876, 3022],
      "statusBits": null
    }
  ]
}
```

Proposed payload (`stream_type=ppg`, new schema suggested `polar.ppg`):

```json
{
  "ppg_frame_type": "ppg3_ambient1",
  "samples": [
    {
      "device_time_ns": 724060800000223456,
      "channels": {
        "ppg0": 120034,
        "ppg1": 118992,
        "ppg2": 119876,
        "ambient": 3022
      },
      "status_bits": null
    }
  ],
  "units": { "channels": "raw_int" },
  "channels": ["ppg0", "ppg1", "ppg2", "ambient"],
  "sample_rate_hz": 55
}
```

#### Verity ACC (SDK-level)

```json
{
  "timeStamp": 724060800000323456,
  "x": -18,
  "y": 7,
  "z": 1006
}
```

Proposed payload (`stream_type=acc`, `polar.acc`):

```json
{
  "samples": [
    {
      "device_time_ns": 724060800000323456,
      "x_mg": -18,
      "y_mg": 7,
      "z_mg": 1006
    }
  ],
  "units": { "x_mg": "mg", "y_mg": "mg", "z_mg": "mg" },
  "channels": ["x_mg", "y_mg", "z_mg"],
  "sample_rate_hz": 52
}
```

#### Verity gyro (SDK-level)

```json
{
  "timeStamp": 724060800000423456,
  "x": -1.8,
  "y": 0.6,
  "z": 2.1
}
```

Proposed payload (`stream_type=gyro`, new schema `polar.gyro`):

```json
{
  "samples": [
    {
      "device_time_ns": 724060800000423456,
      "x_dps": -1.8,
      "y_dps": 0.6,
      "z_dps": 2.1
    }
  ],
  "units": { "x_dps": "deg_per_sec", "y_dps": "deg_per_sec", "z_dps": "deg_per_sec" },
  "channels": ["x_dps", "y_dps", "z_dps"],
  "sample_rate_hz": 52
}
```

#### Verity magnetometer (SDK-level)

```json
{
  "timeStamp": 724060800000523456,
  "x": 0.17,
  "y": -0.03,
  "z": 0.51
}
```

Proposed payload (`stream_type=mag`, new schema `polar.mag`):

```json
{
  "samples": [
    {
      "device_time_ns": 724060800000523456,
      "x_gauss": 0.17,
      "y_gauss": -0.03,
      "z_gauss": 0.51
    }
  ],
  "units": { "x_gauss": "gauss", "y_gauss": "gauss", "z_gauss": "gauss" },
  "channels": ["x_gauss", "y_gauss", "z_gauss"],
  "sample_rate_hz": 50
}
```

#### Verity offline recording example (entry + fetched payload)

```json
{
  "entry": {
    "path": "/U/0/20240411/R/202543/HR.REC",
    "size": 11234,
    "type": "hr"
  },
  "start_time_iso8601": "2024-04-11T20:25:43+02:00",
  "settings": {
    "sample_rate": 1,
    "resolution": 0,
    "range": 0,
    "channels": 1
  },
  "samples": [
    { "hr_bpm": 63 },
    { "hr_bpm": 64 }
  ]
}
```

Proposed payload contract:
- `session_mode=offline_recording`
- `stream_type` based on recording type
- preserve `entry.path`, `entry.size`, and parsed metadata fields in payload

## 6) Online vs Offline Implications for HomeLab

### Online streaming (`session_mode=online_live`)

Characteristics:
- Live capture while BLE link is active.
- Collector controls chunk cadence and `sequence` monotonicity.
- Good for near-real-time UX and lower sync complexity.

Recommended raw handling:
- Chunk by sample count and/or short wall-clock windows (for example 1-5 seconds for high-rate streams).
- Keep collector receive times per chunk and per-sample device timestamps when available.
- Keep explicit stream `sequence` in transport envelope.

Connection loss behavior:
- Missing windows happen immediately when BLE breaks.
- No recovery of missed samples unless same signal was simultaneously recorded offline on device.

### Offline recording (`session_mode=offline_recording`)

Characteristics:
- Device records first; app fetches later.
- Upload time can be far from measurement time.
- File metadata and device time become central.

Workflow (safe order):
1. (Optional) stop recording for target type if needed to flush data.
2. List entries (`listOfflineRecordings`).
3. Fetch entry (`getOfflineRecord`) and verify parse/upload success.
4. Only after confirmed raw upload/ack, remove entry (`removeOfflineRecord`).

Avoid data loss:
- Never delete before successful upload confirmation.
- Persist local sync cursor/ledger by `(device_id, entry.path, entry.size, checksum/etag if available)`.
- Support retries and idempotent ingest by `chunk_id` + deterministic file-derived ids.

Partial sync/retry:
- If fetch or upload fails mid-batch, keep entry and retry.
- For current-day aggressive delete methods, follow Polar warning: avoid deleting date folders that may still contain unread data.

## 7) Time Synchronization Analysis

Key official points:
- Polar epoch is `2000-01-01T00:00:00Z` (not Unix 1970).
- Sensor timestamps are nanoseconds from Polar epoch for timestamped streams.
- Some streams are event-like (HR/PPI) and may have missing/zero/non-sample-precise timestamp semantics.
- Device time may reset to defaults depending on product/power behavior.
- Known issue: on some devices/firmwares, `setLocalTime` may not affect stream timestamps until power cycle.

From measurement docs:
- PMD frame carries measurement type, timestamp, frame metadata and payload.
- Conversion factor and frame settings are required for correct physical values.
- Offline recordings include metadata block + start time + settings + packet size before frame data.

### Implications for `ts_utc`

Do not assign canonical `ts_utc` in collector or ingestion.

Normalizer later should derive canonical analytical time using:
- device timestamp fields when reliable + known device time state
- collector receive/upload clocks for fallback and confidence scoring
- offline metadata start times + stream sample-rate/frame reconstruction

### Recommended alignment confidence rubric

- `high`:
  - timestamped sensor stream (ECG/ACC/GYR/MAG/PPG) with coherent device time and no reset indicators
  - stable mapping to collector clock in session
- `medium`:
  - timestamped stream but potential device-time caveat (post-setLocalTime without reboot, uncertain offset)
  - event-like data with partial timing info
- `low`:
  - HR/PPI without robust per-sample timestamp semantics
  - unknown/reset device time, or only offline file start time + inferred intervals

### Raw timing fields to preserve per chunk/sample

Always preserve as available:
- `collector_received_at` / `uploaded_at_collector`
- `collection.mode`
- `sequence`
- `device_time_reference` (explicit descriptor string)
- per-sample `device_time_ns` where present
- offline metadata:
  - file path
  - file start time string
  - recording settings
  - packet size/frame type/compression markers if surfaced
- any computed offset diagnostics (as metadata, not canonical truth)

## 8) Architecture Impact Mapping

Current architecture rule: `UI -> Collector Core -> Device Adapter -> Transport`.

### New iOS adapters needed

Recommendation:
- Add a shared Polar transport/client layer adapter (`PolarSdkAdapter`) for common connect/feature APIs.
- Add device-specific adapters on top:
  - `PolarH10Adapter`
  - `PolarVeritySenseAdapter`

Reasoning:
- shared BLE SDK lifecycle and feature callbacks can be reused
- device capability/mode/limitations diverge enough to warrant explicit adapters
- preserves collector core stability and mock/test paths

### Payload schemas: existing vs missing

Already present in repo:
- `polar.hr` v1.0
- `polar.ppi` v1.0
- `polar.acc` v1.0

Likely missing for this spike:
- `polar.ecg`
- `polar.ppg`
- `polar.gyro`
- `polar.mag`
- optional device-specific offline metadata wrappers if current schemas are too online-centric

### Normalizer handlers needed later (not in this checkpoint)

- `polar.hr` normalizer (H10 + Verity HR semantics)
- `polar.ppi` normalizer (quality flag gating)
- `polar.acc` normalizer
- new handlers for `ecg`, `ppg`, `gyro`, `mag`
- offline-aware timing reconstruction helpers (metadata + frame-level timing)

### Stream types to implement first

Recommended order (aligned with current architecture and risk):
1. H10 online `hr` (+ RR from HR payload)
2. H10 online `acc` or `ecg` after HR/RR stability
3. Verity Sense online `hr` + `ppi` + `acc`
4. Offline recording spike (list/fetch/delete safety and retry model)
5. High-rate streams (`ppg`, `gyro`, `mag`, high-rate ACC/ECG) after storage + normalization strategy is validated

## 9) Practical Notes for HomeLab Contracts

- Keep `online_live`, `offline_recording`, `file_import` explicit in transport `collection.mode`.
- Preserve raw timestamps and raw frame facts.
- Do not force canonical timestamps in iOS or ingestion.
- Keep ingestion payload opaque; parsing/normalization remains downstream.
- Keep mock/test pathways available by preserving adapter boundary.

## 10) Risks and Open Questions for Next Checkpoint

- Need explicit payload schema decisions for `polar.ecg`, `polar.ppg`, `polar.gyro`, `polar.mag`.
- Need deterministic idempotency strategy for offline file retries (`entry.path` alone may be insufficient across edge cases).
- Need final policy for device-time health checks and reset detection.
- Need empirical validation of Verity Sense SDK mode combinations and throughput limits for concurrent high-rate streams.
- Need to decide whether H10 internal recording should be mapped into the same offline contract shape as Verity files or as separate schema.

