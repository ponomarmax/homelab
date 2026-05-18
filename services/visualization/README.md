# Wearable Operator Dashboard (Python)

Lightweight Streamlit service for operational inspection across wearable pipeline stages.

## Pages

- Session List: merged operator status list from `wearable-pipeline-api`.
- Session Details: artifacts/status for one session + normalized stream chart with zoom.

## Environment

- `PIPELINE_API_BASE_URL` (default `http://wearable-pipeline-api:8091`)
- `RAW_ROOT` (default `/data/wearable/raw`)
- `PROCESSED_ROOT` (default `/data/wearable/processed`)

## Local run

```bash
cd services/visualization
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
streamlit run wearable_operator_dashboard/app.py
```

## Test

```bash
cd services/visualization
PYTHONPATH=. python3 -m unittest tests_test_data_access.py -v
```
