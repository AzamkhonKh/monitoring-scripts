#!/bin/bash

# MySQL Exporter Setup Script for Prometheus
# Author: System Administrator
# Description: Comprehensive script to install, configure, and enable MySQL Exporter
# Usage: ./setup_mysql_exporter.sh [OPTIONS]

set -euo pipefail

# Default configuration
DEFAULT_MYSQL_EXPORTER_VERSION="0.17.2"
DEFAULT_MYSQL_EXPORTER_PORT="9104"
DEFAULT_MYSQL_EXPORTER_USER="mysql_exporter"
DEFAULT_PROMETHEUS_CONFIG="/etc/prometheus/prometheus.yml"
DEFAULT_PROMETHEUS_SERVICE="prometheus"
DEFAULT_INSTALL_DIR="/opt/mysql_exporter"
DEFAULT_SERVICE_NAME="mysql_exporter"
DEFAULT_CONFIG_DIR="/etc/mysql_exporter"
DEFAULT_MYSQL_HOST="localhost"
DEFAULT_MYSQL_PORT="3306"
DEFAULT_MYSQL_USER="mysql_exporter"
DEFAULT_MYSQL_PASSWORD=""
DEFAULT_MYSQL_DATABASE=""

# Script variables (can be overridden by parameters)
MYSQL_EXPORTER_VERSION="${MYSQL_EXPORTER_VERSION:-$DEFAULT_MYSQL_EXPORTER_VERSION}"
MYSQL_EXPORTER_PORT="${MYSQL_EXPORTER_PORT:-$DEFAULT_MYSQL_EXPORTER_PORT}"
MYSQL_EXPORTER_USER="${MYSQL_EXPORTER_USER:-$DEFAULT_MYSQL_EXPORTER_USER}"
PROMETHEUS_CONFIG="${PROMETHEUS_CONFIG:-$DEFAULT_PROMETHEUS_CONFIG}"
PROMETHEUS_SERVICE="${PROMETHEUS_SERVICE:-$DEFAULT_PROMETHEUS_SERVICE}"
INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
SERVICE_NAME="${SERVICE_NAME:-$DEFAULT_SERVICE_NAME}"
CONFIG_DIR="${CONFIG_DIR:-$DEFAULT_CONFIG_DIR}"
MYSQL_HOST="${MYSQL_HOST:-$DEFAULT_MYSQL_HOST}"
MYSQL_PORT="${MYSQL_PORT:-$DEFAULT_MYSQL_PORT}"
MYSQL_USER="${MYSQL_USER:-$DEFAULT_MYSQL_USER}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-$DEFAULT_MYSQL_PASSWORD}"
MYSQL_DATABASE="${MYSQL_DATABASE:-$DEFAULT_MYSQL_DATABASE}"
DRY_RUN=false
FORCE_INSTALL=false
SKIP_PROMETHEUS_CONFIG=false
SKIP_MYSQL_USER_CREATION=false
VERBOSE=false
TARGET_HOSTS=""
CONFIG_FILE=""
MYSQL_ROOT_PASSWORD=""

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
MySQL Exporter Setup Script for Prometheus

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -v, --version VERSION           MySQL Exporter version (default: $DEFAULT_MYSQL_EXPORTER_VERSION)
    -p, --port PORT                 MySQL Exporter port (default: $DEFAULT_MYSQL_EXPORTER_PORT)
    -u, --user USER                 Service user (default: $DEFAULT_MYSQL_EXPORTER_USER)
    -c, --prometheus-config PATH    Prometheus config file (default: $DEFAULT_PROMETHEUS_CONFIG)
    -s, --prometheus-service NAME   Prometheus service name (default: $DEFAULT_PROMETHEUS_SERVICE)
    -d, --install-dir PATH          Installation directory (default: $DEFAULT_INSTALL_DIR)
    -n, --service-name NAME         Service name (default: $DEFAULT_SERVICE_NAME)
    --config-dir PATH               Configuration directory (default: $DEFAULT_CONFIG_DIR)
    --mysql-host HOST               MySQL host (default: $DEFAULT_MYSQL_HOST)
    --mysql-port PORT               MySQL port (default: $DEFAULT_MYSQL_PORT)
    --mysql-user USER               MySQL user for exporter (default: $DEFAULT_MYSQL_USER)
    --mysql-password PASSWORD      MySQL password for exporter
    --mysql-database DATABASE      MySQL database name
    --mysql-root-password PASSWORD MySQL root password (for user creation)
    --config-file PATH              Path to MySQL exporter config file
    -t, --targets HOSTS             Comma-separated list of target hosts for Prometheus config
    --dry-run                       Show what would be done without executing
    --force                         Force installation even if already installed
    --skip-prometheus-config        Skip Prometheus configuration update
    --skip-mysql-user-creation      Skip MySQL user creation
    --verbose                       Enable verbose output
    -h, --help                      Show this help message

