# Polar Battery Status by Mode (H10 + Verity Sense)

Status: documentation spike only. No runtime integration changes in this checkpoint.

## Scope

Цей документ пояснює, як отримувати battery-статус через Polar BLE SDK:
- для Polar H10 і Polar Verity Sense
- у контексті `online_live`, `offline_recording`, `sdk_mode`
- з прикладами payload-ів для інтеграції в HomeLab transport/raw ingestion

## Official references

- Polar SDK README (feature flags, iOS callbacks):
  - <https://github.com/polarofficial/polar-ble-sdk/blob/master/README.md>
- Polar iOS example manager (battery callbacks, polling APIs):
  - <https://github.com/polarofficial/polar-ble-sdk/blob/master/examples/example-ios/polar-sensor-data-collector/PSDC/PolarBleSdkManager.swift>
- Polar iOS battery model (fields/validation):
  - <https://github.com/polarofficial/polar-ble-sdk/blob/master/examples/example-ios/polar-sensor-data-collector/PSDC/Models/BatteryStatusFeature.swift>
- Verity Sense known battery issue while charging:
  - <https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/KnownIssues.md>
- Product docs:
  - H10: <https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/products/PolarH10.md>
  - Verity Sense: <https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/products/PolarVeritySense.md>

## 1) Battery APIs: what is actually available

### Required SDK feature

На iOS потрібно ініціалізувати API з `feature_battery_info`.

Without this feature flag:
- readiness for battery info is not guaranteed
- battery callbacks may never arrive

### Push callbacks (event-driven)

З прикладу `PolarBleSdkManager`:
- `batteryLevelReceived(_ identifier: String, batteryLevel: UInt)`
- `batteryChargingStatusReceived(_ identifier: String, chargingStatus: BleBasClient.ChargeState)`
- `batteryPowerSourcesStateReceived(_ identifier: String, powerSourcesState: BleBasClient.PowerSourcesState)`

### Pull APIs (on-demand polling)

Також доступні синхронні читання з прикладу:
- `api.getBatteryLevel(identifier:)`
- `api.getChargerState(identifier:)`

Рекомендація: використовувати **гібрид**
- основний канал: callbacks
- підстраховка: poll при connect та періодично (наприклад раз на 60-300 сек)

## 2) Device + Mode matrix

> Важливо: battery telemetry не є потоком ECG/PPG/ACC. Це BAS/device-info канал і зазвичай не залежить від того, який sensor-stream ти запустив. Але залежить від BLE-підключення та доступності `feature_battery_info`.

| Device | Mode context | Чи можна читати battery | Як отримувати | Практичні ризики |
| --- | --- | --- | --- | --- |
| H10 | `online_live` | Так, якщо є BLE connection і `feature_battery_info` ready | callbacks + optional poll | Якщо H10 від’єднаний від ремінця/без зв’язку, апдейтів не буде |
| H10 | `offline_recording` (H10 internal recording use-case) | Так під час активного BLE-сеансу | callbacks + poll перед/після sync-операцій | H10 може дисконектитись при знятті з ремінця; довгі операції читання запису чутливі до цього |
| H10 | `sdk_mode` | Немає окремого документованого H10 SDK-mode battery режиму | Якщо `feature_battery_info` ready, читати як стандартний battery BAS | Розглядати як same-as-connected BAS, без окремих гарантій по H10 SDK mode |
| Verity Sense | `online_live` | Так, якщо є connection + feature ready | callbacks + optional poll | Під час charging на певних FW battery% може бути stale |
| Verity Sense | `offline_recording` | Так, коли пристрій підключено до телефону | callbacks + poll під час sync phase | Під час internal/swimming/file-transfer constraints можливі інші busy стани; battery канал не заміняє sync-стани |
| Verity Sense | `sdk_mode` | Так (battery BAS окремо від data streaming mode) | callbacks + optional poll | У SDK mode вимикаються обчислені алгоритми HR/PPI, але це не тотожно battery off |

## 3) Mode-specific guidance for HomeLab

### 3.1 `online_live`

Recommended flow:
1. connect device
2. verify `feature_battery_info` ready
3. subscribe battery callbacks
4. emit battery raw chunks on every callback change
5. periodic poll as watchdog

Use case:
- live health/telemetry of collector session
- quick warning if battery low before high-rate streams

### 3.2 `offline_recording`

Recommended flow:
1. on sync session start: one immediate battery poll snapshot
2. while fetching files: keep callback listener active
3. after successful upload/delete cycle: another battery snapshot

Use case:
- correlate sync failures with low battery
- estimate whether device can finish next offline window

### 3.3 `sdk_mode`

Recommended flow:
- treat battery as device-status channel independent from ECG/PPG/PPI availability
- still collect battery callbacks/polls
- do not infer stream support from battery status alone

## 4) Known limitations and caveats

1. Verity Sense charging bug (KnownIssues): when plugged into USB charger, reported battery level may stay at charge-start value on some firmware; after unplugging values become correct again.
2. No BLE session = no fresh battery updates.
3. `feature_battery_info` must be enabled in SDK initialization.
4. H10 disconnect behavior when removed from strap can interrupt long operations; battery sampling during such windows becomes unreliable.

