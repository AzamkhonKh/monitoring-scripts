#!/bin/bash

# Loki Stack Setup Script (Promtail, Loki, Grafana)
# Author: System Administrator
# Description: Installs and configures Promtail, Loki, and Grafana for log aggregation and visualization
# Usage: ./setup_loki_stack.sh [OPTIONS]

set -euo pipefail

# Default versions
DEFAULT_LOKI_VERSION="2.9.4"
DEFAULT_PROMTAIL_VERSION="$DEFAULT_LOKI_VERSION"
DEFAULT_GRAFANA_VERSION="11.0.0"

# Default ports and paths
DEFAULT_LOKI_PORT="3100"
DEFAULT_GRAFANA_PORT="3000"
DEFAULT_INSTALL_DIR="/opt/loki_stack"
DEFAULT_LOKI_CONFIG="/etc/loki/loki-config.yaml"
DEFAULT_PROMTAIL_CONFIG="/etc/promtail/promtail-config.yaml"
DEFAULT_GRAFANA_DATA_DIR="/var/lib/grafana"
DEFAULT_GRAFANA_ADMIN_USER="admin"
DEFAULT_GRAFANA_ADMIN_PASSWORD="admin"

# Script variables (can be overridden by parameters)
LOKI_VERSION="${LOKI_VERSION:-$DEFAULT_LOKI_VERSION}"
PROMTAIL_VERSION="${PROMTAIL_VERSION:-$DEFAULT_PROMTAIL_VERSION}"
GRAFANA_VERSION="${GRAFANA_VERSION:-$DEFAULT_GRAFANA_VERSION}"
LOKI_PORT="${LOKI_PORT:-$DEFAULT_LOKI_PORT}"
GRAFANA_PORT="${GRAFANA_PORT:-$DEFAULT_GRAFANA_PORT}"
INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
LOKI_CONFIG="${LOKI_CONFIG:-$DEFAULT_LOKI_CONFIG}"
PROMTAIL_CONFIG="${PROMTAIL_CONFIG:-$DEFAULT_PROMTAIL_CONFIG}"
GRAFANA_DATA_DIR="${GRAFANA_DATA_DIR:-$DEFAULT_GRAFANA_DATA_DIR}"
GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-$DEFAULT_GRAFANA_ADMIN_USER}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-$DEFAULT_GRAFANA_ADMIN_PASSWORD}"
DRY_RUN=false
FORCE_INSTALL=false
VERBOSE=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_verbose() { [[ "$VERBOSE" == "true" ]] && echo -e "${BLUE}[VERBOSE]${NC} $1"; }

usage() {
    cat << EOF
Loki Stack Setup Script (Promtail, Loki, Grafana)

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --loki-version VERSION         Loki version (default: $DEFAULT_LOKI_VERSION)
    --promtail-version VERSION     Promtail version (default: $DEFAULT_PROMTAIL_VERSION)
    --grafana-version VERSION      Grafana version (default: $DEFAULT_GRAFANA_VERSION)
    --loki-port PORT               Loki port (default: $DEFAULT_LOKI_PORT)
    --grafana-port PORT            Grafana port (default: $DEFAULT_GRAFANA_PORT)
    --install-dir DIR              Base install directory (default: $DEFAULT_INSTALL_DIR)
    --loki-config PATH             Loki config file (default: $DEFAULT_LOKI_CONFIG)
    --promtail-config PATH         Promtail config file (default: $DEFAULT_PROMTAIL_CONFIG)
    --grafana-data-dir DIR         Grafana data dir (default: $DEFAULT_GRAFANA_DATA_DIR)
    --grafana-admin-user USER      Grafana admin user (default: $DEFAULT_GRAFANA_ADMIN_USER)
    --grafana-admin-password PASS  Grafana admin password (default: $DEFAULT_GRAFANA_ADMIN_PASSWORD)
    --dry-run                      Show what would be done without executing
    --force                        Force installation even if already installed
    --verbose                      Enable verbose output
    -h, --help                     Show this help message

EXAMPLES:
    $0 --grafana-admin-password mysecret
    $0 --loki-version 2.9.4 --grafana-version 11.0.0
EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --loki-version) LOKI_VERSION="$2"; shift 2;;
            --promtail-version) PROMTAIL_VERSION="$2"; shift 2;;
            --grafana-version) GRAFANA_VERSION="$2"; shift 2;;
            --loki-port) LOKI_PORT="$2"; shift 2;;
            --grafana-port) GRAFANA_PORT="$2"; shift 2;;
            --install-dir) INSTALL_DIR="$2"; shift 2;;
            --loki-config) LOKI_CONFIG="$2"; shift 2;;
            --promtail-config) PROMTAIL_CONFIG="$2"; shift 2;;
            --grafana-data-dir) GRAFANA_DATA_DIR="$2"; shift 2;;
            --grafana-admin-user) GRAFANA_ADMIN_USER="$2"; shift 2;;
            --grafana-admin-password) GRAFANA_ADMIN_PASSWORD="$2"; shift 2;;
            --dry-run) DRY_RUN=true; shift;;
            --force) FORCE_INSTALL=true; shift;;
            --verbose) VERBOSE=true; shift;;
            -h|--help) usage; exit 0;;
            *) log_error "Unknown option: $1"; usage; exit 1;;
        esac
    done
}

