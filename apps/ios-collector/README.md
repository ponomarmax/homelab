# iOS Collector

Initial iOS collector skeleton for the wearable HR MVP.

This checkpoint provides:
- a runnable SwiftUI app foundation
- a mock device adapter
- a mock HR stream provider
- collector core session lifecycle
- testable domain models for collection mode and timestamp metadata

This checkpoint does **not** provide:
- Polar SDK integration
- Bluetooth logic
- backend upload
- raw JSONL writing

## Architecture

Current app structure:

`UI -> Collector Core -> Device Adapter -> Stream Provider -> Transport`

Implemented in CP1:
- `CollectorCore` owns session lifecycle and latest HR state
- `CollectorDeviceAdapter` defines future device integration boundary
- `HeartRateStreamProviding` defines future stream integration boundary
- `MockDeviceAdapter` and `MockHeartRateStreamProvider` make the app runnable in simulator
- `MockCollectorTransport` prepares future session/chunk boundaries without performing upload

## Open in Xcode

Open:

- `apps/ios-collector/ios-collector.xcodeproj`

App target:
- `CollectorApp`

Test target:
- `CollectorAppTests`

## Test Command

Example command:

```bash
xcodebuild test \
  -project apps/ios-collector/ios-collector.xcodeproj \
  -scheme CollectorApp \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

If the simulator name is unavailable on the local machine, replace it with an installed simulator from Xcode.

## Manual Validation

1. Open `apps/ios-collector/ios-collector.xcodeproj` in Xcode.
2. Select an iPhone Simulator target.
3. Run the `CollectorApp` scheme.
4. Confirm the main screen opens with title, state, latest HR, and sample count.
5. Press `Select Mock Device`.
6. Confirm the state changes to `Device Selected`.
7. Press `Start`.
8. Confirm the state changes to `Collecting`.
9. Confirm the latest HR changes over time.
10. Confirm the total sample count increases.
11. Press `Stop`.
12. Confirm the state changes to `Stopped`.
13. Confirm the HR value and sample count stop updating.

Optional:
- run on a real iPhone for UI sanity checking only

Real iPhone is not required for CP1.