EXAMPLES:
    # Basic installation (will prompt for MySQL credentials)
    $0

    # Install with specific MySQL connection
    $0 --mysql-host db1.example.com --mysql-user exporter --mysql-password secret123

    # Install specific version with custom port
    $0 --version 0.14.0 --port 9204

    # Install and configure for multiple targets
    $0 --targets "db1:9104,db2:9104,db3:9104"

    # Use existing config file
    $0 --config-file /path/to/my.cnf

    # Dry run to see what would be done
    $0 --dry-run --verbose

    # Force reinstallation
    $0 --force

MYSQL USER SETUP:
    The script can automatically create a MySQL user for the exporter with the following privileges:
    - PROCESS
    - REPLICATION CLIENT
    - SELECT ON performance_schema.*
    - SELECT ON information_schema.*

    If you prefer to create the user manually, use --skip-mysql-user-creation

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--version)
                MYSQL_EXPORTER_VERSION="$2"
                shift 2
                ;;
            -p|--port)
                MYSQL_EXPORTER_PORT="$2"
                shift 2
                ;;
            -u|--user)
                MYSQL_EXPORTER_USER="$2"
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
            --config-dir)
                CONFIG_DIR="$2"
                shift 2
                ;;
            --mysql-host)
                MYSQL_HOST="$2"
                shift 2
                ;;
            --mysql-port)
                MYSQL_PORT="$2"
                shift 2
                ;;
            --mysql-user)
                MYSQL_USER="$2"
                shift 2
                ;;
            --mysql-password)
                MYSQL_PASSWORD="$2"
                shift 2
                ;;
            --mysql-database)
                MYSQL_DATABASE="$2"
                shift 2
                ;;
            --mysql-root-password)
                MYSQL_ROOT_PASSWORD="$2"
                shift 2
                ;;
            --config-file)
                CONFIG_FILE="$2"
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
            --skip-mysql-user-creation)
                SKIP_MYSQL_USER_CREATION=true
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

# Check if MySQL Exporter is already installed
check_existing_installation() {
    if systemctl list-unit-files | grep -q "^$SERVICE_NAME.service"; then
        if [[ "$FORCE_INSTALL" == "false" ]]; then
            log_warning "MySQL Exporter service '$SERVICE_NAME' already exists"
            log_warning "Use --force to reinstall or choose a different service name with --service-name"
            exit 1
        else
            log_info "Forcing reinstallation of existing MySQL Exporter service"
        fi
    fi
}

# Install required packages
install_dependencies() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would install required packages"
        return
    fi

    log_info "Installing required packages"
    
    case $OS in
        ubuntu|debian)
            apt-get update
            apt-get install -y curl wget mysql-client python3 python3-yaml
            ;;
        centos|rhel|rocky|almalinux)
            if command -v dnf &> /dev/null; then
                dnf install -y curl wget mysql python3 python3-pyyaml
            else
                yum install -y curl wget mysql python3 python3-pyyaml
            fi
            ;;
        *)
            log_warning "Unknown OS, skipping package installation"
            ;;
    esac
}

