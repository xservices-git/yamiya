#!/bin/bash
# Docker Auto Setup Script for Linux
# - Install Docker
# - Download erpc.yaml from GitHub
# - Build eRPC from source
# - Auto-restart container every 1 hour
# - Auto-update config every 15 minutes

set -e

echo "============================================================================"
echo "eRPC DOCKER AUTO SETUP - LINUX"
echo "============================================================================"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 1. Update system
echo -e "\n${GREEN}[1/7] Updating system...${NC}"
sudo apt-get update -y
sudo apt-get upgrade -y

# 2. Install Docker
echo -e "\n${GREEN}[2/7] Installing Docker...${NC}"
if ! command -v docker &> /dev/null; then
    # Install dependencies
    sudo apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Add Docker's official GPG key
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Set up repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    sudo apt-get update -y
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Start Docker
    sudo systemctl start docker
    sudo systemctl enable docker
    
    echo -e "${GREEN}✅ Docker installed successfully${NC}"
else
    echo -e "${YELLOW}✅ Docker already installed${NC}"
fi

# 3. Download erpc.yaml from YOUR GitHub repo (latest config)
echo -e "\n${GREEN}[3/7] Downloading latest erpc.yaml from your repo...${NC}"
curl -fsSL "https://raw.githubusercontent.com/xservices-git/yamiya/main/erpc.yaml" -o erpc.yaml 2>/dev/null || {
    echo -e "${YELLOW}⚠️  Failed to download from GitHub, using local config${NC}"
    if [ -f "config/erpc.yaml" ]; then
        cp config/erpc.yaml erpc.yaml
    else
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        cp "$SCRIPT_DIR/erpc-simple.yaml" erpc.yaml
    fi
}

if [ -f "erpc.yaml" ]; then
    echo -e "${GREEN}✅ erpc.yaml ready${NC}"
else
    echo -e "${RED}❌ erpc.yaml not found!${NC}"
    exit 1
fi

# 4. Clone eRPC repository
echo -e "\n${GREEN}[4/7] Cloning eRPC repository...${NC}"
if [ ! -d "erpc" ]; then
    git clone https://github.com/erpc/erpc.git
    echo -e "${GREEN}✅ Repository cloned${NC}"
else
    echo -e "${YELLOW}✅ Repository already exists${NC}"
    cd erpc
    git pull
    cd ..
fi

# 5. Build Docker image
echo -e "\n${GREEN}[5/7] Building Docker image from source...${NC}"
cd erpc
sudo docker build -t erpc-local:latest .
cd ..
echo -e "${GREEN}✅ Docker image built successfully${NC}"

# 6. Stop existing container
echo -e "\n${GREEN}[6/7] Stopping existing container...${NC}"
sudo docker stop erpc-server 2>/dev/null || true
sudo docker rm erpc-server 2>/dev/null || true

# 7. Start container
echo -e "\n${GREEN}[7/7] Starting eRPC container...${NC}"
sudo docker run -d \
    --name erpc-server \
    --restart unless-stopped \
    -p 4000:4000 \
    -p 4001:4001 \
    -v "$(pwd)/erpc.yaml:/erpc.yaml" \
    erpc-local:latest

echo -e "\n${GREEN}✅ eRPC container started successfully${NC}"

# 8. Setup auto-restart service (every 1 hour)
echo -e "\n${GREEN}[BONUS] Setting up auto-restart service...${NC}"

# Create restart script
cat > /tmp/erpc-restart.sh << 'EOF'
#!/bin/bash
# Restart eRPC container to free RAM and reload config
docker restart erpc-server
echo "[$(date)] eRPC container restarted" >> /var/log/erpc-restart.log
EOF

sudo mv /tmp/erpc-restart.sh /usr/local/bin/erpc-restart.sh
sudo chmod +x /usr/local/bin/erpc-restart.sh

# Create systemd timer for hourly restart
sudo tee /etc/systemd/system/erpc-restart.timer > /dev/null << EOF
[Unit]
Description=Restart eRPC container every hour
Requires=erpc-restart.service

[Timer]
OnBootSec=1h
OnUnitActiveSec=1h
Unit=erpc-restart.service

[Install]
WantedBy=timers.target
EOF

# Create systemd service
sudo tee /etc/systemd/system/erpc-restart.service > /dev/null << EOF
[Unit]
Description=Restart eRPC container
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/erpc-restart.sh

[Install]
WantedBy=multi-user.target
EOF

# Enable and start timer
sudo systemctl daemon-reload
sudo systemctl enable erpc-restart.timer
sudo systemctl start erpc-restart.timer

echo -e "${GREEN}✅ Auto-restart service enabled (every 1 hour)${NC}"

# 9. Setup config auto-update (every 15 minutes)
echo -e "\n${GREEN}[BONUS] Setting up config auto-update...${NC}"

# Create update script
cat > /tmp/erpc-update-config.sh << 'EOF'
#!/bin/bash
# Download latest erpc.yaml from GitHub repo
cd /root/.erpc || exit 1
curl -fsSL "https://raw.githubusercontent.com/xservices-git/yamiya/main/erpc.yaml" -o erpc.yaml.new
if [ -f "erpc.yaml.new" ]; then
    mv erpc.yaml.new erpc.yaml
    docker restart erpc-server >/dev/null 2>&1
    echo "[$(date)] Config updated and container restarted" >> /var/log/erpc-config-update.log
fi
EOF

sudo mv /tmp/erpc-update-config.sh /usr/local/bin/erpc-update-config.sh
sudo chmod +x /usr/local/bin/erpc-update-config.sh

# Create systemd timer for 15-minute updates
sudo tee /etc/systemd/system/erpc-update-config.timer > /dev/null << EOF
[Unit]
Description=Update eRPC config every 15 minutes
Requires=erpc-update-config.service

[Timer]
OnBootSec=15min
OnUnitActiveSec=15min
Unit=erpc-update-config.service

[Install]
WantedBy=timers.target
EOF

# Create systemd service
sudo tee /etc/systemd/system/erpc-update-config.service > /dev/null << EOF
[Unit]
Description=Update eRPC config from GitHub
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/erpc-update-config.sh

[Install]
WantedBy=multi-user.target
EOF

# Enable and start timer
sudo systemctl daemon-reload
sudo systemctl enable erpc-update-config.timer
sudo systemctl start erpc-update-config.timer

echo -e "${GREEN}✅ Config auto-update enabled (every 15 minutes)${NC}"

# Summary
echo ""
echo "============================================================================"
echo -e "${GREEN}SETUP COMPLETE!${NC}"
echo "============================================================================"
echo ""
echo "eRPC Server:"
echo "  - HTTP: http://localhost:4000"
echo "  - Metrics: http://localhost:4001"
echo ""
echo "Services:"
echo "  - Auto-restart: Every 1 hour (free RAM + reload config)"
echo "  - Config update: Every 15 minutes (download from GitHub)"
echo ""
echo "Commands:"
echo "  - Check status: sudo docker ps"
echo "  - View logs: sudo docker logs erpc-server"
echo "  - Restart manually: sudo docker restart erpc-server"
echo "  - Stop: sudo docker stop erpc-server"
echo ""
echo "Service status:"
echo "  - Restart timer: sudo systemctl status erpc-restart.timer"
echo "  - Update timer: sudo systemctl status erpc-update-config.timer"
echo ""
echo "============================================================================"
