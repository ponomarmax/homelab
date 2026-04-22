# Constraints

## Hardware

- CPU: Intel i7-10510U
- RAM: 8GB
- Storage: 512GB SSD

---

## Main Constraint

Primary bottleneck:
RAM (8GB)

---

## Resource Strategy

- prefer lightweight services
- avoid unnecessary always-on containers
- monitor memory continuously
- add services gradually

---

## Monitoring Constraints

Prometheus retention should be limited from the start.

Suggested default:
15d retention unless there is a good reason to keep more.

---

## Architecture Constraints

- single-node deployment
- Docker Compose preferred
- no Kubernetes
- avoid distributed complexity

---

## ML Constraints

- no heavy local training
- keep experiments lightweight
- prefer analysis, feature engineering, and prototyping over compute-heavy workloads

---

## Scaling Strategy

If limits are reached:
- reduce retention
- optimize services
- split optional services
- move heavier workloads elsewhere in the future