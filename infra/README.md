# Infrastructure

Docker-first infrastructure for the local single-node platform.

Current contents:

- `compose/` - Docker Compose files and smoke test assets
- `observability/` - scaffolding for future Prometheus, Grafana, cAdvisor, and Node Exporter checkpoints
- `env/` - environment variable documentation

The project should stay single-node and lightweight. New always-on services should include an explicit resource and retention note before being added.

## Data Browser (Developer Utility)

- Service: `data-browser`
- Purpose: local file inspection for wearable raw data
- URL: `http://localhost:11000/` (local) and `http://<DATA_BROWSER_LAN_HOST>:11000/` (LAN)
- Exposed directory: Docker volume `wearable_raw_data` mounted at `/data` in read-only mode
- Access model: no auth, LAN/local only; do not publish through reverse proxy or internet-facing routes