# Prompt for MySQL credentials if not provided
prompt_credentials() {
    if [[ -n "$CONFIG_FILE" ]]; then
        log_info "Using config file: $CONFIG_FILE"
        return
    fi

    if [[ -z "$MYSQL_PASSWORD" && "$DRY_RUN" == "false" && "$SKIP_MYSQL_USER_CREATION" == "false" ]]; then
        echo ""
        log_info "MySQL credentials required for exporter setup"
        
        if [[ -z "$MYSQL_ROOT_PASSWORD" ]]; then
            echo -n "Enter MySQL root password (for user creation): "
            read -s MYSQL_ROOT_PASSWORD
            echo ""
        fi
        
        echo -n "Enter password for MySQL exporter user '$MYSQL_USER' (will be created): "
        read -s MYSQL_PASSWORD
        echo ""
        echo ""
    fi
}

# Test MySQL connection
test_mysql_connection() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would test MySQL connection to $MYSQL_HOST:$MYSQL_PORT"
        return
    fi

    log_info "Testing MySQL connection"
    
    local mysql_cmd="mysql -h$MYSQL_HOST -P$MYSQL_PORT -uroot"
    if [[ -n "$MYSQL_ROOT_PASSWORD" ]]; then
        mysql_cmd+=" -p$MYSQL_ROOT_PASSWORD"
    fi
    
    if ! echo "SELECT 1;" | $mysql_cmd >/dev/null 2>&1; then
        log_error "Cannot connect to MySQL server at $MYSQL_HOST:$MYSQL_PORT"
        log_error "Please check your MySQL credentials and server availability"
        exit 1
    fi
    
    log_success "MySQL connection successful"
}

# Create MySQL user for exporter
create_mysql_user() {
    if [[ "$SKIP_MYSQL_USER_CREATION" == "true" ]]; then
        log_info "Skipping MySQL user creation"
        return
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create MySQL user: $MYSQL_USER"
        return
    fi

    log_info "Creating MySQL user for exporter: $MYSQL_USER"
    local mysql_cmd="mysql -h$MYSQL_HOST -P$MYSQL_PORT -uroot"
    if [[ -n "$MYSQL_ROOT_PASSWORD" ]]; then
        mysql_cmd+=" -p$MYSQL_ROOT_PASSWORD"
    fi

    # MariaDB/MySQL compatibility: Try to create user, if exists then alter password
    cat << EOF | $mysql_cmd 2>/tmp/mysql_exporter_create_user.err
-- Try to create user, ignore error if exists
DELIMITER //
CREATE USER '$MYSQL_USER'@'%' IDENTIFIED BY '$MYSQL_PASSWORD'//
CREATE USER '$MYSQL_USER'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD'//
DELIMITER ;
-- If user exists, update password
SET PASSWORD FOR '$MYSQL_USER'@'%' = PASSWORD('$MYSQL_PASSWORD');
SET PASSWORD FOR '$MYSQL_USER'@'localhost' = PASSWORD('$MYSQL_PASSWORD');
-- Grant necessary privileges
GRANT PROCESS, REPLICATION CLIENT ON *.* TO '$MYSQL_USER'@'%';
GRANT SELECT ON performance_schema.* TO '$MYSQL_USER'@'%';
GRANT SELECT ON information_schema.* TO '$MYSQL_USER'@'%';
GRANT PROCESS, REPLICATION CLIENT ON *.* TO '$MYSQL_USER'@'localhost';
GRANT SELECT ON performance_schema.* TO '$MYSQL_USER'@'localhost';
GRANT SELECT ON information_schema.* TO '$MYSQL_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

    if grep -q "ERROR" /tmp/mysql_exporter_create_user.err; then
        log_warning "Some errors occurred during user creation (likely user already exists). Attempted to update password and privileges."
        cat /tmp/mysql_exporter_create_user.err
    else
        log_success "MySQL user created or updated successfully"
    fi
    rm -f /tmp/mysql_exporter_create_user.err
}

