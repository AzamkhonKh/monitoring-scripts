#!/bin/bash

# Apache Exporter Setup Script for Prometheus
# Author: System Administrator
# Description: Comprehensive script to install, configure, and enable Apache Exporter
# Usage: ./setup_apache_exporter.sh [OPTIONS]

set -euo pipefail

# Default configuration
DEFAULT_APACHE_EXPORTER_VERSION="1.0.1"
DEFAULT_APACHE_EXPORTER_PORT="9117"
DEFAULT_APACHE_EXPORTER_USER="apache_exporter"
DEFAULT_PROMETHEUS_CONFIG="/etc/prometheus/prometheus.yml"
DEFAULT_PROMETHEUS_SERVICE="prometheus"
DEFAULT_INSTALL_DIR="/opt/apache_exporter"
DEFAULT_SERVICE_NAME="apache_exporter"
DEFAULT_APACHE_STATUS_URL="http://localhost/server-status?auto"
DEFAULT_APACHE_CONFIG_DIR="/etc/apache2"
DEFAULT_APACHE_SERVICE="apache2"
DEFAULT_SCRAPE_INTERVAL="15s"

# Script variables (can be overridden by parameters)
APACHE_EXPORTER_VERSION="${APACHE_EXPORTER_VERSION:-$DEFAULT_APACHE_EXPORTER_VERSION}"
APACHE_EXPORTER_PORT="${APACHE_EXPORTER_PORT:-$DEFAULT_APACHE_EXPORTER_PORT}"
APACHE_EXPORTER_USER="${APACHE_EXPORTER_USER:-$DEFAULT_APACHE_EXPORTER_USER}"
PROMETHEUS_CONFIG="${PROMETHEUS_CONFIG:-$DEFAULT_PROMETHEUS_CONFIG}"
PROMETHEUS_SERVICE="${PROMETHEUS_SERVICE:-$DEFAULT_PROMETHEUS_SERVICE}"
INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
SERVICE_NAME="${SERVICE_NAME:-$DEFAULT_SERVICE_NAME}"
APACHE_STATUS_URL="${APACHE_STATUS_URL:-$DEFAULT_APACHE_STATUS_URL}"
APACHE_CONFIG_DIR="${APACHE_CONFIG_DIR:-$DEFAULT_APACHE_CONFIG_DIR}"
APACHE_SERVICE="${APACHE_SERVICE:-$DEFAULT_APACHE_SERVICE}"
SCRAPE_INTERVAL="${SCRAPE_INTERVAL:-$DEFAULT_SCRAPE_INTERVAL}"
DRY_RUN=false
FORCE_INSTALL=false
SKIP_PROMETHEUS_CONFIG=false
SKIP_APACHE_CONFIG=false
VERBOSE=false
TARGET_HOSTS=""
APACHE_USERNAME=""
APACHE_PASSWORD=""
ENABLE_SSL=false
SSL_VERIFY=true

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
Apache Exporter Setup Script for Prometheus

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -v, --version VERSION           Apache Exporter version (default: $DEFAULT_APACHE_EXPORTER_VERSION)
    -p, --port PORT                 Apache Exporter port (default: $DEFAULT_APACHE_EXPORTER_PORT)
    -u, --user USER                 Service user (default: $DEFAULT_APACHE_EXPORTER_USER)
    -c, --prometheus-config PATH    Prometheus config file (default: $DEFAULT_PROMETHEUS_CONFIG)
    -s, --prometheus-service NAME   Prometheus service name (default: $DEFAULT_PROMETHEUS_SERVICE)
    -d, --install-dir PATH          Installation directory (default: $DEFAULT_INSTALL_DIR)
    -n, --service-name NAME         Service name (default: $DEFAULT_SERVICE_NAME)
    -a, --apache-status-url URL     Apache status URL (default: $DEFAULT_APACHE_STATUS_URL)
    --apache-config-dir PATH        Apache config directory (default: $DEFAULT_APACHE_CONFIG_DIR)
    --apache-service NAME           Apache service name (default: $DEFAULT_APACHE_SERVICE)
    --apache-username USER          Apache basic auth username (optional)
    --apache-password PASS          Apache basic auth password (optional)
    --enable-ssl                    Enable SSL for Apache status URL
    --ssl-no-verify                 Disable SSL certificate verification
    -t, --targets HOSTS             Comma-separated list of target hosts for Prometheus config
    --scrape-interval INTERVAL      Scrape interval (default: $DEFAULT_SCRAPE_INTERVAL)
    --dry-run                       Show what would be done without executing
    --force                         Force installation even if already installed
    --skip-prometheus-config        Skip Prometheus configuration update
    --skip-apache-config            Skip Apache server-status configuration
    --verbose                       Enable verbose output
    -h, --help                      Show this help message