check_root() {
    if [[ $EUID -ne 0 && "$DRY_RUN" == "false" ]]; then
        log_error "This script must be run as root (use sudo)"; exit 1
    fi
}

install_dependencies() {
    if [[ "$DRY_RUN" == "true" ]]; then log_info "[DRY RUN] Would install dependencies"; return; fi
    log_info "Installing dependencies (curl, tar, systemd, useradd, wget, etc.)"
    if command -v apt-get &>/dev/null; then
        apt-get update && apt-get install -y curl tar wget systemd
    elif command -v yum &>/dev/null; then
        yum install -y curl tar wget systemd
    elif command -v dnf &>/dev/null; then
        dnf install -y curl tar wget systemd
    else
        log_warning "Unknown package manager. Please ensure curl, tar, wget, and systemd are installed."
    fi
}

create_user() {
    local user="$1"
    if [[ "$DRY_RUN" == "true" ]]; then log_info "[DRY RUN] Would create user: $user"; return; fi
    if ! id "$user" &>/dev/null; then
        useradd --no-create-home --shell /bin/false "$user"
        log_success "User $user created"
    else
        log_info "User $user already exists"
    fi
}

download_and_install_loki() {
    local arch; arch=$(uname -m)
    case $arch in
        x86_64) arch="amd64";;
        aarch64) arch="arm64";;
        armv7l) arch="armv7";;
        *) log_error "Unsupported architecture: $arch"; exit 1;;
    esac
    local url="https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/loki-linux-${arch}.zip"
    local dir="$INSTALL_DIR/loki"
    if [[ "$DRY_RUN" == "true" ]]; then log_info "[DRY RUN] Would download Loki from $url to $dir"; return; fi
    mkdir -p "$dir"
    cd "$dir"
    wget -q "$url" -O loki.zip
    unzip -o loki.zip
    chmod +x loki-linux-${arch}
    mv loki-linux-${arch} loki
    ln -sf "$dir/loki" /usr/local/bin/loki
    log_success "Loki installed at $dir/loki"
}

download_and_install_promtail() {
    local arch; arch=$(uname -m)
    case $arch in
        x86_64) arch="amd64";;
        aarch64) arch="arm64";;
        armv7l) arch="armv7";;
        *) log_error "Unsupported architecture: $arch"; exit 1;;
    esac
    local url="https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/promtail-linux-${arch}.zip"
    local dir="$INSTALL_DIR/promtail"
    if [[ "$DRY_RUN" == "true" ]]; then log_info "[DRY RUN] Would download Promtail from $url to $dir"; return; fi
    mkdir -p "$dir"
    cd "$dir"
    wget -q "$url" -O promtail.zip
    unzip -o promtail.zip
    chmod +x promtail-linux-${arch}
    mv promtail-linux-${arch} promtail
    ln -sf "$dir/promtail" /usr/local/bin/promtail
    log_success "Promtail installed at $dir/promtail"
}

download_and_install_grafana() {
    if [[ "$DRY_RUN" == "true" ]]; then log_info "[DRY RUN] Would install Grafana"; return; fi
    if command -v apt-get &>/dev/null; then
        wget -q -O - https://packages.grafana.com/gpg.key | apt-key add -
        echo "deb https://packages.grafana.com/oss/deb stable main" > /etc/apt/sources.list.d/grafana.list
        apt-get update && apt-get install -y grafana="$GRAFANA_VERSION-1"
    elif command -v yum &>/dev/null; then
        cat <<EOF > /etc/yum.repos.d/grafana.repo
[grafana]
name=Grafana OSS
baseurl=https://packages.grafana.com/oss/rpm
enabled=1
gpgcheck=1
gpgkey=https://packages.grafana.com/gpg.key
EOF
        yum install -y grafana-$GRAFANA_VERSION-1
    elif command -v dnf &>/dev/null; then
        dnf install -y https://dl.grafana.com/oss/release/grafana-$GRAFANA_VERSION-1.x86_64.rpm
    else
        log_warning "Unknown package manager. Please install Grafana manually."
    fi
    log_success "Grafana installed"
}