# Create service user
create_user() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create user: $MYSQL_EXPORTER_USER"
        return
    fi

    if ! id "$MYSQL_EXPORTER_USER" &>/dev/null; then
        log_info "Creating user: $MYSQL_EXPORTER_USER"
        useradd --no-create-home --shell /bin/false "$MYSQL_EXPORTER_USER"
        log_success "User $MYSQL_EXPORTER_USER created"
    else
        log_info "User $MYSQL_EXPORTER_USER already exists"
    fi
}

# Download and install MySQL Exporter
download_and_install() {
    local arch
    arch=$(uname -m)
    case $arch in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l) arch="armv7" ;;
        *) log_error "Unsupported architecture: $arch"; exit 1 ;;
    esac

    local download_url="https://github.com/prometheus/mysqld_exporter/releases/download/v${MYSQL_EXPORTER_VERSION}/mysqld_exporter-${MYSQL_EXPORTER_VERSION}.linux-${arch}.tar.gz"
    local temp_dir="/tmp/mysql_exporter_install"
    local archive_name="mysqld_exporter-${MYSQL_EXPORTER_VERSION}.linux-${arch}.tar.gz"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would download from: $download_url"
        log_info "[DRY RUN] Would install to: $INSTALL_DIR"
        return
    fi

    log_info "Downloading MySQL Exporter v$MYSQL_EXPORTER_VERSION for $arch"
    
    # Create temporary directory
    mkdir -p "$temp_dir"
    cd "$temp_dir"

    # Download and verify
    if ! curl -sSL "$download_url" -o "$archive_name"; then
        log_error "Failed to download MySQL Exporter"
        exit 1
    fi

    # Extract
    log_info "Extracting MySQL Exporter"
    tar xzf "$archive_name"

    # Install
    log_info "Installing MySQL Exporter to $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    cp "mysqld_exporter-${MYSQL_EXPORTER_VERSION}.linux-${arch}/mysqld_exporter" "$INSTALL_DIR/"
    
    # Set permissions
    chown "$MYSQL_EXPORTER_USER:$MYSQL_EXPORTER_USER" "$INSTALL_DIR/mysqld_exporter"
    chmod +x "$INSTALL_DIR/mysqld_exporter"

    # Cleanup
    cd /
    rm -rf "$temp_dir"

    log_success "MySQL Exporter installed successfully"
}

# Create configuration file
create_config() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create configuration directory: $CONFIG_DIR"
        return
    fi

    log_info "Creating MySQL Exporter configuration"
    
    # Create config directory
    mkdir -p "$CONFIG_DIR"
    
    local config_file="$CONFIG_DIR/my.cnf"
    
    if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
        # Use provided config file
        cp "$CONFIG_FILE" "$config_file"
        log_info "Using provided config file: $CONFIG_FILE"
    else
        # Create new config file
        cat > "$config_file" << EOF
[client]
host = $MYSQL_HOST
port = $MYSQL_PORT
user = $MYSQL_USER
password = $MYSQL_PASSWORD
EOF

        if [[ -n "$MYSQL_DATABASE" ]]; then
            echo "database = $MYSQL_DATABASE" >> "$config_file"
        fi
    fi
    
    # Set secure permissions
    chown "$MYSQL_EXPORTER_USER:$MYSQL_EXPORTER_USER" "$config_file"
    chmod 600 "$config_file"
    
    log_success "Configuration file created: $config_file"
}

