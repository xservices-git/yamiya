#!/bin/bash
# Install eRPC monitor as systemd service (Linux only)

set -e

if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    echo "❌ This script is for Linux only"
    exit 1
fi

if [ "$EUID" -ne 0 ]; then
    echo "❌ Please run as root (sudo)"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_FILE="/etc/systemd/system/erpc-monitor.service"

echo "========================================="
echo "Installing eRPC Monitor Service"
echo "========================================="
echo ""

# Update WorkingDirectory in service file
sed "s|WorkingDirectory=.*|WorkingDirectory=$SCRIPT_DIR|g" \
    "$SCRIPT_DIR/erpc-monitor.service" > "$SERVICE_FILE.tmp"

sed "s|ExecStart=.*|ExecStart=$SCRIPT_DIR/docker-setup.sh|g" \
    "$SERVICE_FILE.tmp" > "$SERVICE_FILE"

rm "$SERVICE_FILE.tmp"

# Make script executable
chmod +x "$SCRIPT_DIR/docker-setup.sh"

# Reload systemd
systemctl daemon-reload

# Enable service
systemctl enable erpc-monitor

echo "✅ Service installed"
echo ""
echo "Commands:"
echo "  sudo systemctl start erpc-monitor    # Start"
echo "  sudo systemctl stop erpc-monitor     # Stop"
echo "  sudo systemctl status erpc-monitor   # Status"
echo "  sudo systemctl restart erpc-monitor  # Restart"
echo "  sudo journalctl -u erpc-monitor -f   # View logs"
echo ""
echo "To start now:"
echo "  sudo systemctl start erpc-monitor"
