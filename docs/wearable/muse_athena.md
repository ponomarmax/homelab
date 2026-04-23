# Muse Athena

## Role in the project

Muse Athena is a planned extension for:
- EEG
- IMU
- possible PPG
- future experimental multimodal signals

## Direction

Muse should reuse the same collector app and the same outer upload contracts.

## Important boundary

The Muse SDK is a library for client software.
It should be integrated into the collector app.
The SDK exposes sensor data and some processed data, but not the more advanced processed signals used by the Muse mobile app.

MuseLab is a separate desktop tool and can receive OSC from the phone app.
That path is useful for exploration, but the phone screen must stay active for continuous streaming.
This does not change the agreed collector-to-backend transport contracts.

## Current assumptions

Planned first focus:
- EEG
- accelerometer
- gyroscope
- optional PPG

## Open questions

- exact SDK-accessible stream set for Athena
- exact payload shapes for all packet types
- fNIRS / optics availability in SDK reality
- long-session runtime behavior on iOS

## Rule

Do not design the transport layer around undocumented Muse-specific assumptions.
