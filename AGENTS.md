# AGENTS.md

## Project purpose

This repository contains a local single-node platform that evolves through several layers:

1. infrastructure platform
2. monitoring and observability
3. Home Assistant and smart-home automation
4. environmental data collection
5. wearable physiological data collection
6. backend ingestion and visualization
7. future analytics and ML experiments

This is a production-like portfolio project, not a throwaway hobby setup.

---

## Language rules

Use Ukrainian for communication with the user.

Use English for:
- commit messages
- README content
- changelog / progress entries intended for repo
- LinkedIn post drafts
- public-facing text
- architecture notes that are meant to be published

If unsure:
- internal discussion -> Ukrainian
- anything public or committed -> English

---

## Primary constraints

Host machine:
- Intel i7-10510U
- 8GB RAM
- 512GB SSD

Main limitation:
- RAM is the primary constraint

General rules:
- prefer lightweight solutions
- keep architecture simple
- optimize for single-node deployment
- do not introduce Kubernetes
- do not introduce heavy local ML workloads unless explicitly requested

---

## Source of truth

Before major changes, read and follow these files if they exist:

- 01_vision.md
- 02_architecture.md
- 03_roadmap.md
- 04_constraints.md
- 05_workflow.md
- 06_linkedin_strategy.md
- 07_progress_log.md
- 08_data_strategy.md
- docs/wearable/canonical_contracts.md
- docs/wearable/checkpoints.md
- docs/wearable/hr_mvp_pipeline.md
- docs/wearable/testing_strategy.md
- docs/wearable/time_alignment.md
- docs/repo_structure.md
- docs/observability/README.md

If there is a conflict:
1. 04_constraints.md
2. 02_architecture.md
3. 03_roadmap.md
4. docs/wearable/canonical_contracts.md
5. docs/wearable/hr_mvp_pipeline.md
6. everything else

---

## Working style

For non-trivial tasks:
1. briefly restate the task
2. inspect relevant files
3. propose a short plan
4. implement in small steps
5. verify results
6. summarize what changed

Do not make large structural changes without explaining:
- why the change is needed
- trade-offs
- expected resource impact

---

## Architecture principles

Prefer:
- Docker Compose
- modular services
- isolated networks where useful
- persistent volumes for stateful services
- simple reverse proxy setup
- monitoring from early stages
- one repository for shared docs, shared contracts, collector app, and backend services
- one collector application with multiple sensor adapters
- stable outer transport contracts with flexible sensor-specific payloads
- raw-first ingestion

Avoid:
- overengineering
- unnecessary abstractions
- premature microservice decomposition
- adding tools without a clear operational need
- mixing sensor-specific parsing directly into ingestion when not necessary

---

## Observability working rule

For monitoring and observability tasks:
- read docs/observability/README.md first if it exists
- reuse the established observability scaffolding
- add services incrementally by checkpoint
- validate beyond container startup
- for stateful services, verify persistence after recreate
---

## Wearable direction

Current baseline:
- Polar Verity Sense

Planned extension:
- Muse Athena

Collector direction:
- one iOS collector app
- multiple adapters
- shared transport contracts
- parsing and normalization after ingestion

Before wearable work:
- read the wearable docs first
- keep terminology aligned with the documented pipeline phases

Wearable implementation rules:
- no new services without explicit request
- no agent frameworks
- raw-first principle is mandatory
- each step must be independently verifiable
- do not hardcode HR-only assumptions into long-term architecture

---

## Code and config quality

When writing code, config, or scripts:
- keep files small and readable
- use clear names
- preserve simplicity
- avoid noisy boilerplate
- do not rewrite unrelated files

For YAML / Compose:
- keep service names stable
- use restart policies where appropriate
- use healthchecks when useful
- prefer explicit volumes and networks

---

## Resource awareness

Every proposal should consider:
- memory footprint
- storage growth
- operational complexity

If adding monitoring or storage systems:
- mention retention strategy
- mention expected resource impact

---

## Git workflow

When a task is complete:
1. propose a logical commit split
2. write concise commit messages in English
3. summarize the changes in plain English

Do not create one giant commit if changes can be logically separated.

---

## Required handoff after each logical task

Provide:

### Change summary
- Added:
- Changed:
- Not done:

### Commit plan
- use conventional commit format
- avoid sensitive info to be in commits

### Progress log draft
Date:
What was done:
Key insight:
LinkedIn post idea:

### LinkedIn angles
Provide 2 short ideas for possible LinkedIn posts based on the work.

### Visual ideas
Suggest 1-2 visuals if the work is post-worthy:
- screenshot
- diagram
- graph
- before/after comparison

If the task is not post-worthy, say so explicitly.

---

## Safety / decision rules

If requirements are unclear:
- prefer the simplest solution consistent with the roadmap

If a task would significantly change architecture:
- stop and ask for confirmation before implementing

If a change may exceed hardware limits:
- explicitly warn about RAM / storage impact
