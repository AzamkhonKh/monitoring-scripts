#!/bin/bash

# Node Exporter Setup Script for Prometheus
# Author: System Administrator
# Description: Comprehensive script to install, configure, and enable Node Exporter
# Usage: ./setup_node_exporter.sh [OPTIONS]

set -euo pipefail

# Default configuration
DEFAULT_NODE_EXPORTER_VERSION="1.9.1"
DEFAULT_NODE_EXPORTER_PORT="9100"
DEFAULT_NODE_EXPORTER_USER="node_exporter"
DEFAULT_PROMETHEUS_CONFIG="/etc/prometheus/prometheus.yml"
DEFAULT_PROMETHEUS_SERVICE="prometheus"
DEFAULT_INSTALL_DIR="/opt/node_exporter"
DEFAULT_SERVICE_NAME="node_exporter"

# Script variables (can be overridden by parameters)
NODE_EXPORTER_VERSION="${NODE_EXPORTER_VERSION:-$DEFAULT_NODE_EXPORTER_VERSION}"
NODE_EXPORTER_PORT="${NODE_EXPORTER_PORT:-$DEFAULT_NODE_EXPORTER_PORT}"
NODE_EXPORTER_USER="${NODE_EXPORTER_USER:-$DEFAULT_NODE_EXPORTER_USER}"
PROMETHEUS_CONFIG="${PROMETHEUS_CONFIG:-$DEFAULT_PROMETHEUS_CONFIG}"
PROMETHEUS_SERVICE="${PROMETHEUS_SERVICE:-$DEFAULT_PROMETHEUS_SERVICE}"
INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
SERVICE_NAME="${SERVICE_NAME:-$DEFAULT_SERVICE_NAME}"
DRY_RUN=false
FORCE_INSTALL=false
SKIP_PROMETHEUS_CONFIG=false
VERBOSE=false
TARGET_HOSTS=""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[VERBOSE]${NC} $1"
    fi
}

# Usage function
usage() {
    cat << EOF
Node Exporter Setup Script for Prometheus

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -v, --version VERSION           Node Exporter version (default: $DEFAULT_NODE_EXPORTER_VERSION)
    -p, --port PORT                 Node Exporter port (default: $DEFAULT_NODE_EXPORTER_PORT)
    -u, --user USER                 Service user (default: $DEFAULT_NODE_EXPORTER_USER)
    -c, --prometheus-config PATH    Prometheus config file (default: $DEFAULT_PROMETHEUS_CONFIG)
    -s, --prometheus-service NAME   Prometheus service name (default: $DEFAULT_PROMETHEUS_SERVICE)
    -d, --install-dir PATH          Installation directory (default: $DEFAULT_INSTALL_DIR)
    -n, --service-name NAME         Service name (default: $DEFAULT_SERVICE_NAME)
    -t, --targets HOSTS             Comma-separated list of target hosts for Prometheus config
    --dry-run                       Show what would be done without executing
    --force                         Force installation even if already installed
    --skip-prometheus-config        Skip Prometheus configuration update
    --verbose                       Enable verbose output
    -h, --help                      Show this help message

EXAMPLES:
    # Basic installation
    $0

    # Install specific version with custom port
    $0 --version 1.5.0 --port 9200

    # Install and configure for multiple targets
    $0 --targets "server1:9100,server2:9100,server3:9100"

    # Dry run to see what would be done
    $0 --dry-run --verbose

    # Force reinstallation
    $0 --force

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--version)
                NODE_EXPORTER_VERSION="$2"
                shift 2
                ;;
            -p|--port)
                NODE_EXPORTER_PORT="$2"
                shift 2
                ;;
            -u|--user)
                NODE_EXPORTER_USER="$2"
                shift 2
                ;;
            -c|--prometheus-config)
                PROMETHEUS_CONFIG="$2"
                shift 2
                ;;
            -s|--prometheus-service)
                PROMETHEUS_SERVICE="$2"
                shift 2
                ;;
            -d|--install-dir)
                INSTALL_DIR="$2"
                shift 2
                ;;
            -n|--service-name)
                SERVICE_NAME="$2"
                shift 2
                ;;
            -t|--targets)
                TARGET_HOSTS="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE_INSTALL=true
                shift
                ;;
            --skip-prometheus-config)
                SKIP_PROMETHEUS_CONFIG=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 && "$DRY_RUN" == "false" ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Detect operating system
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    elif [[ -f /etc/redhat-release ]]; then
        OS="centos"
    elif [[ -f /etc/debian_version ]]; then
        OS="debian"
    else
        log_error "Unsupported operating system"
        exit 1
    fi
    
    log_verbose "Detected OS: $OS $OS_VERSION"
}