create_loki_config() {
    if [[ "$DRY_RUN" == "true" ]]; then log_info "[DRY RUN] Would create Loki config at $LOKI_CONFIG"; return; fi
    mkdir -p "$(dirname $LOKI_CONFIG)"
    cat > "$LOKI_CONFIG" <<EOF
auth_enabled: false
server:
  http_listen_port: $LOKI_PORT
  grpc_listen_port: 0
common:
  path: /tmp/loki
  storage:
    filesystem:
      chunks_directory: /tmp/loki/chunks
      rules_directory: /tmp/loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory
schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h
storage_config:
  boltdb_shipper:
    active_index_directory: /tmp/loki/index
    cache_location: /tmp/loki/boltdb-cache
    shared_store: filesystem
  filesystem:
    directory: /tmp/loki/chunks
limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h
chunk_store_config:
  max_look_back_period: 0s
EOF
    log_success "Loki config created at $LOKI_CONFIG"
}

create_promtail_config() {
    if [[ "$DRY_RUN" == "true" ]]; then log_info "[DRY RUN] Would create Promtail config at $PROMTAIL_CONFIG"; return; fi
    mkdir -p "$(dirname $PROMTAIL_CONFIG)"
    cat > "$PROMTAIL_CONFIG" <<EOF
server:
  http_listen_port: 9080
  grpc_listen_port: 0
positions:
  filename: /tmp/positions.yaml
clients:
  - url: http://localhost:$LOKI_PORT/loki/api/v1/push
scrape_configs:
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: varlogs
          __path__: /var/log/*log
EOF
    log_success "Promtail config created at $PROMTAIL_CONFIG"
}

create_loki_service() {
    local service_file="/etc/systemd/system/loki.service"
    if [[ "$DRY_RUN" == "true" ]]; then log_info "[DRY RUN] Would create Loki systemd service"; return; fi
    cat > "$service_file" <<EOF
[Unit]
Description=Loki Log Aggregation System
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/loki --config.file=$LOKI_CONFIG
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable loki
    log_success "Loki systemd service created and enabled"
}

create_promtail_service() {
    local service_file="/etc/systemd/system/promtail.service"
    if [[ "$DRY_RUN" == "true" ]]; then log_info "[DRY RUN] Would create Promtail systemd service"; return; fi
    cat > "$service_file" <<EOF
[Unit]
Description=Promtail Log Shipper
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/promtail --config.file=$PROMTAIL_CONFIG
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable promtail
    log_success "Promtail systemd service created and enabled"
}

start_services() {
    if [[ "$DRY_RUN" == "true" ]]; then log_info "[DRY RUN] Would start Loki, Promtail, and Grafana services"; return; fi
    systemctl restart loki || systemctl start loki
    systemctl restart promtail || systemctl start promtail
    systemctl restart grafana-server || systemctl start grafana-server
    log_success "Loki, Promtail, and Grafana services started"
}

show_status() {
    echo ""
    log_success "=== Loki Stack Setup Complete ==="
    echo ""
    log_info "Loki:     http://localhost:$LOKI_PORT"
    log_info "Promtail: http://localhost:9080"
    log_info "Grafana:  http://localhost:$GRAFANA_PORT (user: $GRAFANA_ADMIN_USER, password: $GRAFANA_ADMIN_PASSWORD)"
    echo ""
    log_info "To add Loki as a data source in Grafana, use URL: http://localhost:$LOKI_PORT"
    log_info "To import dashboards, use the Grafana web UI."
    echo ""
}

main() {
    log_info "Starting Loki Stack setup script"
    parse_arguments "$@"
    check_root
    install_dependencies
    create_user loki
    create_user promtail
    download_and_install_loki
    download_and_install_promtail
    download_and_install_grafana
    create_loki_config
    create_promtail_config
    create_loki_service
    create_promtail_service
    start_services
    show_status
    log_success "Loki Stack setup completed successfully!"
}

main "$@"
