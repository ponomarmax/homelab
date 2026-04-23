# Prometheus Config

Prometheus stores and queries observability metrics.

## Deployment

Prometheus runs from `infra/compose/observability.yml` using Docker Compose.

Deploy through the repository workflow:

```sh
tools/scripts/deploy.sh prometheus --confirm
```

## Configuration

- `prometheus.yml` - scrape configuration.
- `rules/` - future alerting or recording rules when they become useful.

Current scrape targets:

- `prometheus` - Prometheus self-scrape.
- `node-exporter` - host metrics exposed by Node Exporter through Docker host gateway.
- `cadvisor` - container metrics exposed inside the Compose network.

## Persistence

Prometheus is stateful.
Runtime data is stored in the explicit Docker named volume:

```text
homelab_prometheus_data
```

Do not commit Prometheus TSDB data to Git.

## Retention

Retention is limited from the start:

```text
PROMETHEUS_RETENTION=15d
```

This matches the repository constraint to keep storage growth bounded on a small single-node host.

## Validation

Run:

```sh
tools/scripts/check-prometheus.sh --remote
tools/scripts/check-prometheus.sh --lan
```

The remote validation checks startup, restart stability, health endpoint, Node Exporter target state, a basic `up{job="node-exporter"}` query, persistent volume usage, recreate behavior, and host LAN interface reachability.

The LAN validation checks the Prometheus API from the workstation side using `PROMETHEUS_LAN_HOST`.

## Future Integration

Future Grafana data source provisioning should point at Prometheus on the Compose network or host-local endpoint documented by that checkpoint.
