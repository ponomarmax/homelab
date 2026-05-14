# wearable-pipeline-api

Lightweight processing API for wearable raw JSONL artifacts.

Pipeline flow:
- `normalize`
- `window_features`
- `build_session_summary` (deterministic `session_summary.json` artifact)

## Endpoints

- `GET /health`
- `POST /api/v1/pipeline/run`
  - Optional JSON body: `{"session_id": "<session-id>"}` to run a single session only

## Environment

- `RAW_ROOT` (default: `/data/wearable/raw`)
- `PROCESSED_ROOT` (default: `/data/wearable/processed`)
- `PIPELINE_STATE_ROOT` (default: `/data/wearable/pipeline_runs`)
- `LOG_LEVEL` (default: `INFO`)
- `WEARABLE_PIPELINE_API_HOST` (default: `127.0.0.1`)
- `WEARABLE_PIPELINE_API_PORT` (default: `8091`)
- `L0_CROSS_STREAM_MAX_START_DELTA_SECONDS` (default: `10`)
- `L0_CROSS_STREAM_MAX_END_DELTA_SECONDS` (default: `10`)
- `L0_CROSS_STREAM_MIN_OVERLAP_RATIO` (default: `0.5`)
- `L0_CROSS_STREAM_MIN_ANCHOR_STREAMS` (default: `2`)
- `L0_CROSS_STREAM_ANCHOR_STREAMS` (default: `acc,gyro,mag,ppg`)
- `ENABLE_PPI_STARTUP_DELAY` (default: `false`)
- `PPI_STARTUP_DELAY_SECONDS` (default: `25`)

## Time Alignment Notes

- Normalization emits `time_alignment_report.json` per processed session.
- L0-based alignment is cross-validated against anchor streams.
- If a stream's L0 window is inconsistent with anchor windows, alignment is downgraded to L2 (`cross_stream_anchoring`) with warning `l0_cross_stream_inconsistent`.
- Verity Sense offline PPI fallback uses interval-based reconstruction from `ppInMs` and can optionally apply configurable startup delay for session-specific batching behavior.

## Local run

```bash
python3 app.py --host 127.0.0.1 --port 18091
```

## Tests

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

## Engineering Guidance

- Best practices: `docs/wearable/pipeline_service_best_practices.md`
- Refactor playbook (normalize -> features/window): `docs/wearable/refactor_playbook_normalize_features_window.md`
