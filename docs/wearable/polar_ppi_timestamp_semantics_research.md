# Polar PPI Timestamp Semantics Research (Polar BLE SDK)

## 1. Executive summary
- **Documented fact:** Polar explicitly states that for streams where individual sample time cannot be defined (example: PPI, HR), sample time may be `0` or missing.
- **Documented fact:** In current Polar BLE SDK code (Android+iOS), PPI parser reconstructs per-sample timestamps **backward** from frame timestamp using cumulative `ppInMs` (ms -> ns), and leaves sample timestamps as `0` when frame timestamp is `0`.
- **Documented fact:** Polar Verity Sense docs and maintainer comments state PPI algorithm is batched/windowed (commonly 5-second windows; first delivery can be ~25s after start) and older generations may not provide true per-beat absolute timestamps.
- **Inferred behavior:** For Verity Sense/older optical pipeline, per-sample timestamps are often reconstructed/derived rather than directly measured beat-event timestamps.
- **Practical conclusion:** Reliable **ordering** and **relative timing** can be reconstructed from `ppInMs`; fully reliable **absolute per-beat wall-clock timing** is conditional on device/firmware providing trustworthy non-zero PMD frame timestamps and stable device time.

## 2. What Polar officially guarantees
- **Documented fact:** Polar epoch is `2000-01-01T00:00:00Z`; timestamps are nanoseconds from this epoch.
- **Documented fact:** Device time can be set/read via `setLocalTime` / `getLocalTime`.
- **Documented fact:** PPI is pulse-to-pulse interval from optical PPG, similar to RR but not same phase.
- **Documented fact:** PPI quality is sensitive to motion/contact; blocker and skin-contact flags are provided (with caveats for older optical devices).
- **Documented fact:** For Verity Sense, first PPI samples can arrive with delay (~25s), and PPI is incompatible with SDK mode.

Sources:
- https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/TimeSystemExplained.md
- https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/PPIData.md
- https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/products/PolarVeritySense.md

## 3. What Polar explicitly does NOT guarantee
- **Documented fact:** Polar states some streams (including PPI, HR) do not have well-defined individual sample time; sample time may be zero/missing.
- **Documented fact:** Skin-contact reliability is explicitly warned as weak on older optical generations (Verity Sense, OH1).
- **Documented fact:** Timestamp correctness can be affected by device-time handling; known issue says `setLocalTime` may not affect stream timestamps until power cycle (Verity Sense, OH1).

Sources:
- https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/TimeSystemExplained.md
- https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/PPIData.md
- https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/KnownIssues.md

## 4. How Polar timestamps work
- **Documented fact:** Device clock basis is nanoseconds since Polar epoch (2000-01-01 UTC).
- **Documented fact:** PMD frames include an 8-byte frame timestamp.
- **Documented fact (code):** For fixed-rate streams (ACC/GYRO/MAG/PPG/etc.) SDK uses sampling rate and/or previous frame timestamps to interpolate per-sample timestamps.
- **Documented fact (code):** PPI parser does **not** use fixed sample-rate interpolation; it assigns timestamps by reverse cumulative subtraction of `ppInMs` from frame timestamp.
- **Documented fact (code):** If PPI frame timestamp is `0`, SDK leaves sample timestamps at `0`.

Sources:
- https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/TimeSystemExplained.md
- https://github.com/polarofficial/polar-ble-sdk/blob/master/sources/Android/android-communications/library/src/main/java/com/polar/androidcommunications/api/ble/model/gatt/client/pmd/PmdDataFrame.kt
- https://github.com/polarofficial/polar-ble-sdk/blob/master/sources/iOS/ios-communications/Sources/iOSCommunications/ble/api/model/gatt/client/pmd/PmdDataFrame.swift
- https://github.com/polarofficial/polar-ble-sdk/blob/master/sources/Android/android-communications/library/src/main/java/com/polar/androidcommunications/api/ble/model/gatt/client/pmd/model/PpiData.kt
- https://github.com/polarofficial/polar-ble-sdk/blob/master/sources/iOS/ios-communications/Sources/iOSCommunications/ble/api/model/gatt/client/pmd/model/PpiData.swift

## 5. How PPI is generated conceptually
- **Documented fact:** PPI is derived from optical PPG peaks (pulse-to-pulse), not ECG R-wave detection.
- **Documented fact:** PPI is substantially more noise-sensitive than ECG RR and intended for complete rest.
- **Documented fact:** Verity Sense PPI uses a separate algorithm from ordinary HR path; HR updates every 5s when PPI mode enabled; first samples delayed.
- **Inferred behavior:** Delivery is event-interval data batched into windows, not “instant per-beat push” semantics.

