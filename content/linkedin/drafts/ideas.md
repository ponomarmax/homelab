# LinkedIn Ideas

- future post ideas
- hooks
- experiments

## OBS-001 — Validate From The Real User Path

Idea:
Do not stop at `localhost` when validating infrastructure. For a homelab service, the meaningful check is whether the endpoint works from the machine and network path where it will actually be used.

Hook:
`localhost` said my monitoring endpoint worked. The LAN check was the real validation.

Use later when:
Prometheus is scraping Node Exporter or the first Grafana dashboard is available.

## OBS-002 — Containerized Host Metrics Are A Deliberate Boundary

Idea:
Running Node Exporter in Docker is lightweight and reproducible, but host metrics are only meaningful when the container gets explicit host namespace and root filesystem access.

Hook:
A host metrics exporter inside Docker can accidentally monitor the container more than the host.

Use later when:
The observability stack includes Prometheus and the host metrics path can be shown end to end.
