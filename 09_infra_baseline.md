# Infrastructure Baseline

## Host

- hostname: documented in local `.env`
- user: documented in local `.env`
- ip: documented in local `.env`

## System

- OS: Ubuntu Server (minimized)
- installation: fresh, full disk
- filesystem: ext4
- ssh: enabled
- authentication: key-based

## Networking

- static IPv4 configured
- local network only (no external exposure yet)

## Software

- Docker installed
- Docker Compose plugin installed
- snap packages: not used

## Principles

- Docker-first approach
- no system-level services unless necessary
- minimal base system
- infrastructure controlled via repository

## Notes

This host is the single-node foundation for the entire system.
All future services must be deployed via Docker Compose.
Public repository note:
keep real host identifiers, addresses, and private operational details out of version control.
