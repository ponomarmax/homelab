# Repository Structure

## Direction

Keep one repository.
Separate concerns with directories, not with multiple repositories at this stage.

## Top-level structure

```text
docs/
apps/
services/
packages/
infra/
data/
tools/
notebooks/
```

## Directory roles

### docs/
Project documentation, ADRs, wearable notes, repo structure, and roadmap context.

### apps/
Client applications.

Current planned app:
- `apps/ios-collector/`

The collector direction is one app with multiple sensor adapters.

### services/
Backend services.

Current planned services:
- `services/ingestion-api/`
- `services/visualization/`

Ingestion and visualization are separated so raw acceptance does not depend on parsing, charts, or analytics.

### packages/
Shared contracts and future reusable code.

Current package area:
- `packages/schemas/`

Transport schemas and payload schemas are kept separate.

### infra/
Docker-first infrastructure and environment documentation.

Current areas:
- `infra/compose/`
- `infra/env/`

### data/
Local data landing zones.

Expected layers:
- `data/raw/`
- `data/normalized/`
- `data/derived/`

Large datasets and sensitive personal data should not be committed.

### tools/
Repository helper scripts and validation utilities.

Current area:
- `tools/scripts/`

### notebooks/
Future lightweight exploratory analysis.

Avoid heavy local training workloads because RAM is the primary host constraint.
