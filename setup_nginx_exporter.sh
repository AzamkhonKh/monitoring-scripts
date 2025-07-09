#!/bin/bash

# setup_nginx_exporter.sh
# Script to install and configure nginx-prometheus-exporter for Prometheus monitoring

set -e

# Default parameters
NGINX_EXPORTER_VERSION="1.4.2"
EXPORTER_PORT=9113
EXPORTER_USER="nginx_exporter"
EXPORTER_SERVICE="/etc/systemd/system/nginx-exporter.service"
PROMETHEUS_CONFIG="/etc/prometheus/prometheus.yml"
NGINX_STATUS_URL="http://localhost/status"
EXPORTER_BIN="/usr/local/bin/nginx-prometheus-exporter"

usage() {
    echo "Usage: $0 [-v version] [-p exporter_port] [-u nginx_status_url] [-c prometheus_config]"
    echo "  -v  NGINX exporter version (default: $NGINX_EXPORTER_VERSION)"
    echo "  -p  Exporter listen port (default: $EXPORTER_PORT)"
    echo "  -u  NGINX status URL (default: $NGINX_STATUS_URL)"
    echo "  -c  Prometheus config file (default: $PROMETHEUS_CONFIG)"
    exit 1
}

while getopts "v:p:u:c:h" opt; do
    case $opt in
        v) NGINX_EXPORTER_VERSION="$OPTARG" ;;
        p) EXPORTER_PORT="$OPTARG" ;;
        u) NGINX_STATUS_URL="$OPTARG" ;;
        c) PROMETHEUS_CONFIG="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

echo "Installing nginx-prometheus-exporter v$NGINX_EXPORTER_VERSION..."

# Download exporter
cd /tmp
wget -q https://github.com/nginxinc/nginx-prometheus-exporter/releases/download/v${NGINX_EXPORTER_VERSION}/nginx-prometheus-exporter_${NGINX_EXPORTER_VERSION}_linux_amd64.tar.gz
tar -xzf nginx-prometheus-exporter_${NGINX_EXPORTER_VERSION}_linux_amd64.tar.gz
sudo mv nginx-prometheus-exporter /usr/local/bin/
sudo chmod +x /usr/local/bin/nginx-prometheus-exporter

# Create exporter user if not exists
if ! id "$EXPORTER_USER" &>/dev/null; then
    sudo useradd --no-create-home --shell /bin/false $EXPORTER_USER
fi

# Create systemd service
sudo tee $EXPORTER_SERVICE > /dev/null <<EOF
[Unit]
Description=NGINX Prometheus Exporter
After=network.target

[Service]
User=$EXPORTER_USER
Group=$EXPORTER_USER
Type=simple
ExecStart=$EXPORTER_BIN -nginx.scrape-uri $NGINX_STATUS_URL -web.listen-address ":$EXPORTER_PORT"
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable nginx-exporter
sudo systemctl restart nginx-exporter

echo "nginx-prometheus-exporter service started on port $EXPORTER_PORT"

# Patch Prometheus config
if grep -q "nginx-exporter" $PROMETHEUS_CONFIG; then
    echo "Prometheus config already contains nginx-exporter job."
else
    echo "Patching Prometheus config at $PROMETHEUS_CONFIG..."
    sudo tee -a $PROMETHEUS_CONFIG > /dev/null <<EOF

  - job_name: 'nginx-exporter'
    static_configs:
      - targets: ['localhost:$EXPORTER_PORT']
EOF
    sudo systemctl reload prometheus
    echo "Prometheus config patched and reloaded."
fi

echo "Setup complete. Verify with:"
echo "  curl http://localhost:$EXPORTER_PORT/metrics"