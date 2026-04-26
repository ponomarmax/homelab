# Local Notebook Exploration Environment

This directory is a local-only exploration layer for wearable pipeline artifacts.

Scope:
- Explore processed artifacts (`clean_timeseries`, `window_features`, `session_summary`)
- Optionally inspect matching raw session chunks (`chunks.jsonl`) for debugging/traceability
- Sync data from homelab server automatically via read-only SSH/rsync pulls

Out of scope:
- No production pipeline dependency
- No server-side services
- No writes to remote server data
- No normalization/feature/LLM/report delivery logic inside notebooks

## 1. Prerequisites

- Python 3.10+
- `ssh` and `rsync` available in local shell
- SSH access to homelab server

## 2. Setup

From repository root:

```bash
cd notebooks
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## 3. Configure `.env`

Create `notebooks/.env` with:

```env
REMOTE_HOST=
REMOTE_USER=
REMOTE_BASE_PATH=/data/wearable
SSH_KEY_PATH=
```

Notes:
- `SSH_KEY_PATH` is optional.
- Do not commit secrets, private hostnames, or credentials.

## 4. Run

```bash
cd notebooks
source .venv/bin/activate
jupyter lab
```

Open notebooks in order:
- `00_session_discovery.ipynb`
- `01_session_explorer.ipynb`

## 5. Data Cache

- Synced data is stored only under `notebooks/data_cache/`
- Cache is git-ignored
- Notebooks read local copies only
- Sync is idempotent (`rsync -az`) and safe to run repeatedly

## 6. Notebook Flow

- Discovery notebook lists available sessions per user from remote `raw` + `processed`
- Explorer notebook syncs selected session then loads:
  - clean streams
  - window features
  - session summary
  - optional raw chunks (preview-friendly limits)
- Raw debug view compares raw vs processed availability and highlights mismatches