Sources:
- https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/PPIData.md
- https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/products/PolarVeritySense.md
- https://github.com/polarofficial/polar-ble-sdk/issues/484#issuecomment-2444050286

## 6. What each field likely means
- `ppInMs`
  - **Documented fact:** Pulse-to-pulse interval in milliseconds.
- `timeStamp`
  - **Documented fact (current SDK code):** Per sample value in API output, reconstructed from PMD frame timestamp and cumulative intervals for PPI parser.
  - **Documented fact (legacy behavior + maintainer comments):** Historically often `0` for PPI; older devices/algorithms may not provide native timestamp.
- `hr`
  - **Documented fact:** Heart rate estimate associated with PPI sample record.
  - **Documented fact:** In Verity Sense PPI mode, HR behavior differs from normal HR mode; may be limited and less reliable during movement.
- `ppErrorEstimate`
  - **Documented fact:** Expected absolute PP interval error in ms.
  - **Documented fact (maintainer guidance):** `<10 ms` likely very accurate; `>30 ms` may indicate artifact/poor contact.
- `blockerBit`
  - **Documented fact:** Indicates invalidity due to movement/acceleration or other blocker reason.
- `skinContactStatus`
  - **Documented fact:** Contact status indicator for sample.
- `skinContactSupported`
  - **Documented fact:** Whether contact feature is supported.
  - **Documented fact:** For older optical devices, contact support/status may be unreliable.

Sources:
- https://github.com/polarofficial/polar-ble-sdk/blob/master/sources/Android/android-communications/library/src/sdk/java/com/polar/sdk/api/model/PolarPpiData.kt
- https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/PPIData.md
- https://github.com/polarofficial/polar-ble-sdk/issues/146#issuecomment-814834473
- https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/products/PolarVeritySense.md

## 7. Evidence from official docs
- **Documented fact:** TimeSystemExplained says PPI sample time may be zero/missing.
- **Documented fact:** PPIData describes quality caveats and validity flags.
- **Documented fact:** Verity Sense doc says first batch delay (~25s), separate PPI algorithm, and warns about skin-contact reliability.
- **Documented fact:** Offline recording docs treat PPI as offline-capable data type, but do not provide a strict per-sample timestamp guarantee text.

Sources:
- https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/TimeSystemExplained.md
- https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/PPIData.md
- https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/products/PolarVeritySense.md
- https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/SdkOfflineRecordingExplained.md

## 8. Evidence from SDK code
- **Documented fact (Android+iOS):** PPI frame is type 0 raw, 6-byte sample chunks: `hr`, `ppInMs`, `ppErrorEstimate`, flags byte.
- **Documented fact (Android+iOS):** Parser initializes PPI sample timestamp to `0`, then if `frame.timeStamp != 0`, assigns last sample = frame timestamp and walks backward subtracting `ppInMs * 1_000_000`.
- **Documented fact:** Offline file parsing reuses same PMD frame parser path, so same semantics apply online/offline once frame timestamp exists.
- **Documented fact:** SDK tests assert this backward reconstruction behavior for PPI.

Sources:
- https://github.com/polarofficial/polar-ble-sdk/blob/master/sources/Android/android-communications/library/src/main/java/com/polar/androidcommunications/api/ble/model/gatt/client/pmd/model/PpiData.kt
- https://github.com/polarofficial/polar-ble-sdk/blob/master/sources/iOS/ios-communications/Sources/iOSCommunications/ble/api/model/gatt/client/pmd/model/PpiData.swift
- https://github.com/polarofficial/polar-ble-sdk/blob/master/sources/Android/android-communications/library/src/main/java/com/polar/androidcommunications/api/ble/model/offlinerecording/OfflineRecordingData.kt
- https://github.com/polarofficial/polar-ble-sdk/blob/master/sources/iOS/ios-communications/Sources/iOSCommunications/ble/api/model/offlinerecording/OfflineRecordingData.swift
- https://github.com/polarofficial/polar-ble-sdk/blob/master/sources/iOS/ios-communications/Tests/iOSCommunicationsTests/PpiDataTest.swift

