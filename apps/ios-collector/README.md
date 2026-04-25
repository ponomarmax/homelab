# iOS Collector

Initial iOS collector skeleton for the wearable HR MVP.

This checkpoint provides:
- a runnable SwiftUI app foundation
- a mock device adapter
- a mock HR stream provider
- collector core session lifecycle
- testable domain models for collection mode and timestamp metadata
- mock session metadata, stream descriptor, and upload chunk preparation

This checkpoint does **not** provide:
- Polar SDK integration
- Bluetooth logic
- backend upload
- raw JSONL writing

## Architecture

Current app structure:

`UI -> Collector Core -> Device Adapter -> Stream Provider -> Transport`

Implemented in CP2:
- `CollectorCore` owns session lifecycle and latest HR state
- `CollectorDeviceAdapter` defines future device integration boundary
- `HeartRateStreamProviding` defines future stream integration boundary
- `MockDeviceAdapter` and `MockHeartRateStreamProvider` make the app runnable in simulator
- `MockCollectorTransport` prepares future session/chunk boundaries without performing upload
- `CollectionSession`, `StreamDescriptor`, and `UploadChunk` keep the transport-facing model explicit
- `HeartRateChunkBuilder` turns buffered mock HR samples into transport-ready chunk payloads

## Runtime Configuration (Best Practice)

Collector uses a layered configuration strategy:

1. `Info.plist` defaults (versioned in repo, stable for device builds).
2. Launch environment variables (for local overrides).
3. Launch arguments (highest priority for explicit mode switches).

Configured keys:
- `COLLECTOR_USE_MOCK_DEFAULT` (`Bool`)  
  Default mock mode when no explicit override is provided.
- `COLLECTOR_UPLOAD_ENDPOINT` (`String`)  
  Upload destination. If only base URL is provided (for example `http://192.168.0.5:18090/`), collector auto-expands to `/upload-chunk`.

Launch overrides:
- `--mock` forces mock adapter.
- `--real` forces real adapter.
- `COLLECTOR_USE_MOCK=1|0` forces adapter mode.
- `COLLECTOR_UPLOAD_ENDPOINT=http://host:port/...` overrides upload URL.

Recommended workflow:
- Keep `COLLECTOR_USE_MOCK_DEFAULT=false` in `Info.plist`.
- Keep server URL in `Info.plist` for normal app runs.
- Use launch args/env only for tests, CI, and temporary local diagnostics.

## Open in Xcode

Open:

- `apps/ios-collector/ios-collector.xcodeproj`

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
  -project apps/ios-collector/ios-collector.xcodeproj \
  -scheme CollectorApp \
  -destination 'platform=iOS Simulator,name=<AVAILABLE_IPHONE_SIMULATOR>'
```

If simulator execution is blocked in the current shell environment, `xcodebuild build-for-testing` should still compile the app and test target.

## Manual Validation

1. Open `apps/ios-collector/ios-collector.xcodeproj` in Xcode.
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

Real iPhone is not required for CP2.
