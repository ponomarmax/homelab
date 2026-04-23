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
- `dashboards/baseline.yml` - provisions dashboard JSON files from `/etc/grafana/dashboards`.
- `alerting/empty.yml` and `plugins/empty.yml` keep provisioning paths valid while those checkpoints remain out of scope.

This keeps the service usable after deploy without manual clicking in the UI.

Default plugin preinstall work is disabled in Compose to keep startup lightweight and avoid background plugin changes in this checkpoint.

## Dashboards

Repository-controlled dashboards live under:

```text
infra/observability/config/grafana/dashboards/
```

Current baseline dashboards:

- `host/linux-server.json` - host CPU, memory, disk, load, and network metrics from Node Exporter.
- `containers/docker-containers.json` - container CPU, memory, network, and filesystem I/O metrics from cAdvisor.

Grafana uses `foldersFromFilesStructure`, so subdirectories become Grafana folders.

## Validation

Run:

```sh
tools/scripts/check-grafana.sh --remote
tools/scripts/check-grafana.sh --lan
```

The validation checks startup, health, datasource provisioning, dashboard provisioning, Grafana-mediated Prometheus queries for host and container panels, persistent volume usage, and recreate behavior.

## Future Integration

Add future dashboard JSON files under `dashboards/<folder>/`.
Use stable dashboard `uid` values and the provisioned Prometheus datasource UID `prometheus`.
Then run `tools/scripts/check-grafana.sh --remote` and `tools/scripts/check-grafana.sh --lan`.

Future alerting work should be added in a separate checkpoint.
