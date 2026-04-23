# Node Exporter Config

Node Exporter exposes host CPU, memory, filesystem, network, and kernel metrics for future Prometheus scraping.

## Deployment

Node Exporter runs from `infra/compose/observability.yml` using Docker Compose.

Deploy through the repository workflow:

```sh
tools/scripts/deploy.sh node-exporter --confirm
```

The container uses:

- `network_mode: host` so network metrics and the HTTP listener are host-oriented.
- `pid: host` so process and kernel metrics reflect the host namespace.
- `/:/host:ro,rslave` with `--path.rootfs=/host` so filesystem collectors read the host root filesystem.

The service is stateless and does not need persistent storage.

## Validation

Run:

```sh
tools/scripts/check-node-exporter.sh --remote
tools/scripts/check-node-exporter.sh --lan
```

The remote validation checks compose syntax, starts the service, confirms the container is running, reaches host-local `/metrics`, reaches the host LAN interface from the server itself, and verifies host-style `node_*` metrics are present.

The LAN validation checks the endpoint from the workstation side using `NODE_EXPORTER_LAN_HOST`.

Set `NODE_EXPORTER_LAN_HOST` in `.env` when the browser/LAN address differs from `SERVER_IP`.

For a Linux machine with local Docker access, the same script can run without `--remote`.

## Future Integration

Prometheus should scrape Node Exporter on the homelab host port `${NODE_EXPORTER_PORT:-9100}`.
The validation uses the host-local endpoint `localhost:${NODE_EXPORTER_PORT:-9100}` over SSH, the server's own LAN interface, and optionally `${NODE_EXPORTER_LAN_HOST:-SERVER_IP}:${NODE_EXPORTER_PORT:-9100}` from the workstation.
Keep additional collectors disabled unless a later checkpoint documents a concrete need and resource impact.