# Create systemd service
create_service() {
    local service_file="/etc/systemd/system/${SERVICE_NAME}.service"
    local config_file="$CONFIG_DIR/my.cnf"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create systemd service: $service_file"
        return
    fi

    log_info "Creating systemd service: $service_file"

    cat > "$service_file" << EOF
[Unit]
Description=MySQL Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=$MYSQL_EXPORTER_USER
Group=$MYSQL_EXPORTER_USER
Type=simple
ExecStart=$INSTALL_DIR/mysqld_exporter --config.my-cnf=$config_file --web.listen-address=:$MYSQL_EXPORTER_PORT
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

# Start MySQL Exporter service
start_service() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would start service: $SERVICE_NAME"
        return
    fi

    log_info "Starting MySQL Exporter service"
    systemctl start "$SERVICE_NAME"
    
    # Wait a moment and check status
    sleep 3
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_success "MySQL Exporter is running on port $MYSQL_EXPORTER_PORT"
    else
        log_error "Failed to start MySQL Exporter service"
        systemctl status "$SERVICE_NAME" --no-pager
        journalctl -u "$SERVICE_NAME" --no-pager -n 20
        exit 1
    fi
}

# Test MySQL Exporter endpoint
test_endpoint() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would test endpoint: http://localhost:$MYSQL_EXPORTER_PORT/metrics"
        return
    fi

    log_info "Testing MySQL Exporter endpoint"
    
    local max_attempts=10
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if curl -s "http://localhost:$MYSQL_EXPORTER_PORT/metrics" | grep -q "mysql_up"; then
            log_success "MySQL Exporter endpoint is responding and MySQL connection is working"
            return
        fi
        
        log_verbose "Attempt $attempt/$max_attempts failed, waiting..."
        sleep 2
        ((attempt++))
    done
    
    log_error "MySQL Exporter endpoint not responding properly after $max_attempts attempts"
    log_error "Check the service logs: journalctl -u $SERVICE_NAME -f"
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
        targets_config="    static_configs:\n      - targets: ['localhost:$MYSQL_EXPORTER_PORT']\n"
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would update Prometheus config with MySQL Exporter job"
        log_info "[DRY RUN] Targets would be: ${TARGET_HOSTS:-localhost:$MYSQL_EXPORTER_PORT}"
        return
    fi

    log_info "Updating Prometheus configuration"

    # Check if mysql_exporter job already exists
    if grep -q "job_name.*mysql" "$PROMETHEUS_CONFIG"; then
        log_warning "MySQL Exporter job already exists in Prometheus config"
        log_warning "Please manually review and update: $PROMETHEUS_CONFIG"
        return
    fi

    # Add mysql_exporter job to scrape_configs
    python3 -c "
import yaml
import sys

