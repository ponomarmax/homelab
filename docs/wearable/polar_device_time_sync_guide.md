# Polar Device Time Guide (H10 + Verity Sense)

Status: documentation spike only. No production code changes in this checkpoint.

## Scope

Цей документ покриває:
- як встановлювати час на пристрої (`setLocalTime`)
- як читати час із пристрою (`getLocalTime` / `getLocalTimeWithZone`)
- як перевіряти, що синхронізація пройшла коректно
- особливості для H10 та Verity Sense
- нюанси в режимах `online_live`, `offline_recording`, `sdk_mode`
- приклади SDK-викликів і приклади HomeLab raw payload

## Official references

- Time system: <https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/TimeSystemExplained.md>
- Known issues: <https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/KnownIssues.md>
- Sync guideline: <https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/SyncImplementationGuideline.md>
- Polar SDK README: <https://github.com/polarofficial/polar-ble-sdk/blob/master/README.md>
- iOS example manager (`setTime`, `getTime`):
  - <https://github.com/polarofficial/polar-ble-sdk/blob/master/examples/example-ios/polar-sensor-data-collector/PSDC/PolarBleSdkManager.swift>
- PMD online/offline measurement docs:
  - <https://github.com/polarofficial/polar-ble-sdk/blob/master/technical_documentation/online_measurement.pdf>
  - <https://github.com/polarofficial/polar-ble-sdk/blob/master/technical_documentation/offline_measurement.pdf>
- Product docs:
  - H10: <https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/products/PolarH10.md>
  - Verity Sense: <https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/products/PolarVeritySense.md>

## 1) Core model: what “device time” means in Polar

### Epoch and units

- Polar sensor timestamp epoch: `2000-01-01T00:00:00Z`.
- Timestamps are represented as **nanoseconds since Polar epoch**.
- If you convert using Unix-epoch tooling, add offset:
  - `946684800000000000 ns` between 1970 and 2000 epochs.

### Streams with strong sample timestamps vs event-like streams

From official docs:
- Strong per-sample timing: ECG / ACC / magnetometer / similar sensor streams.
- Event-like timing (sample-precise timestamp may be absent/zero/less strict): HR / PPI.

Implication:
- Time verification should rely on timestamped sensor streams first (ECG/ACC/GYR/MAG/PPG).

## 2) Official APIs for time

### Set time

- API: `setLocalTime(deviceId, time, zone)`
- iOS example uses current phone `Date()` + `TimeZone.current`.

### Get time

- API: `getLocalTime` / in iOS example `getLocalTimeWithZone(deviceId)`
- Returns both date and timezone.

### Optional helper in example

- `setDaylightSavingTime()` exists in the example manager, but the primary sync API remains `setLocalTime` + `getLocalTime`.

## 3) Step-by-step: robust sync procedure

### Preconditions

1. BLE connected to target device.
2. Device supports time feature (`feature_polar_device_time_setup` or `feature_polar_device_control` readiness in example manager).
3. No assumptions about prior device clock state.

### Recommended sequence

1. Read current device time (`T_dev_before`).
2. Capture phone reference time (`T_phone_set`) right before `setLocalTime`.
3. Call `setLocalTime(device, T_phone_set, TimeZone.current)`.
4. Read back device time (`T_dev_after`) immediately.
5. Compute absolute delta:
   - `|T_dev_after - T_phone_now|`
6. Start one timestamped stream (ECG or ACC) and verify timestamp progression is plausible.
7. For affected firmware/devices, power cycle if known issue applies, then re-verify stream timestamps.

### Pass/Fail heuristic

- Pass (basic): read-after-write succeeds, no API error, timezone matches expected.
- Pass (strong): read-after-write delta is within tolerance (for example <= 2-5 seconds, adjustable by connection latency).
- Pass (stream): timestamped stream values are monotonic and map reasonably to expected wall clock after conversion.
- Needs remediation: values still look pre-set/default after `setLocalTime`.

## 4) Device-specific notes

### H10

- Device may reset to default time after shutdown conditions (e.g., detached strap + no BLE, per official docs).
- For long sessions, re-check device time periodically or at each connect.
- Timestamp verification can use ECG/ACC streams.

### Verity Sense

- Default-time reset behavior differs from H10 (official docs: default reset typically tied to deeper power/battery state scenarios).
- Known issue states timestamp update after `setLocalTime` may require power off/on on some firmwares.
- After setting time, include stream-based verification; if mismatch persists, do controlled reboot and re-check.

## 5) Mode-specific behavior

> Important: time APIs are device-control operations, separate from whether you run HR/ECG/offline file flow. But operational timing of when to call them matters.

