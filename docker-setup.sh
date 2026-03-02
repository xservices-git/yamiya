#!/bin/bash
# Docker eRPC Setup - Auto install, run, restart every 2 hours, auto-update config
# For Linux/macOS

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ERPC_CONFIG="$SCRIPT_DIR/erpc.yaml"
GITHUB_CONFIG_URL="https://raw.githubusercontent.com/xservices-git/yamiya/refs/heads/main/erpc.yaml"
UPDATE_INTERVAL=600  # 10 minutes
RESTART_INTERVAL=7200  # 2 hours
CONTAINER_NAME="erpc-server"
IMAGE_NAME="ghcr.io/erpc/erpc:latest"

echo "========================================"
echo "eRPC Docker Setup - Full Automation"
echo "========================================"
echo "Features:"
echo "  - Auto install Docker if not found"
echo "  - Auto download eRPC config from GitHub"
echo "  - Auto restart container every 2 hours"
echo "  - Auto update config every 10 minutes"
echo "========================================"
echo ""

# Function: Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function: Install Docker
install_docker() {
    echo "🔧 Installing Docker..."
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        if command_exists apt-get; then
            # Debian/Ubuntu
            sudo apt-get update
            sudo apt-get install -y ca-certificates curl gnupg
            sudo install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            sudo chmod a+r /etc/apt/keyrings/docker.gpg
            
            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
              $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
              sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            sudo apt-get update
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            
        elif command_exists yum; then
            # CentOS/RHEL
            sudo yum install -y yum-utils
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            sudo systemctl start docker
            sudo systemctl enable docker
        else
            echo "❌ Unsupported Linux distribution"
            exit 1
        fi
        
        # Add user to docker group
        sudo usermod -aG docker $USER
        echo "✅ Docker installed. You may need to log out and back in for group changes."
        
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command_exists brew; then
            brew install --cask docker
            echo "✅ Docker installed via Homebrew"
            echo "⚠️  Please start Docker Desktop manually"
            exit 0
        else
            echo "❌ Homebrew not found. Install from: https://brew.sh/"
            echo "   Or download Docker Desktop: https://www.docker.com/products/docker-desktop"
            exit 1
        fi
    else
        echo "❌ Unsupported OS: $OSTYPE"
        exit 1
    fi
}

# Function: Download config from GitHub
download_config() {
    echo "📥 Downloading config from GitHub..."
    
    if curl -fsSL "$GITHUB_CONFIG_URL" -o "$ERPC_CONFIG.tmp"; then
        # Validate YAML
        if grep -q "logLevel:" "$ERPC_CONFIG.tmp" && grep -q "projects:" "$ERPC_CONFIG.tmp"; then
            mv "$ERPC_CONFIG.tmp" "$ERPC_CONFIG"
            echo "✅ Config downloaded and validated"
            return 0
        else
            echo "⚠️  Downloaded config is invalid, keeping current config"
            rm -f "$ERPC_CONFIG.tmp"
            return 1
        fi
    else
        echo "⚠️  Failed to download config from GitHub"
        rm -f "$ERPC_CONFIG.tmp"
        return 1
    fi
}

# Function: Check if config changed
config_changed() {
    if [ ! -f "$ERPC_CONFIG" ]; then
        return 0  # No config, need download
    fi
    
    # Download to temp and compare
    if curl -fsSL "$GITHUB_CONFIG_URL" -o "$ERPC_CONFIG.tmp" 2>/dev/null; then
        if ! cmp -s "$ERPC_CONFIG" "$ERPC_CONFIG.tmp"; then
            rm -f "$ERPC_CONFIG.tmp"
            return 0  # Changed
        fi
        rm -f "$ERPC_CONFIG.tmp"
        return 1  # Not changed
    fi
    
    return 1  # Download failed, assume not changed
}

