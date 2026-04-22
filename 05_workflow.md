# Workflow

## Core Principle

Separate thinking from execution.

- ChatGPT -> strategy, planning, architecture, LinkedIn
- Codex -> implementation inside the repository

---

## Chat Types

### 1. Infrastructure chat
Used for:
- Docker
- networking
- monitoring
- Home Assistant setup

### 2. Data chat
Used for:
- data collection
- APIs
- storage design
- integrations

### 3. ML chat
Used for:
- feature engineering
- analysis
- experiment planning

### 4. LinkedIn chat
Used for:
- post drafts
- positioning
- content planning

---

## Rule

One logical task -> one chat.

Do not mix:
- implementation
- ML analysis
- LinkedIn writing
in the same chat unless truly necessary.

---

## Standard Development Loop

1. implement a task in Codex
2. request final handoff
3. review commit split
4. commit changes
5. update 07_progress_log.md
6. if checkpoint is meaningful, create LinkedIn post draft in GPT

---

## Language Workflow

- internal discussions with AI -> Ukrainian
- public outputs -> English

---

## Repository Update Rule

The repository is the canonical source of truth.

If strategy or architecture changes:
- update repo docs first
- sync to GPT Project if needed

---

## Post Creation Rule

Create LinkedIn posts only after meaningful checkpoints:
- repo initialized
- monitoring stack running
- Home Assistant running
- first sensor integrated
- first automation working
- first useful analysis completed

## Infrastructure Rule

All host-level changes should be:
- reproducible
- documented
- ideally reflected in repository scripts


Avoid manual one-off changes without documentation.

All remote server changes must be either:
- executed through repo scripts
- logged in 10_server_change_log.md
