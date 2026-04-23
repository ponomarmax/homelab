# Post 001 — Contract-First Wearable Ingestion

## Status
draft

## Date
2026-04-23

## Text
Before building the first wearable ingestion API, I paused and did something less exciting:

I defined the contracts.

The current milestone in my homelab ML transition project is a raw-first wearable data foundation.

The direction:
- one iOS collector app
- multiple sensor adapters
- Polar Verity Sense first
- Muse Athena later
- backend ingestion separated from parsing and analytics

The important design choice:

The outer transport contract stays stable.
The inner sensor payload stays flexible.

That means the backend can accept data from different sensors without becoming tightly coupled to one device shape.

For now, the repository has:
- transport schemas for sessions, streams, upload chunks, acknowledgements, and errors
- payload schemas for Polar HR, PPI, and accelerometer streams
- draft payload schemas for Muse EEG and PPG
- examples that can be inspected manually
- a payload registry so schema IDs and versions are explicit

Why this matters:

In ML projects, the model is usually not the first hard problem.

The first hard problem is often:
- what exactly are we collecting?
- how do we preserve the raw data?
- how do we avoid rewriting ingestion when the next sensor arrives?
- how do we keep debugging possible six months later?

So the first backend milestone is intentionally simple:

POST one upload chunk.
Validate the envelope.
Store the raw payload.
Return an acknowledgement.

No feature engineering yet.
No premature analytics layer.
No heavy infrastructure.

Just a clean boundary between collection, ingestion, parsing, and future analysis.

This is less glamorous than a dashboard.

But it is the kind of foundation that makes the dashboard trustworthy later.


## Hook options
- Before building the first wearable ingestion API, I paused and defined the contracts.
- The model is not the first hard problem in an ML system. The data boundary is.
- My next homelab milestone is not a dashboard. It is a contract.

## Visual
- path: content/linkedin/assets/001_contracts/
- prompt: content/linkedin/assets/001_contracts/image_prompt.md

## Metrics
- views:
- likes:
- comments:

## Notes
- Related to the monorepo restructuring and canonical wearable contract foundation.
- Good checkpoint because it shows architecture discipline before implementation.
