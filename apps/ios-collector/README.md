# iOS Collector

Initial iOS collector skeleton for the wearable HR MVP.

This collector provides:
- a runnable SwiftUI app foundation
- test-only mock device adapter
- test-only mock HR stream provider
- collector core session lifecycle
- testable domain models for collection mode and timestamp metadata
- session metadata / stream descriptor / upload chunk preparation
- persistent session ledger (Application Support JSON)
- unassigned offline recordings grouping and assignment actions
- pending server-sync queue for session manifests with retry support

This checkpoint does **not** provide:
- Polar SDK integration
- Bluetooth logic
- backend upload
- raw JSONL writing

## Architecture

Current app structure:

`UI -> Collector Core -> Device Adapter -> Transport`

Implemented in CP2:
- `CollectorCore` owns session lifecycle and latest HR state
- `CollectorDeviceAdapter` defines future device integration boundary
- `DeviceStatus` / `BatteryStatus` provide a vendor-agnostic latest-status model for UI
- `CollectorStreamProviding` defines stream integration boundary
- `MockDeviceAdapter` and `MockHeartRateStreamProvider` are test doubles under `CollectorAppTests/TestDoubles`
- `CollectorHTTPTransport` prepares and uploads chunks (or runs local-only mode when endpoint is absent)
- `CollectionSession`, `StreamDescriptor`, and `UploadChunk` keep the transport-facing model explicit
- `CollectorChunkBuilder` turns buffered samples into transport-ready chunk payloads
- `SessionLedgerStore` persists managed session state and pending manifest sync queue
- `NightSessionViewModel` + `SessionWorkflowCoordinator` provide one-button offline PPI+ACC operational flow

Current stream naming and payload schemas:
- `hr` -> `polar.hr`
- `ecg` -> `polar.ecg`
- `acc` -> `polar.acc`
- `battery` -> `polar.device_battery`

## Device Status (Latest Known, In-Memory)

- UI reads generic `DeviceStatusSnapshot` state from `CollectorCore` only.
- Device list shows battery when cached/known; otherwise falls back to clean capability-aware text (for example `available after connection`).
- Active session status shows latest known battery level when callback or poll updates arrive.
- Battery status is in-memory only (no backend fetch, no persistence/history).

## Runtime Configuration (Best Practice)

Collector uses a layered configuration strategy:

1. `Info.plist` defaults (versioned in repo, stable for device builds).
2. Launch environment variables (for local overrides).
3. Launch arguments (highest priority for explicit mode switches).

Configured keys:
- `COLLECTOR_UPLOAD_ENDPOINT` (`String`)  
  Upload destination. If only base URL is provided (for example `http://192.168.0.5:18090/`), collector auto-expands to `/upload-chunk`.
- `COLLECTOR_PIPELINE_ENDPOINT` (`String`)
  Pipeline trigger endpoint, for example `http://192.168.0.5:18091/api/v1/pipeline/trigger`.
- `COLLECTOR_UNASSIGNED_CLUSTER_GAP_SECONDS` (`Number`, optional)
  Time gap threshold (seconds) for clustering unassigned offline recordings. Default is `180`.
- `COLLECTOR_UPLOAD_FLUSH_INTERVAL_SECONDS` (`Number`, optional)
  Time-based upload cadence override. Default is `60` seconds.

Launch overrides:
- `COLLECTOR_UPLOAD_ENDPOINT=http://host:port/...` overrides upload URL.

Recommended workflow:
- Keep server URL in `Info.plist` for normal app runs.
- Use launch env overrides for tests, CI, and temporary local diagnostics.

## Upload Cadence

Upload scheduling is time-based by default:
- if a stream buffer has data, collector flushes that stream every `upload_flush_interval_seconds` (default: `60`)
- if a stream buffer is empty, collector does nothing
- on stop, collector performs a final flush of remaining buffered samples

Sample-count flush is optional and configuration-driven:
- disabled by default to avoid excessive small uploads for high-frequency streams (for example ACC/ECG)
- can be enabled per stream via collector upload configuration overrides

## Stream Settings Preservation

