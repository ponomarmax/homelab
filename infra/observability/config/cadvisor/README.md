# cAdvisor Config

cAdvisor exposes container-level CPU, memory, filesystem, and network metrics for Prometheus.

## Deployment

cAdvisor runs from `infra/compose/observability.yml` using Docker Compose.

Deploy through the repository workflow:

```sh
tools/scripts/deploy.sh cadvisor --confirm
```

The service is stateless and does not need persistent storage.

cAdvisor listens on port `8080` inside the Compose network.
The host/LAN port defaults to `${CADVISOR_PORT:-8080}`.

## Host Access

cAdvisor needs read access to host and Docker runtime paths to produce meaningful container metrics:

- `/:/rootfs:ro`
- `/var/run:/var/run:ro`
- `/sys:/sys:ro`
- `/var/lib/docker:/var/lib/docker:ro`
- `/dev/disk:/dev/disk:ro`
- `/dev/kmsg:/dev/kmsg`

The service currently uses `privileged: true`, matching the upstream containerized run guidance.
Keep this isolated to the local homelab network and revisit if a narrower configuration is proven to work reliably.

## Validation

Run:

```sh
tools/scripts/check-cadvisor.sh --remote
tools/scripts/check-cadvisor.sh --lan
```

The validation checks startup, restart stability, `/metrics`, cAdvisor metric families, Prometheus target state, and a Prometheus query for container data.

## Future Integration

Grafana dashboards should rely on the Prometheus `cadvisor` job rather than scraping cAdvisor directly.