# Function: Start eRPC container
start_erpc() {
    echo "🚀 Starting eRPC container..."
    
    # Stop and remove old container
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
    
    # Run new container
    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        -p 4000:4000 \
        -p 4001:4001 \
        -v "$ERPC_CONFIG:/app/erpc.yaml:ro" \
        "$IMAGE_NAME"
    
    echo "✅ eRPC container started"
    echo "   HTTP: http://localhost:4000"
    echo "   Metrics: http://localhost:4001/metrics"
}

# Function: Restart eRPC container
restart_erpc() {
    echo "🔄 Restarting eRPC container..."
    docker restart "$CONTAINER_NAME"
    echo "✅ Container restarted"
}

# Function: Reload config (restart container)
reload_config() {
    echo "🔄 Reloading config..."
    docker restart "$CONTAINER_NAME"
    echo "✅ Config reloaded"
}

# Function: Install as systemd service (Linux only)
install_systemd_service() {
    echo ""
    echo "🔧 Installing systemd service..."
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        echo "⚠️  Need root privileges to install service"
        echo "   Re-running with sudo..."
        
        # Create service file content
        SERVICE_CONTENT="[Unit]
Description=eRPC Docker Monitor - Auto restart & update
After=docker.service
Requires=docker.service

[Service]
Type=simple
User=root
WorkingDirectory=$SCRIPT_DIR
ExecStart=$SCRIPT_DIR/docker-setup.sh --service-mode
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
Environment=\"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\"

[Install]
WantedBy=multi-user.target"
        
        # Write service file
        echo "$SERVICE_CONTENT" | sudo tee /etc/systemd/system/erpc-monitor.service > /dev/null
        
        # Reload and enable
        sudo systemctl daemon-reload
        sudo systemctl enable erpc-monitor
        
        echo "✅ Service installed"
        echo ""
        echo "Commands:"
        echo "  sudo systemctl start erpc-monitor    # Start"
        echo "  sudo systemctl stop erpc-monitor     # Stop"
        echo "  sudo systemctl status erpc-monitor   # Status"
        echo "  sudo systemctl restart erpc-monitor  # Restart"
        echo "  sudo journalctl -u erpc-monitor -f   # View logs"
        echo ""
        
        read -p "Start service now? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo systemctl start erpc-monitor
            echo "✅ Service started"
            echo ""
            echo "View logs with: sudo journalctl -u erpc-monitor -f"
        else
            echo "✓ Service installed but not started"
            echo "   Start with: sudo systemctl start erpc-monitor"
        fi
        
        return 0
    fi
    
    # Already root, install directly
    SERVICE_FILE="/etc/systemd/system/erpc-monitor.service"
    
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=eRPC Docker Monitor - Auto restart & update
After=docker.service
Requires=docker.service

[Service]
Type=simple
User=root
WorkingDirectory=$SCRIPT_DIR
ExecStart=$SCRIPT_DIR/docker-setup.sh --service-mode
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable erpc-monitor
    
    echo "✅ Service installed"
    echo ""
    
    read -p "Start service now? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        systemctl start erpc-monitor
        echo "✅ Service started"
    fi
}

# Function: Background monitor (auto-restart + auto-update)
background_monitor() {
    echo ""
    echo "========================================"
    echo "BACKGROUND MONITOR STARTED"
    echo "========================================"
    echo "Auto-restart: Every 2 hours"
    echo "Auto-update: Every 10 minutes"
    echo "Press Ctrl+C to stop"
    echo "========================================"
    echo ""
    
    last_restart=$(date +%s)
    last_update=$(date +%s)
    
    while true; do
        sleep 60  # Check every minute
        
        current_time=$(date +%s)
        
        # Check if need restart (every 2 hours)
        time_since_restart=$((current_time - last_restart))
        if [ $time_since_restart -ge $RESTART_INTERVAL ]; then
            echo ""
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⏰ Auto-restart (2 hours elapsed)"
            restart_erpc
            last_restart=$(date +%s)
        fi
        
        # Check if need update (every 10 minutes)
        time_since_update=$((current_time - last_update))
        if [ $time_since_update -ge $UPDATE_INTERVAL ]; then
            echo ""
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🔍 Checking for config updates..."
            
            if config_changed; then
                echo "📥 Config changed, downloading..."
                if download_config; then
                    echo "🔄 Reloading eRPC with new config..."
                    reload_config
                    echo "✅ Config updated and reloaded"
                fi
            else
                echo "✓ Config unchanged"
            fi
            
            last_update=$(date +%s)
        fi
        
        # Show status every 5 minutes
        if [ $((current_time % 300)) -eq 0 ]; then
            restart_in=$((RESTART_INTERVAL - time_since_restart))
            update_in=$((UPDATE_INTERVAL - time_since_update))
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Status: Next restart in ${restart_in}s, next update check in ${update_in}s"
        fi
    done
}

