# Ingestion API

Lightweight CP3 backend for wearable HR uploads.

Responsibilities:
- accept `UploadChunkContract`
- validate transport envelope + `polar.hr@1.0` payload shape
- append accepted raw chunks as JSONL under configured raw path
- return ACK on success
- return structured error on failure

Out of scope:
- timestamp normalization
- feature computation
- LLM calls
- Telegram delivery

## Run

```bash
python3 services/ingestion-api/app.py --host 127.0.0.1 --port 8090
```

Optional env vars:
- `INGESTION_API_HOST`
- `INGESTION_API_PORT`
- `WEARABLE_RAW_DATA_PATH`

Endpoint:
- `POST /upload-chunk`
