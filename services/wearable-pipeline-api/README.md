# wearable-pipeline-api

Lightweight processing API for wearable raw JSONL artifacts.

## Endpoints

- `GET /health`
- `POST /api/v1/pipeline/normalize/hr`

## Environment

- `RAW_ROOT` (default: `/data/wearable/raw`)
- `PROCESSED_ROOT` (default: `/data/wearable/processed`)
- `PIPELINE_STATE_ROOT` (default: `/data/wearable/pipeline_runs`)
- `LOG_LEVEL` (default: `INFO`)
- `WEARABLE_PIPELINE_API_HOST` (default: `127.0.0.1`)
- `WEARABLE_PIPELINE_API_PORT` (default: `8091`)

## Local run

```bash
python3 app.py --host 127.0.0.1 --port 18091
```

## Tests

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
```
