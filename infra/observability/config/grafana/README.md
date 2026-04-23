# Grafana Config

Grafana is the observability UI layer.

## Deployment

Grafana runs from `infra/compose/observability.yml` using Docker Compose.

Deploy through the repository workflow:

```sh
tools/scripts/deploy.sh grafana --confirm
```

## State

Grafana is stateful.
Runtime data is stored in the explicit Docker named volume:

```text
homelab_grafana_data
```

Do not commit Grafana databases, sessions, plugins, or runtime state to Git.

## Provisioning

Repository-controlled provisioning lives under:

```text
infra/observability/config/grafana/provisioning/
```

Current provisioning:

- `datasources/prometheus.yml` - provisions Prometheus as the default datasource.
- `alerting/empty.yml`, `dashboards/empty.yml`, and `plugins/empty.yml` keep provisioning paths valid while those checkpoints remain out of scope.

This keeps the service usable after deploy without manual clicking in the UI.

Default plugin preinstall work is disabled in Compose to keep startup lightweight and avoid background plugin changes in this checkpoint.

## Validation

Run:

```sh
tools/scripts/check-grafana.sh --remote
tools/scripts/check-grafana.sh --lan
```

The validation checks startup, health, datasource provisioning, a Grafana-mediated Prometheus query, persistent volume usage, and recreate behavior.

## Future Integration

Future dashboard provisioning should use `provisioning/dashboards/` and versioned dashboard JSON files under `dashboards/`.
Future alerting work should be added in a separate checkpoint.