EXAMPLES:
    # Basic installation
    $0

    # Install specific version with custom port
    $0 --version 0.13.4 --port 9200

    # Install with custom Apache status URL
    $0 --apache-status-url "http://localhost:8080/server-status?auto"

    # Install with SSL and basic auth
    $0 --enable-ssl --apache-username admin --apache-password secret

    # Install and configure for multiple targets
    $0 --targets "server1:9117,server2:9117,server3:9117"

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
                APACHE_EXPORTER_VERSION="$2"
                shift 2
                ;;
            -p|--port)
                APACHE_EXPORTER_PORT="$2"
                shift 2
                ;;
            -u|--user)
                APACHE_EXPORTER_USER="$2"
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
            -a|--apache-status-url)
                APACHE_STATUS_URL="$2"
                shift 2
                ;;
            --apache-config-dir)
                APACHE_CONFIG_DIR="$2"
                shift 2
                ;;
            --apache-service)
                APACHE_SERVICE="$2"
                shift 2
                ;;
            --apache-username)
                APACHE_USERNAME="$2"
                shift 2
                ;;
            --apache-password)
                APACHE_PASSWORD="$2"
                shift 2
                ;;
            --enable-ssl)
                ENABLE_SSL=true
                shift
                ;;
            --ssl-no-verify)
                SSL_VERIFY=false
                shift
                ;;
            -t|--targets)
                TARGET_HOSTS="$2"
                shift 2
                ;;
            --scrape-interval)
                SCRAPE_INTERVAL="$2"
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
            --skip-apache-config)
                SKIP_APACHE_CONFIG=true
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
    
    # Adjust Apache paths based on OS
    if [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "fedora" ]]; then
        APACHE_CONFIG_DIR="/etc/httpd"
        APACHE_SERVICE="httpd"
    elif [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        APACHE_CONFIG_DIR="/etc/apache2"
        APACHE_SERVICE="apache2"
    fi
}

# Check if Apache Exporter is already installed
check_existing_installation() {
    if systemctl list-unit-files | grep -q "^$SERVICE_NAME.service"; then
        if [[ "$FORCE_INSTALL" == "false" ]]; then
            log_warning "Apache Exporter service '$SERVICE_NAME' already exists"
            log_warning "Use --force to reinstall or choose a different service name with --service-name"
            exit 1
        else
            log_info "Forcing reinstallation of existing Apache Exporter service"
        fi
    fi
}

# Check Apache installation and status
check_apache() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would check Apache installation and status"
        return
    fi

    if ! systemctl list-unit-files | grep -q "^$APACHE_SERVICE.service"; then
        log_error "Apache service '$APACHE_SERVICE' not found. Please install Apache first."
        exit 1
    fi

    if ! systemctl is-active --quiet "$APACHE_SERVICE"; then
        log_warning "Apache service '$APACHE_SERVICE' is not running"
        log_info "Starting Apache service..."
        systemctl start "$APACHE_SERVICE"
        sleep 2
        
        if ! systemctl is-active --quiet "$APACHE_SERVICE"; then
            log_error "Failed to start Apache service"
            exit 1
        fi
    fi

    log_success "Apache service is running"
}

# Create service user
create_user() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create user: $APACHE_EXPORTER_USER"
        return
    fi

    if ! id "$APACHE_EXPORTER_USER" &>/dev/null; then
        log_info "Creating user: $APACHE_EXPORTER_USER"
        useradd --no-create-home --shell /bin/false "$APACHE_EXPORTER_USER"
        log_success "User $APACHE_EXPORTER_USER created"
    else
        log_info "User $APACHE_EXPORTER_USER already exists"
    fi
}