| Mode | Can set/get time? | Recommended timing | Validation focus | Risks |
| --- | --- | --- | --- | --- |
| `online_live` | Yes (with device-control/time feature ready) | On connect, before starting key streams | immediate `getLocalTime` + timestamped stream monotonicity | Known issue: stream timestamps may not reflect new time until power cycle on some FW |
| `offline_recording` | Yes | Prefer between offline recording phases (official sync guideline) | check before fetch/delete phases; preserve metadata for later alignment | Changing config/time mid-recording may complicate interpretation; schedule carefully |
| `sdk_mode` | Yes (time control is separate from SDK mode stream capabilities) | Before high-rate run, and after mode toggles if needed | same as above + stream sanity in chosen mode | Do not toggle SDK mode during active recording/streams (invalid-state risk from SDK mode doc) |

## 6) Known issues that affect verification

From official Known Issues:
- Verity Sense (all FW listed there): after `setLocalTime`, stream timestamps may not change until power off/on.
- Similar timestamp issue is listed for OH1; treat sensor-family behavior cautiously when validating.

Operational interpretation:
- A successful `setLocalTime` API response alone is not sufficient for “timing fully aligned” status.
- Always include stream-level verification for timestamped data.

## 7) Practical iOS examples (from official SDK usage pattern)

### 7.1 Set and get time

```swift
// Set device time to phone current time
let now = Date()
let zone = TimeZone.current
try await api.setLocalTime(deviceId, time: now, zone: zone).value

// Read back device time
let (deviceDate, deviceZone) = try await api.getLocalTimeWithZone(deviceId).value
print("Device time: \(deviceDate), zone: \(deviceZone.identifier)")
```

### 7.2 Verification helper

```swift
let toleranceSec: TimeInterval = 5
let now2 = Date()
let delta = abs(deviceDate.timeIntervalSince(now2))
if delta <= toleranceSec {
    print("Time sync OK: delta=\(delta)s")
} else {
    print("Time sync drift: delta=\(delta)s; run stream verification")
}
```

### 7.3 Stream timestamp verification idea

```swift
// Example: ECG stream timestamps should be monotonic
var previous: UInt64?
_ = api.startEcgStreaming(deviceId, settings: ecgSettings)
  .subscribe(onNext: { frame in
      for s in frame.samples {
          let ts = s.timeStamp
          if let p = previous, ts <= p {
              print("Non-monotonic timestamp detected")
          }
          previous = ts
      }
  })
```

## 8) HomeLab raw payload recommendations (time operations)

Important:
- keep raw operational events in ingestion
- do not assign canonical `ts_utc` here
- let normalizer derive canonical alignment later

### 8.1 Time-set operation event (`online_live` context)

```json
{
  "event_type": "device_time_set",
  "device": {
    "vendor": "polar",
    "model": "Polar H10",
    "device_id": "H10_7F31"
  },
  "collection": { "mode": "online_live" },
  "operation": {
    "requested_local_time": "2026-04-26T19:10:05+03:00",
    "requested_timezone": "Europe/Kyiv",
    "api": "setLocalTime",
    "result": "success"
  },
  "collector_received_at": "2026-04-26T16:10:05.412Z"
}
```

### 8.2 Time-read operation event

```json
{
  "event_type": "device_time_read",
  "device": {
    "vendor": "polar",
    "model": "Polar Verity Sense",
    "device_id": "A1B2C3D4"
  },
  "collection": { "mode": "offline_recording" },
  "operation": {
    "api": "getLocalTimeWithZone",
    "device_time": "2026-04-26T19:10:07+03:00",
    "device_timezone": "Europe/Kyiv"
  },
  "collector_received_at": "2026-04-26T16:10:07.018Z"
}
```

### 8.3 Verification result event

```json
{
  "event_type": "device_time_verification",
  "device": {
    "vendor": "polar",
    "model": "Polar Verity Sense",
    "device_id": "A1B2C3D4"
  },
  "collection": { "mode": "online_live" },
  "verification": {
    "delta_seconds": 1.2,
    "tolerance_seconds": 5,
    "stream_check": "pending_or_passed",
    "result": "pass"
  },
  "notes": [
    "if stream timestamps still old after setLocalTime, perform power cycle and repeat check"
  ]
}
```

## 9) How to confirm sync “really good” (checklist)

1. `getLocalTime` before set and log it.
2. `setLocalTime` returns success.
3. `getLocalTime` after set returns expected wall-clock and timezone.
4. Delta to phone time is within agreed tolerance.
5. Timestamped stream (ECG/ACC/PPG/GYR/MAG) shows monotonic timestamps and plausible absolute alignment.
6. If mismatch persists and known issue applies: controlled power cycle, repeat steps 2-5.

## 10) Integration guidance for your architecture

For `UI -> Collector Core -> Device Adapter -> Transport`:

- `Device Adapter` layer should own all time-control calls and verification.
- `Collector Core` receives neutral events:
  - `device_time_set`
  - `device_time_read`
  - `device_time_verification`
- `Transport` persists these as raw operational chunks (`collection.mode` explicit).
- `Normalizer` later combines:
  - operational time events
  - sensor stream timestamps
  - offline metadata start times
  to compute canonical analytical timeline.

## 11) Not done in this checkpoint

- No collector code updates.
- No ingestion schema migrations.
- No automatic retry orchestration implementation.
