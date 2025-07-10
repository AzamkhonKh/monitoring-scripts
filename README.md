# Monitoring Stack Setup: Prometheus, Grafana, Loki, Promtail

This repository provides scripts and configuration files to quickly set up a monitoring and log aggregation stack using **Prometheus**, **Grafana**, **Loki**, and **Promtail**. The setup is designed for collecting, storing, and visualizing metrics and distributed logs across multiple nodes. **Alerting mechanisms are not included** in this setup.

## Features

- **Prometheus**: Collects and stores metrics from various exporters (Node, Apache, MySQL, Nginx, etc.).
- **Grafana**: Visualizes metrics and logs with customizable dashboards.
- **Loki**: Aggregates and stores logs from distributed nodes.
- **Promtail**: Ships logs from your nodes to Loki.
- **Sample dashboards** and configuration files included for quick start.

## Use Cases

- Easily deploy a monitoring stack for distributed systems.
- Gather and analyze logs from multiple servers in one place.
- Visualize system and application metrics with ready-to-use dashboards.

## Security Notice

**Do not expose monitoring ports to the public internet!**

- Secure all ports (Prometheus, Grafana, Loki, etc.) using firewalls.
- The author used `firewall-cmd` (CentOS/RHEL) and `ufw` (Ubuntu/Debian) to restrict access.

## Getting Started

1. Clone this repository.
2. Review and edit configuration files as needed.
3. Use the provided setup scripts to deploy exporters and the monitoring stack.
4. Import the sample Grafana dashboard for quick visualization.

---

### Docker Compose & Makefile

- The included `docker-compose.yml` is primarily for testing scripts and can be used directly or via the `Makefile`.
- Common tasks (build, up, down, logs, clean, run scripts) are available as Makefile targets for convenience.

---

### Example Observation Stack

This setup was tested with a stack including:

- **Nginx** or **Apache** web server
- **Linux node** (CentOS-based container)
- **MySQL** database

You can adapt the exporters and configurations for similar environments.

## Files Included

- `docker-compose.yml` – Compose file for running the stack.
- `loki-config.yml`, `promtail_sampleconfig.yml` – Loki and Promtail configs.
- `setup_*_exporter.sh` – Scripts to set up various exporters.
- `grafana_loki_apache_access_dashboard.json` – Example Grafana dashboard.
- `Makefile` – Helper commands for setup and management.

## Disclaimer

This project was helpful for setting up distributed monitoring and log aggregation. It may be useful for your needs as well. Contributions and suggestions are welcome!
