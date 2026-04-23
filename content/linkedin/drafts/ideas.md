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

## OBS-003 — Retention Belongs In The First Prometheus Commit

Idea:
Prometheus is easy to start, but on a small single-node host it should be bounded from day one. Retention is part of the architecture, not a cleanup task for later.

Hook:
The first Prometheus decision I made was not a dashboard. It was retention.

Use later when:
Grafana is available and the post can show the full path from scrape target to stored metric to dashboard.

## OBS-004 — Validate The Time-Series Store Before The Dashboard

Idea:
Before adding Grafana, validate that Prometheus is actually scraping Node Exporter, answering `up` queries, writing TSDB data, and surviving a recreate.

Hook:
A monitoring UI is only useful if the time-series store underneath is already trustworthy.

Use later when:
Prometheus is paired with the first Grafana dashboard and the end-to-end validation story is visible.

## OBS-005 — Container Metrics Need Deliberate Host Access

Idea:
cAdvisor is simple to run, but meaningful container metrics require explicit access to Docker runtime paths and host system views. That access should be documented and validated, not hidden in a compose file.

Hook:
Container metrics are not magic. They come from very specific host access.

Use later when:
Grafana dashboards can show container CPU, memory, filesystem, and network metrics collected through Prometheus.

## OBS-006 — Validate The Pipeline Before The Dashboard

Idea:
Before adding Grafana, validate that cAdvisor serves metrics, Prometheus scrapes it, and container metrics are queryable through the Prometheus API.

Hook:
I added container monitoring without a dashboard first, on purpose.

Use later when:
The first Grafana dashboard completes the observability pipeline visually.

## OBS-007 — Provisioning Turns Grafana Into Infrastructure

Idea:
Grafana becomes reproducible when datasources are provisioned from repository config instead of being clicked into place manually.

Hook:
The first Grafana milestone was not a dashboard. It was a provisioned datasource.

Use later when:
The first dashboards rely on the provisioned Prometheus datasource.

## OBS-008 — Validate The UI Through The Data Path

Idea:
A Grafana login page is not enough validation. The stronger check is whether Grafana can query existing Prometheus data through its provisioned datasource.

Hook:
I did not validate Grafana by opening the login page. I made it query Prometheus.

Use later when:
Showing the full path from exporter to Prometheus to Grafana.

## OBS-009 — Dashboards As Code Beat ClickOps

Idea:
A dashboard is infrastructure when it is stored as JSON, provisioned by Grafana, and recreated without manual UI work.

Hook:
The first useful Grafana dashboards in my homelab were not clicked together. They were committed.

Use later when:
Showing host and container dashboards side by side.

## OBS-010 — Validate Dashboards By Their Queries

Idea:
Dashboard validation should check that provisioned panels can query real Prometheus data, not just that the dashboard title appears in Grafana.

Hook:
I did not stop when the dashboard appeared. I validated the PromQL behind it.

Use later when:
Explaining how the observability stack became trustworthy end to end.