When SDK stream settings are negotiated at stream start (for example ECG/ACC sample rate, range, resolution, channels), collector preserves them raw in upload payload:

- `payload.stream_settings`

Notes:
- values are adapter-captured metadata, not interpreted by ingestion
- ingestion stores payload as-is (raw-first boundary remains unchanged)
- downstream pipeline/ML/reporting is responsible for any interpretation

## Open in Xcode

Open:

- `apps/ios-collector/ios-collector.xcworkspace` (preferred)

App target:
- `CollectorApp`

Test target:
- `CollectorAppTests`

## Test Command

Discover available simulators first:

```bash
xcrun simctl list devices available
```

Then run tests with any available iPhone simulator:

```bash
xcodebuild test \
  -workspace apps/ios-collector/ios-collector.xcworkspace \
  -scheme CollectorApp \
  -destination 'platform=iOS Simulator,name=<AVAILABLE_IPHONE_SIMULATOR>'
```

If simulator execution is blocked in the current shell environment, run workspace-based compile-only:

```bash
xcodebuild build-for-testing \
  -workspace apps/ios-collector/ios-collector.xcworkspace \
  -scheme CollectorApp \
  -destination 'platform=iOS Simulator,name=<AVAILABLE_IPHONE_SIMULATOR>'
```

## Manual Validation

1. Open `apps/ios-collector/ios-collector.xcworkspace` in Xcode.
2. Select an iPhone Simulator target.
3. Run the `CollectorApp` scheme.
4. Confirm the main screen opens with title, state, latest HR, total samples, and buffered samples.
5. Press `Select Mock Device`.
6. Confirm the state changes to `Device Selected`.
7. Press `Start`.
8. Confirm the state changes to `Collecting`.
9. Confirm the latest HR changes over time.
10. Confirm the total sample count increases.
11. Confirm the buffered sample count increases.
12. Press `Prepare Chunk`.
13. Confirm the buffered sample count resets and last chunk diagnostics appear.
14. Press `Stop`.
15. Confirm the state changes to `Stopped`.
16. Confirm the HR value and sample counters stop updating.

Optional:
- run on a real iPhone for UI sanity checking only

## Offline Session Management (Implemented)

- In-app started sessions are persisted in local session ledger and can be recovered after app restart.
- If session started in-app but stopped externally, collector marks lifecycle as externally stopped on next reconciliation.
- Offline files can be linked to existing managed session or grouped from unassigned recordings.
- Unassigned recordings can be uploaded:
  - as one merged session
  - or as multiple sessions by time clusters
- Session IDs are collector-generated with UTC prefix + short GUID suffix (`S-YYYYMMDD-HHMMSSZ-XXXXXXXX`).

## One-Button Night Session (Operational)

- Start button: `Start Night Session`
  - connects/selects device if needed
  - selects offline streams `PPI` + `ACC`
  - starts offline recording
- Stop button: `Stop & Sync Session`
  - stops offline recording
  - refreshes/lists offline recordings
  - uploads raw chunks with stable collector session id
  - triggers pipeline endpoint for the uploaded session
- Status cards show:
  - collector session id
  - backend session id (same id when backend does not return separate id)
  - pipeline trigger status
  - optional dashboard/session link

## Pending Server Sync and Retry (Implemented)

- Session manifests are sent to ingestion `POST /session-manifest`.
- If server is unavailable, manifest sync is queued locally as pending (with retry count and last error).
- UI shows pending sync entries and allows manual retry.
- Collector also retries pending manifest sync on app foreground activation.

## Manual Validation: Locked-Screen BLE HR Collection

Use a real iPhone and Polar device:

1. Start HR collection.
2. Confirm HR samples are arriving in the app.
3. Lock the iPhone screen for 30-60 seconds while collection continues.
4. Unlock the iPhone.
5. Prepare and upload a chunk.
6. Verify sample timestamps continue through the locked interval without a large gap.
7. Verify uploaded raw JSONL includes:
   - sample-level `payload.samples[].received_at_collector`
   - chunk-level `time.first_sample_received_at_collector`
   - no chunk-level `time.received_at_collector`