# Configure Apache mod_status
configure_apache_status() {
    if [[ "$SKIP_APACHE_CONFIG" == "true" ]]; then
        log_info "Skipping Apache configuration"
        return
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure Apache mod_status"
        return
    fi

    log_info "Configuring Apache mod_status"

    # Enable mod_status module
    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        a2enmod status
        
        # Create status configuration
        cat > "$APACHE_CONFIG_DIR/conf-available/status.conf" << 'EOF'
<IfModule mod_status.c>
    <Location "/server-status">
        SetHandler server-status
        Require local
        Require ip 127.0.0.1
        Require ip ::1
    </Location>

    <Location "/server-info">
        SetHandler server-info
        Require local
        Require ip 127.0.0.1
        Require ip ::1
    </Location>
</IfModule>

# Extended status
ExtendedStatus On
EOF
        
        a2enconf status
        
    elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "fedora" ]]; then
        # Create status configuration for RHEL/CentOS
        cat > "$APACHE_CONFIG_DIR/conf.d/status.conf" << 'EOF'
LoadModule status_module modules/mod_status.so

<IfModule mod_status.c>
    <Location "/server-status">
        SetHandler server-status
        Require local
        Require ip 127.0.0.1
        Require ip ::1
    </Location>

    <Location "/server-info">
        SetHandler server-info
        Require local
        Require ip 127.0.0.1
        Require ip ::1
    </Location>
</IfModule>

# Extended status
ExtendedStatus On
EOF
    fi

    # Test Apache configuration
    if ! apache2ctl configtest 2>/dev/null && ! httpd -t 2>/dev/null; then
        log_error "Apache configuration test failed"
        exit 1
    fi

    # Reload Apache
    systemctl reload "$APACHE_SERVICE"
    log_success "Apache mod_status configured and reloaded"
}

# Download and install Apache Exporter
download_and_install() {
    local arch
    arch=$(uname -m)
    case $arch in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l) arch="armv7" ;;
        *) log_error "Unsupported architecture: $arch"; exit 1 ;;
    esac

    local download_url="https://github.com/Lusitaniae/apache_exporter/releases/download/v${APACHE_EXPORTER_VERSION}/apache_exporter-${APACHE_EXPORTER_VERSION}.linux-${arch}.tar.gz"
    local temp_dir="/tmp/apache_exporter_install"
    local archive_name="apache_exporter-${APACHE_EXPORTER_VERSION}.linux-${arch}.tar.gz"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would download from: $download_url"
        log_info "[DRY RUN] Would install to: $INSTALL_DIR"
        return
    fi

    log_info "Downloading Apache Exporter v$APACHE_EXPORTER_VERSION for $arch"
    
    # Create temporary directory
    mkdir -p "$temp_dir"
    cd "$temp_dir"

    # Download and verify
    if ! curl -sSL "$download_url" -o "$archive_name"; then
        log_error "Failed to download Apache Exporter"
        exit 1
    fi

    # Extract
    log_info "Extracting Apache Exporter"
    tar xzf "$archive_name"

    # Install
    log_info "Installing Apache Exporter to $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    cp "apache_exporter-${APACHE_EXPORTER_VERSION}.linux-${arch}/apache_exporter" "$INSTALL_DIR/"
    
    # Set permissions
    chown "$APACHE_EXPORTER_USER:$APACHE_EXPORTER_USER" "$INSTALL_DIR/apache_exporter"
    chmod +x "$INSTALL_DIR/apache_exporter"

    # Cleanup
    cd /
    rm -rf "$temp_dir"

    log_success "Apache Exporter installed successfully"
}

# Create systemd service
create_service() {
    local service_file="/etc/systemd/system/${SERVICE_NAME}.service"
    local exec_start="$INSTALL_DIR/apache_exporter"
    
    # Build command line arguments
    exec_start+=" --web.listen-address=:$APACHE_EXPORTER_PORT"
    exec_start+=" --scrape_uri=$APACHE_STATUS_URL"
    
    if [[ -n "$APACHE_USERNAME" && -n "$APACHE_PASSWORD" ]]; then
        exec_start+=" --basic_auth.username=$APACHE_USERNAME"
        exec_start+=" --basic_auth.password=$APACHE_PASSWORD"
    fi
    
    if [[ "$ENABLE_SSL" == "true" ]]; then
        if [[ "$SSL_VERIFY" == "false" ]]; then
            exec_start+=" --insecure"
        fi
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create systemd service: $service_file"
        log_info "[DRY RUN] ExecStart: $exec_start"
        return
    fi

    log_info "Creating systemd service: $service_file"

    cat > "$service_file" << EOF
[Unit]
Description=Apache Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=$APACHE_EXPORTER_USER
Group=$APACHE_EXPORTER_USER
Type=simple
ExecStart=$exec_start
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

# Start Apache Exporter service
start_service() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would start service: $SERVICE_NAME"
        return
    fi

    log_info "Starting Apache Exporter service"
    systemctl start "$SERVICE_NAME"
    
    # Wait a moment and check status
    sleep 2
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_success "Apache Exporter is running on port $APACHE_EXPORTER_PORT"
    else
        log_error "Failed to start Apache Exporter service"
        systemctl status "$SERVICE_NAME" --no-pager
        exit 1
    fi
}

