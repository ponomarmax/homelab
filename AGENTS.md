## Project purpose

This repository contains a local single-node platform evolving across:

- infrastructure
- observability
- smart home / Home Assistant
- environment data
- wearable data
- backend ingestion
- future analytics / ML

Production-like portfolio project.

---

## Language rules

Use Ukrainian for communication with the user.

Use English for:
- commit messages
- README
- progress logs
- architecture docs

---

## Constraints

Host:
- Intel i7-10510U
- 8GB RAM
- 512GB SSD

Rules:
- prefer lightweight solutions
- simple architecture
- single-node optimized
- no Kubernetes
- no heavy ML unless requested

---

## Source of truth (priority)

1. 04_constraints.md
2. 02_architecture.md
3. 03_roadmap.md
4. docs/wearable/canonical_contracts.md
5. docs/wearable/hr_mvp_pipeline.md

---

## Working style

For non-trivial tasks:

1. restate task briefly
2. inspect relevant files
3. propose short plan
4. implement in small steps
5. verify results
6. provide concise summary

---

## Architecture principles

Prefer:
- Docker Compose
- modular services
- raw-first ingestion
- stable transport contracts
- single collector app with adapters

Avoid:
- overengineering
- premature microservices
- unnecessary abstractions

---

## Wearable rules

- no new services without request
- no agent frameworks
- raw-first principle
- each step must be verifiable
- no HR-only assumptions in long-term design

---

## Code quality

- keep code small and readable
- no boilerplate noise
- do not modify unrelated files

---

## Resource awareness

Always consider:
- RAM
- storage
- operational complexity

---

## Git workflow

After task:
- provide concise change summary
- suggest commit message (single or multiple if obvious)

Do NOT:
- over-split commits unless clearly needed
- generate large commit plans automatically

---

## REQUIRED HANDOFF (minimal)

Provide ONLY:

### Change summary
- Added
- Changed
- Not done

### Suggested commit message

Keep it short.

---

## ON-DEMAND SUMMARY MODE

Only when explicitly requested (e.g. "generate summary"):

Provide:
- detailed change summary
- logical commit split
- progress log
- LinkedIn ideas

Do NOT generate this by default.

---

## Safety rules

If unclear:
- choose simplest solution

If architecture impact:
- stop and ask

If resource risk:
- warn explicitly