tree -L 3 -I ".git|node_modules|venv|.venv|__pycache__|.pytest_cache|data|dist|build"
.
├── 01_vision.md
├── 02_architecture.md
├── 03_roadmap.md
├── 04_constraints.md
├── 05_workflow.md
├── 06_linkedin_strategy.md
├── 07_progress_log.md
├── 08_data_strategy.md
├── 09_infra_baseline.md
├── 10_server_change_log.md
├── AGENTS.light.md
├── AGENTS.md
├── Makefile
├── README.md
├── apps
│   └── ios-collector
│       ├── CollectorApp
│       ├── CollectorAppTests
│       ├── Podfile
│       ├── Podfile.lock
│       ├── Pods
│       ├── README.md
│       ├── ios-collector.xcodeproj
│       └── ios-collector.xcworkspace
├── content
│   └── linkedin
│       ├── assets
│       ├── drafts
│       └── posts
├── docs
│   ├── adr
│   │   └── ADR-001-monorepo-and-collector.md
│   ├── context
│   │   ├── codex_rules.md
│   │   └── prompt_templates.md
│   ├── infra
│   │   └── README.md
│   ├── observability
│   │   ├── README.md
│   │   └── health-layer.md
│   ├── repo_structure.md
│   └── wearable
│       ├── README.md
│       ├── canonical_contracts.md
│       ├── checkpoints.md
│       ├── hr_mvp_pipeline.md
│       ├── muse_athena.md
│       ├── payload_registry.md
│       ├── polar_verity_sense.md
│       ├── testing_strategy.md
│       └── time_alignment.md
├── hr-samples-6547A356-4489-45A6-AB09-D739013CCD5E.jsonl
├── infra
│   ├── README.md
│   ├── compose
│   │   ├── docker-compose.yml
│   │   ├── observability.yml
│   │   └── smoke
│   ├── env
│   │   └── README.md
│   └── observability
│       ├── README.md
│       ├── config
│       ├── scripts
│       └── validation
├── notebooks
│   └── README.md
├── packages
│   └── schemas
│       ├── README.md
│       ├── examples
│       ├── payloads
│       └── transport
├── prompt.summary.md
├── services
│   ├── visualization
│   │   └── README.md
│   └── wearable-ingestion-api
│       ├── Dockerfile
│       ├── README.md
│       ├── app.py
│       ├── requirements.txt
│       ├── scripts
│       ├── tests
│       └── wearable_ingestion_api
└── tools
    ├── README.md
    └── scripts
        ├── check-cadvisor.sh
        ├── check-grafana.sh
        ├── check-node-exporter.sh
        ├── check-observability.sh
        ├── check-prometheus.sh
        ├── check.sh
        ├── deploy.sh
        ├── logs.sh
        ├── ssh.sh
        ├── validate-json.sh
        └── validate-wearable-ingestion-api.sh