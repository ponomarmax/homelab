# Codex Rules

## Language
- User-facing explanations: Ukrainian.
- Code, docs, README, commits, progress logs: English.

## Development
- Python: small modules, explicit boundaries, typed where useful, no heavy dependencies without need.
- iOS: separate UI, collector core, device adapter, and transport.
- Avoid rewriting core logic when adding devices or streams.
- Keep mock/test paths available where hardware is not required.

## Testing
- Verify behavior, not only that code runs.
- Prefer small deterministic fixtures.
- Use synthetic fixtures for unit/contract tests.
- Use sanitized real fixtures only when needed.
- Do not commit private real data.

## Deployment
- Use Docker Compose.
- Config lives in repository-controlled files.
- Runtime secrets and host-specific values stay in local `.env`.
- Stateful services need explicit volumes/bind mounts.
- Validate endpoint/UI/functionality/persistence as relevant.

## Wearable pipeline
MVP flow:
Polar HR -> iOS Collector -> ingestion API -> raw JSONL -> pipeline processing -> clean Parquet -> window features -> session summary JSON -> insights/report MD -> communication delivery.

Rules:
- Raw JSONL is append-only truth.
- `ts_utc` is introduced only during normalization.
- Normalizer expands batches but does not aggregate.
- Features are the first aggregation layer.
- Add new streams through handlers, not pipeline rewrites.
- Session summary is deterministic and non-LLM.
- Use `session_summary` instead of `nightly_summary` unless the task is explicitly sleep/night-specific.
- LLM interpretation, prompt building, response validation, report generation, and Telegram delivery belong to a downstream insights/reporting layer.
- Notebooks and ML experiments are exploration layers and must not be required for the production pipeline.

## Handoff
Keep the final answer short:
- change summary
- validation
- suggested conventional commit


PYTHON ENGINEERING STANDARDS

Якщо задача стосується Python backend service, API, ML pipeline або processing pipeline:

1. Architecture
- follow clean, layered structure
- separate API / domain logic / pipeline steps / storage / config / schemas
- avoid putting business logic directly in route handlers
- keep ingestion, normalization, feature building, reporting, and delivery as separate responsibilities
- keep functions small, typed, and testable

2. Web services
- use production-like patterns for Python web services
- validate inputs explicitly
- return clear error responses
- keep service configuration environment-based
- avoid hardcoded paths, ports, secrets, hostnames, or private data

3. Pipelines
- pipeline steps must be independently runnable and testable
- prefer deterministic processing before any LLM/AI interpretation
- verify produced artifacts, not only that the process finished
- preserve raw data before normalization or aggregation
- keep timestamp normalization separate from ingestion

4. Tests
- add or update tests for changed behavior
- prefer unit, contract, artifact, and smoke tests depending on task
- keep fixtures small and deterministic
- do not commit private real data
- validation should include exact commands and results

5. Local development
- if running Python locally, use a virtual environment
- document needed commands when relevant
- do not assume globally installed Python packages
- keep dependency changes minimal and justified

6. Logging
- use standard Python logging, not print, for services and pipelines
- log meaningful lifecycle events, validation failures, pipeline step starts/completions, artifact paths, and errors
- avoid logging secrets, private host details, tokens, raw personal data, or large payloads
- keep logs console-friendly by default
- make log level configurable through environment variables
- design logging so it can later be collected centrally from Docker/container logs

7. Output
- keep implementation small and production-like
- do not overengineer abstractions before they are needed
- explain any new structure briefly in the handoff