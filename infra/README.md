# Infrastructure

Docker-first infrastructure for the local single-node platform.

Current contents:

- `compose/` - Docker Compose files and smoke test assets
- `observability/` - scaffolding for future Prometheus, Grafana, cAdvisor, and Node Exporter checkpoints
- `env/` - environment variable documentation

The project should stay single-node and lightweight. New always-on services should include an explicit resource and retention note before being added.

## Data Browser (Developer Utility)

- Service: `data-browser`
- Purpose: local file inspection for wearable pipeline data under `/data/wearable`
- URL: `http://localhost:11000/` (local) and `http://<DATA_BROWSER_LAN_HOST>:11000/` (LAN)
- Exposed directory: `/data` with writable mounts for `wearable_raw_data`, `wearable_processed_data`, and `wearable_pipeline_state`
- Access model: no auth, local/LAN admin use only; do not publish through reverse proxy, WAN, or internet-facing routes
