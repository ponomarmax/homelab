# Infrastructure

Docker-first infrastructure for the local single-node platform.

Current contents:

- `compose/` - Docker Compose files and smoke test assets
- `observability/` - scaffolding for future Prometheus, Grafana, cAdvisor, and Node Exporter checkpoints
- `env/` - environment variable documentation

The project should stay single-node and lightweight. New always-on services should include an explicit resource and retention note before being added.
