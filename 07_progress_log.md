# Progress Log

## Entry Template

Date:
What was done:
Key insight:
LinkedIn post idea:

---

## Entries

Date: 2026-04-23

What was done:
- Added Node Exporter as the first real observability service.
- Deployed it through the existing Docker Compose-based repository workflow.
- Added reusable validation for the deployed host-local metrics endpoint, the host LAN interface, and workstation-to-LAN access.
- Verified that `/metrics` returns Node Exporter host-style metrics for CPU, memory, filesystem, and exporter build info.

Key insight:
Containerized host monitoring needs explicit host namespace and root filesystem access; otherwise the exporter can accidentally describe the container more than the host.

LinkedIn post idea:
Two possible angles: validating monitoring from the user's real LAN path, and why containerized host metrics need explicit host access instead of default container isolation.

Date: 2026-04-23

What was done:
- Added a lightweight observability scaffold for future Prometheus, Grafana, cAdvisor, and Node Exporter checkpoints.
- Added a compose overlay placeholder for observability services.
- Documented config, validation, script, and persistence locations.
- Added a reusable observability scaffold validation script.

Key insight:
A small service-oriented scaffold makes future monitoring checkpoints easier to add without committing to runtime services before the host resource budget is understood.

LinkedIn post idea:
Not yet. This checkpoint is useful engineering groundwork, but it is probably too internal to be a standalone post.

Date: 2026-04-22
What was done: Added a lightweight HTTP smoke-test service to Docker Compose, validated it locally, and verified basic network reachability after deployment.
Key insight: A tiny static HTTP endpoint is enough to validate the end-to-end deployment and LAN accessibility path before adding real infrastructure services.
LinkedIn post idea: From empty Compose baseline to a real LAN-reachable health endpoint with a minimal BusyBox container.

Date: 2026-04-22

What was done:
- Installed Ubuntu Server (minimized)
- Configured static IP (192.168.0.5)
- Enabled SSH access
- Set up SSH key-based authentication
- Disabled password-based SSH login
- Installed Docker and Docker Compose plugin
- Established baseline infrastructure

Key insight:
Starting simple with a clean, Docker-first host reduces future complexity and makes the system easier to reason about.

LinkedIn post idea:
Setting up a production-like local server from scratch and why simplicity beats overengineering in early infrastructure decisions.

Date: 2026-04-23

What was done:
- Reorganized the repository into a clean monorepo layout for docs, apps, services, packages, infra, data, tools, and notebooks.
- Added the wearable-oriented structure for the iOS collector, ingestion API, visualization service, shared schemas, ADRs, and data layers.
- Added canonical transport JSON Schemas for sessions, stream descriptors, upload chunks, acknowledgements, and errors.
- Added payload schemas and examples for Polar HR, Polar PPI, Polar ACC, Muse EEG draft, and Muse PPG draft.
- Added a payload registry and updated wearable documentation to keep ingestion, parsing, and analytics clearly separated.
- Prepared a LinkedIn draft and image prompt for the contract-first wearable ingestion checkpoint.

Key insight:
Defining stable transport contracts before implementing services keeps raw ingestion independent from sensor-specific parsing and makes future sensor expansion less risky.

LinkedIn post idea:
How a contract-first boundary makes a wearable data platform easier to debug, extend, and trust before any ML work begins.
