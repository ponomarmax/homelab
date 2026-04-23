# Tools

Helper scripts for local validation and deployment workflows.

Current scripts live in `tools/scripts/`.

Current validation entry points:

- `tools/scripts/check.sh` - base infrastructure compose validation.
- `tools/scripts/check-observability.sh` - observability scaffold validation.
- `tools/scripts/check-node-exporter.sh` - Node Exporter runtime and metrics validation, with `--remote` for the deployed homelab host and `--lan` for workstation-to-LAN validation.
