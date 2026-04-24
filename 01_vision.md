# Vision

## Purpose

This project is a real-world engineering system that combines:
- local infrastructure
- smart home automation
- environmental data collection
- wearable physiological data collection
- future neural / multimodal sensor collection
- data analysis
- future ML experimentation

The goal is not to build a hobby setup, but a production-like system with clear architecture, constraints, and evolution.

---

## Career Goal

Primary goal:
transition from Backend Engineering (.NET, distributed systems) to AI / ML Engineering.

Strategy:
- build a real system instead of toy projects
- use real-world personal and environmental data
- demonstrate end-to-end ownership:
  - infrastructure
  - monitoring
  - data collection
  - mobile collector development
  - backend ingestion
  - storage
  - visualization
  - analytics
  - future ML experiments

---

## System Vision

This project evolves through several connected layers:

1. Infrastructure platform
2. Monitoring and observability
3. Home Assistant and automations
4. Environmental data collection
5. Wearable collector platform
6. Backend ingestion and storage
7. Visualization and validation
8. Correlation analysis
9. Future ML experimentation

---

## Wearable Vision

A single collector application should receive data from supported wearable sensors, map them into shared transport contracts, and upload them to backend services.

Initial baseline:
- Polar Verity Sense for cardio and motion data

Planned extension:
- Muse Athena for neural and experimental multimodal data

The system should support:
- online live collection
- future offline recording
- future imported data flows
- raw data retention
- normalized analytical layers
- future feature extraction and ML experimentation

Near-term MVP architecture:
- Polar Verity Sense HR only
- iOS Collector -> ingestion API -> raw JSONL -> nightly orchestrator
- deterministic normalization, feature building, and nightly summary
- LLM interpretation only after deterministic summary artifacts exist

---

## End Goal

A fully integrated system that:
- collects environmental and physiological data
- supports multiple wearable sensors through one collector architecture
- keeps raw ingestion separate from normalization, features, and reporting
- supports session-based wearable data and future continuous environment data
- correlates sleep and physiological patterns with room conditions
- enables future experimentation with ML models on real personal data

---

## Key Principles

- production-like architecture on a local machine
- simplicity over complexity
- iterative development
- visible progress and measurable checkpoints
- raw data is always retained
- ingestion is separate from parsing and analysis
- pipeline steps should remain independently verifiable
- portfolio-first mindset