## 9. Evidence from GitHub issues/discussions
- **Documented fact (historical):** Maintainer previously stated PPI timestamp was always 0 / not meaningful in stream and recommended app-side estimation.
- **Documented fact (newer timeline):** Polar created and shipped work to add PPI timestamps (issue #558 discussion).
- **Documented fact:** Maintainer notes Verity Sense algorithm itself may not calculate timestamps for samples; older generation behavior differs from newer devices (e.g., Polar 360).
- **Documented fact:** Community repeatedly reports timing ambiguity around non-wear gaps and offline reconstruction.
- **Documented fact:** Separate timestamp-delta failures (non-PPI-specific) indicate broader clock continuity pitfalls when previous frame timestamp > current.

Sources:
- https://github.com/polarofficial/polar-ble-sdk/issues/146
- https://github.com/polarofficial/polar-ble-sdk/issues/211
- https://github.com/polarofficial/polar-ble-sdk/issues/484#issuecomment-2444050286
- https://github.com/polarofficial/polar-ble-sdk/issues/558
- https://github.com/polarofficial/polar-ble-sdk/issues/740

## 10. Likely intended reconstruction model
- **Documented fact:** Current SDK implementation itself uses cumulative-interval reconstruction from frame anchor.
- **Inferred behavior:** Polar’s intended practical model today appears to be:
  1. Use PMD frame timestamp as anchor when present/non-zero.
  2. Reconstruct earlier beat-event times by backward cumulative `ppInMs`.
  3. Fall back to `0`/missing when no anchor exists.
- **Hypothesis:** For older Verity Sense paths without native per-sample timestamping, this reconstruction is best-available approximation, not ground-truth event timestamping.

## 11. Risks and ambiguities
- **Contradictory evidence across time:** older maintainer guidance says PPI timestamp meaningless/zero; current code generates per-sample timestamps from frame anchor.
- **Device/firmware variability:** behavior differs across product generations (explicitly called out by maintainers).
- **Clock integrity risk:** time resets, unsynchronized clocks, or backwards device-time jumps can invalidate continuity.
- **Quality risk:** motion/contact artifacts can make `ppInMs` itself unreliable even if timestamp math is consistent.
- **Anchor risk:** if frame timestamp is packet/window-level rather than true beat-end instant, reconstructed beat times may be systematically shifted.

## 12. Recommended normalization strategy boundaries (architecture, no code)
- **Raw preservation**
  - Preserve original frame-level metadata and sample fields (`ppInMs`, `ppErrorEstimate`, flags, original sample timestamp field from SDK output).
  - Preserve recording start time and file boundaries.
- **Canonical timeline policy**
  - Treat reconstructed per-sample timestamp as **derived** unless provenance indicates direct native timestamp support.
  - Keep provenance flags: `timestamp_origin = {native, reconstructed_from_frame, missing_zero}`.
- **Confidence scoring boundaries**
  - Use blocker/contact/errorEstimate to grade sample confidence.
  - Do not infer sign from `ppErrorEstimate` (absolute error only).
- **Continuity boundaries**
  - Detect and segment on non-monotonic timestamps, large discontinuities, and timestamp resets.
  - Accept duplicate timestamps as possible artifact of reconstruction/window anchoring and segment accordingly rather than forcing strict uniqueness.
- **Bad interval handling boundaries**
  - Keep raw; mark suspect intervals instead of deleting by default.
  - Separate “analysis-ready filtered view” from immutable raw evidence.

## 13. Open questions
- Is PMD PPI frame timestamp formally defined as end-of-window, last-beat timestamp, or packet emission time in latest firmware docs? (No explicit normative statement found in inspected markdown sources.)
- Are Verity Sense 3.x firmware lines changing PPI timestamp semantics beyond what issue comments state?
- What exact device list/firmware matrix has native PPI timestamps vs reconstructed-only behavior?
- What guarantees (if any) exist for duplicate timestamp handling at PMD frame boundaries?

## 14. Proposed empirical validation experiments
1. **Online Verity Sense session (rest):** compare SDK sample timestamps vs cumulative `ppInMs` recomputation to verify exact parser-consistency and boundary behavior.
2. **Offline Verity Sense recording:** inspect whether frame timestamps are zero/non-zero and quantify proportion of reconstructed vs missing timestamps.
3. **Motion artifact protocol:** induce movement periods; evaluate `blockerBit`, `ppErrorEstimate`, and timestamp continuity patterns.
4. **Clock perturbation test:** controlled `setLocalTime` scenarios and power-cycle permutations to verify KnownIssues interactions and timestamp resets.
5. **Cross-device matrix:** Verity Sense vs OH1 vs Polar 360 using same protocol to document generation differences.
6. **Non-wear gap protocol:** remove/re-wear cycles and evaluate whether timelines remain contiguous, padded, or shifted.
7. **Packet boundary test:** verify duplicate timestamp occurrence rate at frame transitions and relationship to last-sample anchoring.

---

## Appendix: fact vs inference vs hypothesis legend
- **Documented fact:** directly stated in Polar docs, SDK code, or maintainer comments.
- **Inferred behavior:** strongest interpretation consistent with multiple facts, but not explicitly guaranteed.
- **Hypothesis:** plausible explanation requiring further empirical verification.
