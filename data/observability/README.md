# Observability Runtime Data

This directory documents the fallback location for observability runtime data during development or migration.

Default expectation:

- use Docker named volumes for Prometheus and Grafana runtime state
- do not commit generated time-series data, databases, or local Grafana state

Expected stateful services later:

- `prometheus/` - Prometheus time-series database if a bind mount is explicitly chosen.
- `grafana/` - Grafana runtime state if a bind mount is explicitly chosen.

Keep large or sensitive runtime data out of Git.
