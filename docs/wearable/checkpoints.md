# Wearable Checkpoints

## Goal

Break the work into small observable vertical slices.

---

## CP0 — Fake transport proof
- iOS app sends a fake payload
- backend accepts it
- raw file is stored
- basic success response is visible

## CP1 — Polar connection state
- app scans and connects
- connection state is visible
- session lifecycle is visible

## CP2 — Local HR visibility
- live HR is visible in the app
- packet count grows
- last packet time is visible

## CP3 — Real HR end-to-end
- real HR is uploaded
- raw backend file is stored
- success / failure upload state is visible

## CP4 — Raw storage readability
- files are grouped by session and stream
- raw data is easy to inspect manually

## CP5 — Basic backend visualization
- session list
- simple HR over time
- last upload visibility

## CP6 — Basic resilience
- reconnect handling
- backend unavailable handling
- duplicate upload handling

## CP7 — PPI expansion
- PPI is added without changing the outer contract

## CP8 — ACC expansion
- ACC is added without changing the outer contract