# Test Apache Exporter endpoint
test_endpoint() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would test endpoint: http://localhost:$APACHE_EXPORTER_PORT/metrics"
        return
    fi

    log_info "Testing Apache Exporter endpoint"
    
    local max_attempts=10
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if curl -s "http://localhost:$APACHE_EXPORTER_PORT/metrics" >/dev/null; then
            log_success "Apache Exporter endpoint is responding"
            
            # Test if Apache metrics are being collected
            if curl -s "http://localhost:$APACHE_EXPORTER_PORT/metrics" | grep -q "apache_"; then
                log_success "Apache metrics are being collected successfully"
            else
                log_warning "Apache Exporter is running but no Apache metrics found"
                log_warning "Please check Apache status URL: $APACHE_STATUS_URL"
            fi
            return
        fi
        
        log_verbose "Attempt $attempt/$max_attempts failed, waiting..."
        sleep 2
        ((attempt++))
    done
    
    log_error "Apache Exporter endpoint not responding after $max_attempts attempts"
    exit 1
}

# Test Apache status URL
test_apache_status() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would test Apache status URL: $APACHE_STATUS_URL"
        return
    fi

    log_info "Testing Apache status URL: $APACHE_STATUS_URL"
    
    local curl_cmd="curl -s"
    if [[ -n "$APACHE_USERNAME" && -n "$APACHE_PASSWORD" ]]; then
        curl_cmd+=" -u $APACHE_USERNAME:$APACHE_PASSWORD"
    fi
    
    if [[ "$ENABLE_SSL" == "true" && "$SSL_VERIFY" == "false" ]]; then
        curl_cmd+=" -k"
    fi
    
    if $curl_cmd "$APACHE_STATUS_URL" | grep -q "Total Accesses:"; then
        log_success "Apache status URL is accessible"
    else
        log_warning "Apache status URL may not be properly configured"
        log_warning "Please verify: $APACHE_STATUS_URL"
    fi
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
        targets_config="    static_configs:\n      - targets: ['localhost:$APACHE_EXPORTER_PORT']\n"
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would update Prometheus config with Apache Exporter job"
        log_info "[DRY RUN] Targets would be: ${TARGET_HOSTS:-localhost:$APACHE_EXPORTER_PORT}"
        return
    fi

    log_info "Updating Prometheus configuration"

    # Check if apache_exporter job already exists
    if grep -q "job_name.*apache_exporter" "$PROMETHEUS_CONFIG"; then
        log_warning "Apache Exporter job already exists in Prometheus config"
        log_warning "Please manually review and update: $PROMETHEUS_CONFIG"
        return
    fi

    # Add apache_exporter job to scrape_configs
    python3 -c "
import yaml
import sys