# Main execution
main() {
    # Check if running in service mode (skip interactive prompts)
    if [[ "$1" == "--service-mode" ]]; then
        echo "🚀 Starting in service mode..."
        
        # Ensure Docker is running
        if ! docker info >/dev/null 2>&1; then
            echo "❌ Docker daemon not running"
            exit 1
        fi
        
        # Start monitor directly (no prompts)
        background_monitor
        exit 0
    fi
    
    # Check Docker
    if ! command_exists docker; then
        echo "⚠️  Docker not found"
        read -p "Install Docker automatically? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_docker
        else
            echo "❌ Docker is required. Install manually: https://docs.docker.com/get-docker/"
            exit 1
        fi
    else
        echo "✅ Docker found: $(docker --version)"
    fi
    
    # Check Docker daemon
    if ! docker info >/dev/null 2>&1; then
        echo "❌ Docker daemon not running"
        echo "   Start Docker Desktop or run: sudo systemctl start docker"
        exit 1
    fi
    
    # Pull latest image
    echo "📥 Pulling latest eRPC image..."
    docker pull "$IMAGE_NAME"
    
    # Download config from GitHub
    if [ ! -f "$ERPC_CONFIG" ]; then
        echo "⚠️  Config not found, downloading from GitHub..."
        download_config
    else
        echo "✓ Config found: $ERPC_CONFIG"
        read -p "Download latest config from GitHub? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            download_config
        fi
    fi
    
    # Verify config exists
    if [ ! -f "$ERPC_CONFIG" ]; then
        echo "❌ Config file not found: $ERPC_CONFIG"
        exit 1
    fi
    
    # Start eRPC
    start_erpc
    
    # Wait for startup
    echo "⏳ Waiting for eRPC to start..."
    sleep 5
    
    # Check health
    if curl -f http://localhost:4000/healthz >/dev/null 2>&1; then
        echo "✅ eRPC is healthy"
    else
        echo "⚠️  Health check failed, but container is running"
    fi
    
    # Show logs
    echo ""
    echo "📋 Recent logs:"
    docker logs --tail 20 "$CONTAINER_NAME"
    
    echo ""
    echo "========================================"
    echo "✅ SETUP COMPLETE"
    echo "========================================"
    echo "eRPC is running at:"
    echo "  HTTP: http://localhost:4000"
    echo "  Metrics: http://localhost:4001/metrics"
    echo ""
    echo "Useful commands:"
    echo "  docker logs -f $CONTAINER_NAME    # View logs"
    echo "  docker stop $CONTAINER_NAME       # Stop"
    echo "  docker start $CONTAINER_NAME      # Start"
    echo "  docker restart $CONTAINER_NAME    # Restart"
    echo "========================================"
    echo ""
    
    # Ask to install as service (Linux only)
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "🔧 INSTALL AS SYSTEMD SERVICE"
        echo "This will run eRPC monitor automatically on boot"
        echo ""
        read -p "Install as systemd service? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_systemd_service
        else
            # Ask to start monitor manually
            read -p "Start background monitor now? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                background_monitor
            else
                echo "✓ Setup complete. Run this script again to start monitor."
            fi
        fi
    else
        # macOS - just ask to start monitor
        read -p "Start background monitor? (auto-restart + auto-update) (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            background_monitor
        else
            echo "✓ Setup complete. Run this script again to start monitor."
        fi
    fi
}

# Run main
main "$@"