# Check if Node Exporter is already installed
check_existing_installation() {
    if systemctl list-unit-files | grep -q "^$SERVICE_NAME.service"; then
        if [[ "$FORCE_INSTALL" == "false" ]]; then
            log_warning "Node Exporter service '$SERVICE_NAME' already exists"
            log_warning "Use --force to reinstall or choose a different service name with --service-name"
            exit 1
        else
            log_info "Forcing reinstallation of existing Node Exporter service"
        fi
    fi
}

# Create service user
create_user() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create user: $NODE_EXPORTER_USER"
        return
    fi

    if ! id "$NODE_EXPORTER_USER" &>/dev/null; then
        log_info "Creating user: $NODE_EXPORTER_USER"
        useradd --no-create-home --shell /bin/false "$NODE_EXPORTER_USER"
        log_success "User $NODE_EXPORTER_USER created"
    else
        log_info "User $NODE_EXPORTER_USER already exists"
    fi
}

# Download and install Node Exporter
download_and_install() {
    local arch
    arch=$(uname -m)
    case $arch in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l) arch="armv7" ;;
        *) log_error "Unsupported architecture: $arch"; exit 1 ;;
    esac

    local download_url="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-${arch}.tar.gz"
    local temp_dir="/tmp/node_exporter_install"
    local archive_name="node_exporter-${NODE_EXPORTER_VERSION}.linux-${arch}.tar.gz"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would download from: $download_url"
        log_info "[DRY RUN] Would install to: $INSTALL_DIR"
        return
    fi

    log_info "Downloading Node Exporter v$NODE_EXPORTER_VERSION for $arch"
    
    # Create temporary directory
    mkdir -p "$temp_dir"
    cd "$temp_dir"

    # Download and verify
    if ! curl -sSL "$download_url" -o "$archive_name"; then
        log_error "Failed to download Node Exporter"
        exit 1
    fi

    # Extract
    log_info "Extracting Node Exporter"
    tar xzf "$archive_name"

    # Install
    log_info "Installing Node Exporter to $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    cp "node_exporter-${NODE_EXPORTER_VERSION}.linux-${arch}/node_exporter" "$INSTALL_DIR/"
    
    # Set permissions
    chown "$NODE_EXPORTER_USER:$NODE_EXPORTER_USER" "$INSTALL_DIR/node_exporter"
    chmod +x "$INSTALL_DIR/node_exporter"

    # Cleanup
    cd /
    rm -rf "$temp_dir"

    log_success "Node Exporter installed successfully"
}

# Create systemd service
create_service() {
    local service_file="/etc/systemd/system/${SERVICE_NAME}.service"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create systemd service: $service_file"
        return
    fi

    log_info "Creating systemd service: $service_file"

    cat > "$service_file" << EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=$NODE_EXPORTER_USER
Group=$NODE_EXPORTER_USER
Type=simple
ExecStart=$INSTALL_DIR/node_exporter --web.listen-address=:$NODE_EXPORTER_PORT
Restart=always
RestartSec=3
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    
    log_success "Systemd service created and enabled"
}

# Start Node Exporter service
start_service() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would start service: $SERVICE_NAME"
        return
    fi

    log_info "Starting Node Exporter service"
    systemctl start "$SERVICE_NAME"
    
    # Wait a moment and check status
    sleep 2
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_success "Node Exporter is running on port $NODE_EXPORTER_PORT"
    else
        log_error "Failed to start Node Exporter service"
        systemctl status "$SERVICE_NAME" --no-pager
        exit 1
    fi
}

