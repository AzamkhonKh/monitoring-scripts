#!/bin/bash
# Configure Promtail to send Apache logs to Loki
# Usage: ./configure_promtail_apache.sh [--promtail-config /etc/promtail/promtail-config.yaml] [--apache-access-log /var/log/httpd/access_log] [--apache-error-log /var/log/httpd/error_log]

set -euo pipefail

PROMTAIL_CONFIG="/etc/promtail/promtail-config.yaml"
APACHE_ACCESS_LOG="/var/log/httpd/access_log"
APACHE_ERROR_LOG="/var/log/httpd/error_log"
RESTART_PROMTAIL=true

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --promtail-config)
            PROMTAIL_CONFIG="$2"; shift 2;;
        --apache-access-log)
            APACHE_ACCESS_LOG="$2"; shift 2;;
        --apache-error-log)
            APACHE_ERROR_LOG="$2"; shift 2;;
        --no-restart)
            RESTART_PROMTAIL=false; shift;;
        -h|--help)
            echo "Usage: $0 [--promtail-config PATH] [--apache-access-log PATH] [--apache-error-log PATH] [--no-restart]"; exit 0;;
        *)
            echo "Unknown option: $1"; exit 1;;
    esac
done

# Detect Apache log files if not provided
if [[ ! -f "$APACHE_ACCESS_LOG" && -f "/var/log/apache2/access.log" ]]; then
    APACHE_ACCESS_LOG="/var/log/apache2/access.log"
fi
if [[ ! -f "$APACHE_ERROR_LOG" && -f "/var/log/apache2/error.log" ]]; then
    APACHE_ERROR_LOG="/var/log/apache2/error.log"
fi

if [[ ! -f "$APACHE_ACCESS_LOG" ]]; then
    echo "[WARNING] Apache access log not found at $APACHE_ACCESS_LOG" >&2
fi
if [[ ! -f "$APACHE_ERROR_LOG" ]]; then
    echo "[WARNING] Apache error log not found at $APACHE_ERROR_LOG" >&2
fi

# Backup Promtail config
if [[ -f "$PROMTAIL_CONFIG" ]]; then
    cp "$PROMTAIL_CONFIG" "$PROMTAIL_CONFIG.bak.$(date +%Y%m%d_%H%M%S)"
fi

echo "[INFO] Configuring Promtail to scrape Apache logs..."

# Append Apache jobs to Promtail config
grep -q 'job_name: apache_access' "$PROMTAIL_CONFIG" 2>/dev/null || cat >> "$PROMTAIL_CONFIG" <<EOF

# Apache Access Log
scrape_configs:
  - job_name: apache_access
    static_configs:
      - targets: [localhost]
        labels:
          job: apache_access
          __path__: $APACHE_ACCESS_LOG
  - job_name: apache_error
    static_configs:
      - targets: [localhost]
        labels:
          job: apache_error
          __path__: $APACHE_ERROR_LOG
EOF

echo "[INFO] Promtail config updated: $PROMTAIL_CONFIG"

if $RESTART_PROMTAIL; then
    echo "[INFO] Restarting promtail service..."
    systemctl restart promtail || systemctl start promtail
    echo "[INFO] Promtail service restarted."
else
    echo "[INFO] Promtail config updated. Please restart promtail manually if needed."
fi