try:
    with open('$PROMETHEUS_CONFIG', 'r') as f:
        config = yaml.safe_load(f)
    
    if 'scrape_configs' not in config:
        config['scrape_configs'] = []
    
    # Check if mysql_exporter job already exists
    for job in config['scrape_configs']:
        if job.get('job_name') in ['mysql_exporter', 'mysql', 'mysqld_exporter']:
            print('MySQL Exporter job already exists')
            sys.exit(0)
    
    # Add new job
    mysql_exporter_job = {
        'job_name': 'mysql_exporter',
        'scrape_interval': '15s',
        'static_configs': []
    }
    
    # Add targets
    targets = []
    if '$TARGET_HOSTS':
        targets = [t.strip() for t in '$TARGET_HOSTS'.split(',')]
    else:
        targets = ['localhost:$MYSQL_EXPORTER_PORT']
    
    mysql_exporter_job['static_configs'].append({'targets': targets})
    config['scrape_configs'].append(mysql_exporter_job)
    
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
        echo "  - job_name: 'mysql_exporter'"
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
    log_success "=== MySQL Exporter Setup Complete ==="
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "This was a dry run. No actual changes were made."
        return
    fi

    log_info "Service Information:"
    echo "  - Service Name: $SERVICE_NAME"
    echo "  - Service User: $MYSQL_EXPORTER_USER"
    echo "  - Installation Directory: $INSTALL_DIR"
    echo "  - Configuration Directory: $CONFIG_DIR"
    echo "  - Port: $MYSQL_EXPORTER_PORT"
    echo "  - Metrics URL: http://localhost:$MYSQL_EXPORTER_PORT/metrics"
    echo ""
    
    log_info "MySQL Connection:"
    echo "  - Host: $MYSQL_HOST"
    echo "  - Port: $MYSQL_PORT"
    echo "  - User: $MYSQL_USER"
    if [[ -n "$MYSQL_DATABASE" ]]; then
        echo "  - Database: $MYSQL_DATABASE"
    fi
    echo ""
    
    log_info "Useful Commands:"
    echo "  - Check status: systemctl status $SERVICE_NAME"
    echo "  - View logs: journalctl -u $SERVICE_NAME -f"
    echo "  - Stop service: systemctl stop $SERVICE_NAME"
    echo "  - Start service: systemctl start $SERVICE_NAME"
    echo "  - Restart service: systemctl restart $SERVICE_NAME"
    echo "  - Edit config: nano $CONFIG_DIR/my.cnf"
    echo ""
    
    if [[ "$SKIP_PROMETHEUS_CONFIG" == "false" ]]; then
        log_info "Prometheus Configuration:"
        echo "  - Config file: $PROMETHEUS_CONFIG"
        echo "  - Service: $PROMETHEUS_SERVICE"
        echo "  - Backup created with timestamp"
    fi
    
    echo ""
    log_info "Verification:"
    echo "  - MySQL Exporter: curl http://localhost:$MYSQL_EXPORTER_PORT/metrics | grep mysql_up"
    echo "  - Prometheus targets: Check Prometheus web UI -> Status -> Targets"
    echo ""
    
    log_info "Available Metrics (examples):"
    echo "  - mysql_up: MySQL server availability"
    echo "  - mysql_global_status_*: MySQL status variables"
    echo "  - mysql_global_variables_*: MySQL configuration variables"
    echo "  - mysql_info_schema_*: Information schema metrics"
    echo "  - mysql_perf_schema_*: Performance schema metrics"
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

    log_info "Starting MySQL Exporter setup script"
    
    # Parse arguments
    parse_arguments "$@"
    
    # Show configuration
    if [[ "$VERBOSE" == "true" || "$DRY_RUN" == "true" ]]; then
        echo ""
        log_info "Configuration:"
        echo "  - MySQL Exporter Version: $MYSQL_EXPORTER_VERSION"
        echo "  - Port: $MYSQL_EXPORTER_PORT"
        echo "  - Service User: $MYSQL_EXPORTER_USER"
        echo "  - Install Directory: $INSTALL_DIR"
        echo "  - Config Directory: $CONFIG_DIR"
        echo "  - Service Name: $SERVICE_NAME"
        echo "  - MySQL Host: $MYSQL_HOST"
        echo "  - MySQL Port: $MYSQL_PORT"
        echo "  - MySQL User: $MYSQL_USER"
        echo "  - MySQL Database: ${MYSQL_DATABASE:-default}"
        echo "  - Prometheus Config: $PROMETHEUS_CONFIG"
        echo "  - Prometheus Service: $PROMETHEUS_SERVICE"
        echo "  - Target Hosts: ${TARGET_HOSTS:-localhost:$MYSQL_EXPORTER_PORT}"
        echo "  - Config File: ${CONFIG_FILE:-auto-generated}"
        echo "  - Dry Run: $DRY_RUN"
        echo "  - Force Install: $FORCE_INSTALL"
        echo "  - Skip Prometheus Config: $SKIP_PROMETHEUS_CONFIG"
        echo "  - Skip MySQL User Creation: $SKIP_MYSQL_USER_CREATION"
        echo ""
    fi

    # Pre-flight checks
    check_root
    detect_os
    check_existing_installation
    install_dependencies
    prompt_credentials
    
    if [[ "$SKIP_MYSQL_USER_CREATION" == "false" ]]; then
        test_mysql_connection
        create_mysql_user
    fi

    # Installation steps
    create_user
    download_and_install
    create_config
    create_service
    start_service
    test_endpoint
    update_prometheus_config
    restart_prometheus
    show_status

    log_success "MySQL Exporter setup completed successfully!"
}

# Run main function with all arguments
main "$@"