# Test Node Exporter endpoint
test_endpoint() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would test endpoint: http://localhost:$NODE_EXPORTER_PORT/metrics"
        return
    fi

    log_info "Testing Node Exporter endpoint"
    
    local max_attempts=10
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if curl -s "http://localhost:$NODE_EXPORTER_PORT/metrics" >/dev/null; then
            log_success "Node Exporter endpoint is responding"
            return
        fi
        
        log_verbose "Attempt $attempt/$max_attempts failed, waiting..."
        sleep 2
        ((attempt++))
    done
    
    log_error "Node Exporter endpoint not responding after $max_attempts attempts"
    exit 1
}

# Backup Prometheus configuration
backup_prometheus_config() {
    if [[ ! -f "$PROMETHEUS_CONFIG" ]]; then
        log_warning "Prometheus config file not found: $PROMETHEUS_CONFIG"
        return 1
    fi

    local backup_file="${PROMETHEUS_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would backup $PROMETHEUS_CONFIG to $backup_file"
        return 0
    fi

    cp "$PROMETHEUS_CONFIG" "$backup_file"
    log_success "Prometheus config backed up to: $backup_file"
    return 0
}

# Update Prometheus configuration
update_prometheus_config() {
    if [[ "$SKIP_PROMETHEUS_CONFIG" == "true" ]]; then
        log_info "Skipping Prometheus configuration update"
        return
    fi

    if ! backup_prometheus_config; then
        log_warning "Cannot backup Prometheus config, skipping configuration update"
        return
    fi

    local temp_config="/tmp/prometheus_updated.yml"
    local targets_config=""
    
    # Prepare targets configuration
    if [[ -n "$TARGET_HOSTS" ]]; then
        # Parse comma-separated targets
        IFS=',' read -ra TARGETS <<< "$TARGET_HOSTS"
        targets_config="    static_configs:\n      - targets:\n"
        for target in "${TARGETS[@]}"; do
            targets_config+="        - '${target}'\n"
        done
    else
        # Default to localhost
        targets_config="    static_configs:\n      - targets: ['localhost:$NODE_EXPORTER_PORT']\n"
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would update Prometheus config with Node Exporter job"
        log_info "[DRY RUN] Targets would be: ${TARGET_HOSTS:-localhost:$NODE_EXPORTER_PORT}"
        return
    fi

    log_info "Updating Prometheus configuration"

    # Check if node_exporter job already exists
    if grep -q "job_name.*node_exporter" "$PROMETHEUS_CONFIG"; then
        log_warning "Node Exporter job already exists in Prometheus config"
        log_warning "Please manually review and update: $PROMETHEUS_CONFIG"
        return
    fi

    # Add node_exporter job to scrape_configs
    python3 -c "
import yaml
import sys

try:
    with open('$PROMETHEUS_CONFIG', 'r') as f:
        config = yaml.safe_load(f)
    
    if 'scrape_configs' not in config:
        config['scrape_configs'] = []
    
    # Check if node_exporter job already exists
    for job in config['scrape_configs']:
        if job.get('job_name') == 'node_exporter':
            print('Node Exporter job already exists')
            sys.exit(0)
    
    # Add new job
    node_exporter_job = {
        'job_name': 'node_exporter',
        'scrape_interval': '15s',
        'static_configs': []
    }
    
    # Add targets
    targets = []
    if '$TARGET_HOSTS':
        targets = [t.strip() for t in '$TARGET_HOSTS'.split(',')]
    else:
        targets = ['localhost:$NODE_EXPORTER_PORT']
    
    node_exporter_job['static_configs'].append({'targets': targets})
    config['scrape_configs'].append(node_exporter_job)
    
    with open('$temp_config', 'w') as f:
        yaml.dump(config, f, default_flow_style=False, sort_keys=False)
    
    print('Configuration updated successfully')
except Exception as e:
    print(f'Error updating configuration: {e}')
    sys.exit(1)
" 2>/dev/null || {
        log_warning "Failed to update Prometheus config automatically"
        log_info "Please manually add the following job to your Prometheus configuration:"
        echo ""
        echo "  - job_name: 'node_exporter'"
        echo "    scrape_interval: 15s"
        echo -e "$targets_config"
        return
    }

    # Replace original config
    mv "$temp_config" "$PROMETHEUS_CONFIG"
    log_success "Prometheus configuration updated"
}

