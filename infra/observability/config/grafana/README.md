# Grafana Config

Future Grafana configuration belongs here.

Expected directories later:

- `dashboards/` - versioned dashboard JSON files.
- `provisioning/` - data source and dashboard provisioning files.

Grafana is stateful. Use a Docker volume for runtime state unless a future checkpoint documents a reason to use a bind mount.
