# Observability Scaffold

This directory contains the lightweight observability stack as it is added checkpoint by checkpoint.

Current service:

- Node Exporter - host metrics endpoint for future Prometheus scraping.
- Prometheus - metrics storage and scraping for observability targets.
- cAdvisor - container metrics endpoint scraped by Prometheus.
- Grafana - observability UI with provisioned Prometheus datasource.

Current dashboards:

- Host / Linux Server - host CPU, memory, disk, load, and network metrics.
- Docker / Containers - container CPU, memory, network, and filesystem I/O metrics.

## Layout

```text
infra/observability/
  config/
    prometheus/
      rules/
    grafana/
      dashboards/
      provisioning/
    cadvisor/
    node-exporter/
  scripts/
  validation/
```

## Compose

Observability services are added to:

```sh
infra/compose/observability.yml
```

The base platform compose file stays in:

```sh
infra/compose/docker-compose.yml
```

Validate the base and observability compose files together:

```sh
docker compose \
  --env-file .env.example \
  -f infra/compose/docker-compose.yml \
  -f infra/compose/observability.yml \
  config
```

## Configuration

- `config/prometheus/` - Prometheus configuration and future alerting or recording rules.
- `config/grafana/` - Grafana dashboards and provisioning files.
- `config/cadvisor/` - cAdvisor service notes or minimal config, if needed later.
- `config/node-exporter/` - Node Exporter service notes or collector flags, if needed later.

Keep service-specific configuration close to the service directory. Shared validation or deployment helpers should stay in `tools/scripts/`.

## Persistence

Use Docker named volumes by default for stateful observability services.

Expected stateful services:

- Prometheus - time-series database; start with limited retention, currently planned as 15 days.
- Grafana - dashboards, data sources, users, and local settings.

Expected stateless services:

- cAdvisor - container metrics exporter.
- Node Exporter - host metrics exporter.

If bind-mounted local state is needed for development or migration, use `data/observability/` and do not commit generated runtime data.

## Workflow

1. Add one observability service per checkpoint.
2. Add service config under `infra/observability/config/<service>/`.
3. Add only necessary service-specific helper scripts under `infra/observability/scripts/`.
4. Put generic checks in `tools/scripts/`.
5. Validate compose syntax before deployment.
6. After deployment, verify restart behavior and inspect logs.
7. Record the handoff in `07_progress_log.md` or a progress draft.

Current validation entry point:

```sh
tools/scripts/check-node-exporter.sh
tools/scripts/check-prometheus.sh
tools/scripts/check-cadvisor.sh
tools/scripts/check-grafana.sh
```

## Resource Notes

The host has 8GB RAM, so the stack should remain small.
Prometheus retention must be limited from the first real Prometheus checkpoint.
Avoid adding optional exporters or dashboards until there is a clear operational need.
