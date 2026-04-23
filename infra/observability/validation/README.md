# Observability Validation

Place observability-specific validation notes and fixtures here.

Current generic validation entry point:

```sh
tools/scripts/check-observability.sh
```

Current service validation:

```sh
tools/scripts/check-node-exporter.sh --remote
tools/scripts/check-node-exporter.sh --lan
tools/scripts/check-prometheus.sh --remote
tools/scripts/check-prometheus.sh --lan
tools/scripts/check-cadvisor.sh --remote
tools/scripts/check-cadvisor.sh --lan
tools/scripts/check-grafana.sh --remote
tools/scripts/check-grafana.sh --lan
```

For LAN validation, set `NODE_EXPORTER_LAN_HOST` in `.env` when it differs from the SSH `SERVER_IP`.
Set `PROMETHEUS_LAN_HOST` the same way when the Prometheus LAN address differs from `SERVER_IP`.
Set `CADVISOR_LAN_HOST` the same way when the cAdvisor LAN address differs from `SERVER_IP`.
Set `GRAFANA_LAN_HOST` the same way when the Grafana LAN address differs from `SERVER_IP`.

Future service checkpoints should add validation steps for:

- compose syntax
- expected config files
- container health or readiness
- restart and recreate behavior
- log inspection