try:
    with open('$PROMETHEUS_CONFIG', 'r') as f:
        config = yaml.safe_load(f)
    
    if 'scrape_configs' not in config:
        config['scrape_configs'] = []
    
    # Check if apache_exporter job already exists
    for job in config['scrape_configs']:
        if job.get('job_name') == 'apache_exporter':
            print('Apache Exporter job already exists')
            sys.exit(0)
    
    # Add new job
    apache_exporter_job = {
        'job_name': 'apache_exporter',
        'scrape_interval': '$SCRAPE_INTERVAL',
        'static_configs': []
    }
    
    # Add targets
    targets = []
    if '$TARGET_HOSTS':
        targets = [t.strip() for t in '$TARGET_HOSTS'.split(',')]
    else:
        targets = ['localhost:$APACHE_EXPORTER_PORT']
    
    apache_exporter_job['static_configs'].append({'targets': targets})
    config['scrape_configs'].append(apache_exporter_job)
    
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
        echo "  - job_name: 'apache_exporter'"
        echo "    scrape_interval: $SCRAPE_INTERVAL"
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
    log_success "=== Apache Exporter Setup Complete ==="
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "This was a dry run. No actual changes were made."
        return
    fi

    log_info "Service Information:"
    echo "  - Service Name: $SERVICE_NAME"
    echo "  - Service User: $APACHE_EXPORTER_USER"
    echo "  - Installation Directory: $INSTALL_DIR"
    echo "  - Port: $APACHE_EXPORTER_PORT"
    echo "  - Metrics URL: http://localhost:$APACHE_EXPORTER_PORT/metrics"
    echo "  - Apache Status URL: $APACHE_STATUS_URL"
    echo ""
    
    log_info "Useful Commands:"
    echo "  - Check status: systemctl status $SERVICE_NAME"
    echo "  - View logs: journalctl -u $SERVICE_NAME -f"
    echo "  - Stop service: systemctl stop $SERVICE_NAME"
    echo "  - Start service: systemctl start $SERVICE_NAME"
    echo "  - Restart service: systemctl restart $SERVICE_NAME"
    echo ""
    
    log_info "Apache Commands:"
    echo "  - Check Apache status: systemctl status $APACHE_SERVICE"
    echo "  - Test Apache config: apache2ctl configtest || httpd -t"
    echo "  - Check status URL: curl $APACHE_STATUS_URL"
    echo ""
    
    if [[ "$SKIP_PROMETHEUS_CONFIG" == "false" ]]; then
        log_info "Prometheus Configuration:"
        echo "  - Config file: $PROMETHEUS_CONFIG"
        echo "  - Service: $PROMETHEUS_SERVICE"
        echo "  - Backup created with timestamp"
    fi
    
    echo ""
    log_info "Verification:"
    echo "  - Apache Exporter: curl http://localhost:$APACHE_EXPORTER_PORT/metrics"
    echo "  - Apache Status: curl $APACHE_STATUS_URL"
    echo "  - Prometheus targets: Check Prometheus web UI -> Status -> Targets"
    
    echo ""
    log_info "Troubleshooting:"
    echo "  - If no metrics: Check Apache status URL accessibility"
    echo "  - If authentication issues: Verify --apache-username/--apache-password"
    echo "  - If SSL issues: Use --ssl-no-verify for self-signed certificates"
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

    log_info "Starting Apache Exporter setup script"
    
    # Parse arguments
    parse_arguments "$@"
    
    # Show configuration
    if [[ "$VERBOSE" == "true" || "$DRY_RUN" == "true" ]]; then
        echo ""
        log_info "Configuration:"
        echo "  - Apache Exporter Version: $APACHE_EXPORTER_VERSION"
        echo "  - Port: $APACHE_EXPORTER_PORT"
        echo "  - User: $APACHE_EXPORTER_USER"
        echo "  - Install Directory: $INSTALL_DIR"
        echo "  - Service Name: $SERVICE_NAME"
        echo "  - Apache Status URL: $APACHE_STATUS_URL"
        echo "  - Apache Config Dir: $APACHE_CONFIG_DIR"
        echo "  - Apache Service: $APACHE_SERVICE"
        echo "  - Prometheus Config: $PROMETHEUS_CONFIG"
        echo "  - Prometheus Service: $PROMETHEUS_SERVICE"
        echo "  - Target Hosts: ${TARGET_HOSTS:-localhost:$APACHE_EXPORTER_PORT}"
        echo "  - Scrape Interval: $SCRAPE_INTERVAL"
        echo "  - SSL Enabled: $ENABLE_SSL"
        echo "  - SSL Verify: $SSL_VERIFY"
        echo "  - Dry Run: $DRY_RUN"
        echo "  - Force Install: $FORCE_INSTALL"
        echo "  - Skip Prometheus Config: $SKIP_PROMETHEUS_CONFIG"
        echo "  - Skip Apache Config: $SKIP_APACHE_CONFIG"
        echo ""
    fi

    # Pre-flight checks
    check_root
    detect_os
    check_existing_installation
    check_apache

    # Installation steps
    create_user
    configure_apache_status
    download_and_install
    create_service
    start_service
    test_apache_status
    test_endpoint
    update_prometheus_config
    restart_prometheus
    show_status

    log_success "Apache Exporter setup completed successfully!"
}

# Run main function with all arguments
main "$@"