## 5) Proposed HomeLab integration (no runtime changes yet)

Current architecture: `UI -> Collector Core -> Device Adapter -> Transport`.

Recommended adapter responsibility:
- `PolarH10Adapter` and `PolarVeritySenseAdapter` both expose unified battery events
- Collector Core only sees normalized adapter event contract, not SDK-specific enums

### Transport strategy options

Option A (no transport enum change now):
- `stream_family = quality`
- `stream_type = unknown`
- `transport.payload_schema = polar.device_battery`

Option B (future explicit transport extension):
- add `stream_type = battery`
- keep payload schema `polar.device_battery`

For this checkpoint, Option A is safer because it avoids transport schema edits.

## 6) Sample data series

Important:
- keep raw SDK semantics
- no `ts_utc` assignment in collector/ingestion
- include `collection.mode` explicitly (`online_live` or `offline_recording`)

### 6.1 SDK-level callback event sample

```json
{
  "identifier": "A1B2C3D4",
  "batteryLevel": 84,
  "chargingStatus": "charging",
  "powerSourcesState": {
    "batteryPresent": "connected",
    "wiredExternalPowerConnected": "connected",
    "wirelessExternalPowerConnected": "disconnected"
  },
  "collector_received_at": "2026-04-26T15:05:17.221Z"
}
```

### 6.2 SDK-level poll snapshot sample

```json
{
  "identifier": "A1B2C3D4",
  "batteryLevelPolled": 83,
  "chargerStatePolled": "discharging",
  "collector_received_at": "2026-04-26T15:10:00.102Z"
}
```

### 6.3 HomeLab UploadChunkContract payload (online)

```json
{
  "schema_version": "1.0",
  "chunk_id": "chunk_batt_000123",
  "session_id": "sess_20260426_1500",
  "stream_id": "stream_battery_main",
  "stream_type": "unknown",
  "sequence": 123,
  "source": {
    "vendor": "polar",
    "device_model": "Polar Verity Sense",
    "device_id": "A1B2C3D4"
  },
  "collection": {
    "mode": "online_live"
  },
  "time": {
    "device_time_reference": "battery_status_no_sample_clock",
    "first_sample_received_at_collector": "2026-04-26T15:05:17.221Z",
    "uploaded_at_collector": "2026-04-26T15:05:17.590Z"
  },
  "transport": {
    "encoding": "json",
    "compression": "none",
    "payload_schema": "polar.device_battery",
    "payload_version": "1.0"
  },
  "payload": {
    "event_type": "callback_update",
    "battery": {
      "level_percent": 84,
      "charge_state": "charging",
      "power_sources": {
        "battery_present": "connected",
        "wired_external_power": "connected",
        "wireless_external_power": "disconnected"
      }
    },
    "sdk_raw": {
      "charging_state_enum": "BleBasClient.ChargeState.charging"
    },
    "units": {
      "level_percent": "percent"
    }
  }
}
```

### 6.4 HomeLab UploadChunkContract payload (offline sync context)

```json
{
  "schema_version": "1.0",
  "chunk_id": "chunk_batt_000987",
  "session_id": "sess_20260426_sync_01",
  "stream_id": "stream_battery_sync",
  "stream_type": "unknown",
  "sequence": 7,
  "source": {
    "vendor": "polar",
    "device_model": "Polar H10",
    "device_id": "H10_7F31"
  },
  "collection": {
    "mode": "offline_recording"
  },
  "time": {
    "device_time_reference": "battery_status_no_sample_clock",
    "first_sample_received_at_collector": "2026-04-26T18:20:00.012Z",
    "uploaded_at_collector": "2026-04-26T18:20:00.122Z"
  },
  "transport": {
    "encoding": "json",
    "compression": "none",
    "payload_schema": "polar.device_battery",
    "payload_version": "1.0"
  },
  "payload": {
    "event_type": "sync_snapshot",
    "sync_phase": "before_offline_file_fetch",
    "battery": {
      "level_percent": 41,
      "charge_state": "discharging"
    }
  }
}
```

### 6.5 Error/unavailable sample

```json
{
  "event_type": "battery_unavailable",
  "reason": "feature_battery_info_not_ready_or_device_disconnected",
  "collector_received_at": "2026-04-26T18:22:01.004Z"
}
```

## 7) Recommended ingestion/normalization boundaries

Ingestion stage:
- store raw JSONL as-is
- do not attempt battery analytics inference

Normalizer stage (later):
- optional derived metrics:
  - battery drain slope per hour
  - low-battery windows before stream dropouts
  - charger-state transitions
- only here assign canonical analytical timestamps if needed

## 8) Implementation checklist (next practical step)

1. In each Polar adapter, ensure `feature_battery_info` is part of enabled feature set.
2. Emit battery callback events into dedicated battery stream channel.
3. Add periodic poll watchdog (configurable interval).
4. During offline sync workflow, record battery snapshot at least at:
   - sync start
   - before delete
   - sync end
5. Keep battery payload schema stable (`polar.device_battery`), version independently from transport envelope.

## 9) What is intentionally not done here

- no code changes in iOS collector
- no schema file additions under `packages/schemas`
- no updates to ingestion/normalizer services
