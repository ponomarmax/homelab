# Post 002 — iOS Collector Skeleton With Mock HR

## Status
draft

## Date
2026-04-24

## Text
The next checkpoint in my homelab wearable pipeline is not real Bluetooth yet.

It is something more basic and more useful first:

a simulator-runnable iOS collector skeleton with a mock heart-rate stream.

The goal of this stage was to make the collector architecture real before integrating Polar hardware:

- SwiftUI app that opens in Xcode and runs in simulator
- collector core that owns session lifecycle
- device adapter abstraction for future sensors
- stream provider abstraction for future HR, PPI, ACC, and EEG streams
- transport boundary placeholder for future upload contracts
- mock HR provider so the whole flow is testable without a physical device

For this checkpoint, the app can:

- select a mock device
- start a live session
- show changing HR values
- count received samples
- stop the session cleanly

Why I wanted this before BLE integration:

If the first working version depends on Bluetooth, hardware state, permissions, and a real wearable from day one, debugging gets messy fast.

Using a mock HR stream first lets me validate:

- the app structure
- the session model
- the collector state transitions
- the UI responsiveness
- the testing path

So the first iOS milestone is intentionally small:

`UI -> Collector Core -> Device Adapter -> Stream Provider -> Transport`

No Polar SDK yet.
No upload yet.
No backend coupling yet.

Just a clean boundary that already runs, already shows live values, and already has tests.

That is the kind of checkpoint I trust more than a flashy demo that skips the architecture.

The screen recording for this post shows the app running in simulator with the mock HR stream updating in real time.

## Hook options
- Before touching Bluetooth, I made the iOS wearable collector run in simulator with a mock HR stream.
- The first useful iOS wearable milestone was not BLE. It was a testable mock stream.
- I wanted the collector architecture to run before I asked real hardware to cooperate.

## Visual
- primary: simulator screen recording of Start -> live HR updates -> Stop
- secondary: generated architecture visual from `content/linkedin/assets/002_ios_collector_mock_hr/image_prompt.md`

## Metrics
- views:
- likes:
- comments:

## Notes
- Good post because it shows an implementation checkpoint, not just planning.
- The demo recording is the strongest primary visual because it proves the simulator-first flow.
- The generated diagram can be used as a carousel cover or second slide.
