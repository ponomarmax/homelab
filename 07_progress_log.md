# Progress Log

## Entry Template

Date:
What was done:
Key insight:
LinkedIn post idea:

---

## Entries

Date: 2026-04-25

What was done:
- Deployed the latest wearable ingestion contract-boundary refactor with the existing Docker Compose workflow.
- Updated deployment validation to assert the new opaque payload behavior: valid generic payload accepted, valid HR payload accepted, payload without `samples` accepted, and malformed transport envelope rejected.
- Verified deployed raw JSONL persistence preserves payloads exactly as received, including sample-level `received_at_collector` for HR samples.
- Revalidated ingestion unit/contract tests and schema/example JSON checks before deployment.

Key insight:
Boundary-safe deployment validation should test transport correctness and raw preservation, not sensor-specific payload semantics.

LinkedIn post idea:
How contract-boundary validation in production catches the right failures while keeping ingestion sensor-agnostic.

Date: 2026-04-24

What was done:
- Extended the iOS collector mock HR flow so a running mock session now produces explicit session metadata, stream descriptors, and transport-ready upload chunk payloads.
- Added chunk preparation inside the collector core while keeping the flow mock-only and simulator-runnable.
- Expanded the collector UI diagnostics to show buffered samples and prepared chunk status without adding backend calls or complex UI.
- Added tests for session creation, sample sequencing, buffered sample counting, chunk contents, timestamp preservation, and session stop timestamps.

Key insight:
Preparing structured chunks before real backend integration makes the collector boundary concrete early, while keeping timestamp ownership and canonical alignment in the later normalizer.

LinkedIn post idea:
Two possible angles: using a mock wearable stream to lock down a transport-ready session/chunk model before backend work, and why traceable timestamp fields matter even before real device integration.

Date: 2026-04-24

What was done:
- Added the initial iOS collector Xcode project with a runnable SwiftUI app target and unit test target.
- Implemented the first collector skeleton layers: UI, collector core, device adapter abstraction, stream provider abstraction, and transport placeholder.
- Added a mock device adapter and mock HR stream so the app can run in simulator without Polar SDK, BLE, or backend integration.
- Added collector tests covering mock sample emission, session start/stop, latest HR updates, sample counting, default live mode, and timestamp metadata representation.
- Prepared LinkedIn-ready content for the checkpoint, including a post draft and an image-generation prompt to pair with the simulator demo recording.

Key insight:
Getting a simulator-runnable mock stream into the collector first makes the session lifecycle and UI testable before the BLE and backend edges introduce harder debugging paths.

LinkedIn post idea:
Two possible angles: building an iOS wearable collector from the inside out with mock streams first, and why simulator-first validation reduces risk before BLE integration.

Date: 2026-04-24

What was done:
- Added the HR MVP wearable pipeline architecture document as the pre-implementation source of truth.
- Added dedicated documentation for wearable time alignment and testing strategy.
- Updated vision, architecture, roadmap, data strategy, and agent instructions to align on the same HR MVP terminology and artifact boundaries.
- Documented the target service topology, storage layout, extensibility model, and future environment-data compatibility without changing runtime behavior.

Key insight:
Locking down artifact boundaries, timestamp rules, and deterministic pipeline responsibilities before implementation reduces future rework and keeps the ingestion boundary clean.

LinkedIn post idea:
Two possible angles: documenting a wearable pipeline as architecture before writing code, and why raw-first plus deterministic nightly artifacts make later AI layers easier to trust.

Date: 2026-04-23

What was done:
- Added repository-controlled baseline Grafana dashboards for host and container metrics.
- Added dashboard provisioning that loads JSON dashboards from the Grafana dashboards directory.
- Organized dashboards into host and containers folders for future extension.
- Extended Grafana validation to confirm provisioned dashboards and real host/container Prometheus query results through Grafana.

Key insight:
Dashboards become operational infrastructure when they are provisioned from versioned JSON and validated through the real Grafana-to-Prometheus data path.

LinkedIn post idea:
Two possible angles: turning Grafana dashboards into reproducible infrastructure, and validating dashboards by querying the same metrics their panels use.

Date: 2026-04-23

What was done:
- Added Grafana as the observability UI layer.
- Added a Docker named volume for Grafana state.
- Provisioned Prometheus as the default Grafana datasource from repository-controlled config.
- Added reusable validation for Grafana health, datasource provisioning, Prometheus query through Grafana, LAN access, and persistence after recreate.

Key insight:
Grafana becomes reproducible when the datasource and state strategy are defined in the repository instead of relying on manual UI setup.

LinkedIn post idea:
Two possible angles: why dashboards should come after validated metrics storage, and how provisioning turns Grafana from a manual UI into reproducible infrastructure.

Date: 2026-04-23

What was done:
- Added cAdvisor as the container metrics source for the observability layer.
- Integrated cAdvisor with the existing Prometheus scrape configuration.
- Moved the temporary smoke-test endpoint off the default cAdvisor port so cAdvisor can use the expected LAN port.
- Added reusable validation for cAdvisor `/metrics`, Prometheus target state, and a container metric query.
- Kept cAdvisor stateless and documented the host/Docker runtime mounts it needs.

Key insight:
Container observability needs explicit Docker runtime access; validating cAdvisor directly and through Prometheus confirms the path from container runtime to time-series storage before adding dashboards.

LinkedIn post idea:
Two possible angles: why container metrics need careful host mounts, and how to validate the metrics pipeline before building Grafana dashboards.

Date: 2026-04-23

What was done:
- Added Prometheus as the first stateful observability storage service.
- Configured Prometheus to scrape itself and the existing Node Exporter target.
- Added explicit Prometheus retention of 15 days.
- Added a named Docker volume for Prometheus TSDB data.
- Added reusable validation for Prometheus health, Node Exporter scrape state, query results, LAN access, and persistence after recreate.

Key insight:
Prometheus should be treated as stateful from the first checkpoint; validating scrape results and TSDB persistence is more useful than only checking that the container is running.

LinkedIn post idea:
Two possible angles: why retention belongs in the first Prometheus commit, and how to validate observability storage before adding dashboards.

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
