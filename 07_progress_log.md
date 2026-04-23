# Progress Log

## Entry Template

Date:
What was done:
Key insight:
LinkedIn post idea:

---

## Entries

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