# Restart Prometheus service
restart_prometheus() {
    if [[ "$SKIP_PROMETHEUS_CONFIG" == "true" ]]; then
        return
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would restart Prometheus service: $PROMETHEUS_SERVICE"
        return
    fi

    log_info "Restarting Prometheus service"
    
    if systemctl is-active --quiet "$PROMETHEUS_SERVICE"; then
        systemctl restart "$PROMETHEUS_SERVICE"
        sleep 3
        
        if systemctl is-active --quiet "$PROMETHEUS_SERVICE"; then
            log_success "Prometheus service restarted successfully"
        else
            log_error "Failed to restart Prometheus service"
            systemctl status "$PROMETHEUS_SERVICE" --no-pager
        fi
    else
        log_warning "Prometheus service is not running, skipping restart"
    fi
}

# Show final status and information
show_status() {
    echo ""
    log_success "=== Node Exporter Setup Complete ==="
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "This was a dry run. No actual changes were made."
        return
    fi

    log_info "Service Information:"
    echo "  - Service Name: $SERVICE_NAME"
    echo "  - Service User: $NODE_EXPORTER_USER"
    echo "  - Installation Directory: $INSTALL_DIR"
    echo "  - Port: $NODE_EXPORTER_PORT"
    echo "  - Metrics URL: http://localhost:$NODE_EXPORTER_PORT/metrics"
    echo ""
    
    log_info "Useful Commands:"
    echo "  - Check status: systemctl status $SERVICE_NAME"
    echo "  - View logs: journalctl -u $SERVICE_NAME -f"
    echo "  - Stop service: systemctl stop $SERVICE_NAME"
    echo "  - Start service: systemctl start $SERVICE_NAME"
    echo "  - Restart service: systemctl restart $SERVICE_NAME"
    echo ""
    
    if [[ "$SKIP_PROMETHEUS_CONFIG" == "false" ]]; then
        log_info "Prometheus Configuration:"
        echo "  - Config file: $PROMETHEUS_CONFIG"
        echo "  - Service: $PROMETHEUS_SERVICE"
        echo "  - Backup created with timestamp"
    fi
    
    echo ""
    log_info "Verification:"
    echo "  - Node Exporter: curl http://localhost:$NODE_EXPORTER_PORT/metrics"
    echo "  - Prometheus targets: Check Prometheus web UI -> Status -> Targets"
}

# Cleanup function
cleanup() {
    if [[ -f /tmp/prometheus_updated.yml ]]; then
        rm -f /tmp/prometheus_updated.yml
    fi
}

# Main function
main() {
    trap cleanup EXIT

    log_info "Starting Node Exporter setup script"
    
    # Parse arguments
    parse_arguments "$@"
    
    # Show configuration
    if [[ "$VERBOSE" == "true" || "$DRY_RUN" == "true" ]]; then
        echo ""
        log_info "Configuration:"
        echo "  - Node Exporter Version: $NODE_EXPORTER_VERSION"
        echo "  - Port: $NODE_EXPORTER_PORT"
        echo "  - User: $NODE_EXPORTER_USER"
        echo "  - Install Directory: $INSTALL_DIR"
        echo "  - Service Name: $SERVICE_NAME"
        echo "  - Prometheus Config: $PROMETHEUS_CONFIG"
        echo "  - Prometheus Service: $PROMETHEUS_SERVICE"
        echo "  - Target Hosts: ${TARGET_HOSTS:-localhost:$NODE_EXPORTER_PORT}"
        echo "  - Dry Run: $DRY_RUN"
        echo "  - Force Install: $FORCE_INSTALL"
        echo "  - Skip Prometheus Config: $SKIP_PROMETHEUS_CONFIG"
        echo ""
    fi

    # Pre-flight checks
    check_root
    detect_os
    check_existing_installation

    # Installation steps
    create_user
    download_and_install
    create_service
    start_service
    test_endpoint
    update_prometheus_config
    restart_prometheus
    show_status

    log_success "Node Exporter setup completed successfully!"
}

# Run main function with all arguments
main "$@"
