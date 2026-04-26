# AGENTS.md

You are Codex working inside this repository.

## Project
Single-node homelab platform for infrastructure, observability, Home Assistant, wearable data ingestion, future analytics/ML.

## Hard constraints
- 8GB RAM, 512GB SSD.
- Docker Compose first.
- No Kubernetes.
- Prefer lightweight services.
- Do not add always-on services unless explicitly requested.
- Do not commit secrets, real IPs, hostnames, credentials, or private data.

## Working rules
- Implement only the requested task.
- Do not modify unrelated files.
- Keep code small, readable, and production-like.
- Prefer simple architecture over abstractions.
- If the task changes architecture or adds a service, call it out before implementing.
- Validate changes with the narrowest meaningful test/smoke command.

## Project principles
- Repository-controlled infrastructure.
- Raw-first data ingestion.
- Ingestion must not do normalization, features, LLM calls, or Telegram delivery.
- Stateful services must declare persistence and be validated after recreate.
- A service is not integrated only because the container starts.
- Session summary is the deterministic factual artifact after window features.
- Do not call it night summary unless the task is explicitly sleep/night-specific.
- LLM interpretation, prompt building, report generation, and Telegram delivery belong to a downstream insights/reporting layer.

## Output
Return only:
### Change summary
- Added:
- Changed:
- Not done:

### Validation
- Commands run:
- Result:

### Suggested commit message
`type(scope): summary`