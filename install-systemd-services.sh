#!/bin/bash

# Auspex Systemd Service Installation Script
# This script installs systemd services for poller, alerter, and API server

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Auspex Systemd Service Installer${NC}"
echo -e "${GREEN}=========================================${NC}"
echo

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default installation directory
INSTALL_DIR="/opt/auspex"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root or with sudo${NC}"
    exit 1
fi

# Ask for installation directory
read -p "Installation directory [${INSTALL_DIR}]: " USER_DIR
INSTALL_DIR="${USER_DIR:-$INSTALL_DIR}"

echo
echo -e "${YELLOW}Installation Configuration:${NC}"
echo "  Source directory: ${SCRIPT_DIR}"
echo "  Install directory: ${INSTALL_DIR}"
echo "  Systemd services: /etc/systemd/system/"
echo

read -p "Proceed with installation? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
fi

# Step 1: Create installation directory
echo
echo -e "${GREEN}Step 1: Creating installation directory...${NC}"
mkdir -p "${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}/config"
mkdir -p "${INSTALL_DIR}/bin"
mkdir -p "${INSTALL_DIR}/webui"
mkdir -p "${INSTALL_DIR}/logs"

# Step 2: Copy files
echo -e "${GREEN}Step 2: Copying application files...${NC}"

# Copy Go source files
cp -r "${SCRIPT_DIR}/cmd" "${INSTALL_DIR}/"
cp "${SCRIPT_DIR}/go.mod" "${INSTALL_DIR}/"
cp "${SCRIPT_DIR}/go.sum" "${INSTALL_DIR}/" 2>/dev/null || true

# Copy web UI
cp -r "${SCRIPT_DIR}/webui/"* "${INSTALL_DIR}/webui/"

# Copy SQL files
cp "${SCRIPT_DIR}/db-init-new.sql" "${INSTALL_DIR}/"
cp "${SCRIPT_DIR}/db-alerting-schema.sql" "${INSTALL_DIR}/" 2>/dev/null || true

# Copy config template if config doesn't exist
if [ ! -f "${INSTALL_DIR}/config/auspex.conf" ]; then
    if [ -f "${SCRIPT_DIR}/config/auspex.conf" ]; then
        cp "${SCRIPT_DIR}/config/auspex.conf" "${INSTALL_DIR}/config/"
        echo -e "${YELLOW}  Copied existing config file${NC}"
    elif [ -f "${SCRIPT_DIR}/config/auspex.conf.template" ]; then
        cp "${SCRIPT_DIR}/config/auspex.conf.template" "${INSTALL_DIR}/config/auspex.conf"
        echo -e "${YELLOW}  Created config from template - EDIT ${INSTALL_DIR}/config/auspex.conf${NC}"
    fi
fi

# Set secure permissions on config
chmod 600 "${INSTALL_DIR}/config/auspex.conf" 2>/dev/null || true

# Step 3: Build Go binaries
echo -e "${GREEN}Step 3: Building Go binaries...${NC}"
cd "${INSTALL_DIR}"

# Check if Go is installed
if ! command -v go &> /dev/null; then
    echo -e "${RED}Error: Go is not installed. Please install Go 1.21+ first.${NC}"
    exit 1
fi

# Build poller
echo "  Building poller..."
go build -o "${INSTALL_DIR}/bin/auspex-poller" "${INSTALL_DIR}/cmd/poller/main.go"

# Build alerter
echo "  Building alerter..."
go build -o "${INSTALL_DIR}/bin/auspex-alerter" "${INSTALL_DIR}/cmd/alerter/main.go"

echo -e "${GREEN}  Binaries built successfully${NC}"

# Step 4: Create auspex user (if doesn't exist)
echo -e "${GREEN}Step 4: Creating auspex user...${NC}"
if ! id "auspex" &>/dev/null; then
    useradd -r -s /bin/false -d "${INSTALL_DIR}" -c "Auspex SNMP Monitor" auspex
    echo "  User 'auspex' created"
else
    echo "  User 'auspex' already exists"
fi

# Set ownership
chown -R auspex:auspex "${INSTALL_DIR}"

# Step 5: Create systemd service files
echo -e "${GREEN}Step 5: Creating systemd service files...${NC}"

# Poller service
cat > /etc/systemd/system/auspex-poller.service << EOF
[Unit]
Description=Auspex SNMP Poller
Documentation=https://github.com/yourusername/auspex
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=auspex
Group=auspex
WorkingDirectory=${INSTALL_DIR}
EnvironmentFile=${INSTALL_DIR}/config/auspex.conf

ExecStart=${INSTALL_DIR}/bin/auspex-poller

# Restart policy
Restart=on-failure
RestartSec=5s

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${INSTALL_DIR}/logs

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=auspex-poller

[Install]
WantedBy=multi-user.target
EOF

echo "  Created auspex-poller.service"

# Alerter service
cat > /etc/systemd/system/auspex-alerter.service << EOF
[Unit]
Description=Auspex Alerting Engine
Documentation=https://github.com/yourusername/auspex
After=network.target postgresql.service auspex-poller.service
Wants=postgresql.service

[Service]
Type=simple
User=auspex
Group=auspex
WorkingDirectory=${INSTALL_DIR}
EnvironmentFile=${INSTALL_DIR}/config/auspex.conf

ExecStart=${INSTALL_DIR}/bin/auspex-alerter

# Restart policy
Restart=on-failure
RestartSec=5s

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${INSTALL_DIR}/logs

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=auspex-alerter

[Install]
WantedBy=multi-user.target
EOF

echo "  Created auspex-alerter.service"

# API Server service
cat > /etc/systemd/system/auspex-api.service << EOF
[Unit]
Description=Auspex API Server
Documentation=https://github.com/yourusername/auspex
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=auspex
Group=auspex
WorkingDirectory=${INSTALL_DIR}/webui
EnvironmentFile=${INSTALL_DIR}/config/auspex.conf

ExecStart=/usr/bin/node ${INSTALL_DIR}/webui/server.js

# Restart policy
Restart=on-failure
RestartSec=5s

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${INSTALL_DIR}/logs

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=auspex-api

[Install]
WantedBy=multi-user.target
EOF

echo "  Created auspex-api.service"

# Step 6: Install Node.js dependencies
echo -e "${GREEN}Step 6: Installing Node.js dependencies...${NC}"
cd "${INSTALL_DIR}/webui"

# Check if npm is installed
if ! command -v npm &> /dev/null; then
    echo -e "${YELLOW}  Warning: npm not found. Skipping dependency installation.${NC}"
    echo -e "${YELLOW}  Install Node.js and run: cd ${INSTALL_DIR}/webui && npm install${NC}"
else
    npm install
    echo "  Node.js dependencies installed"
fi

# Step 7: Reload systemd
echo -e "${GREEN}Step 7: Reloading systemd daemon...${NC}"
systemctl daemon-reload

# Step 8: Enable services
echo -e "${GREEN}Step 8: Enabling services...${NC}"
systemctl enable auspex-poller.service
systemctl enable auspex-alerter.service
systemctl enable auspex-api.service
echo "  Services enabled (will start on boot)"

echo
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo
echo -e "${YELLOW}Important: Edit configuration before starting services${NC}"
echo "  Config file: ${INSTALL_DIR}/config/auspex.conf"
echo "  Update database password and SMTP settings"
echo
echo -e "${YELLOW}Service Management Commands:${NC}"
echo "  Start services:"
echo "    sudo systemctl start auspex-poller"
echo "    sudo systemctl start auspex-alerter"
echo "    sudo systemctl start auspex-api"
echo
echo "  Stop services:"
echo "    sudo systemctl stop auspex-poller"
echo "    sudo systemctl stop auspex-alerter"
echo "    sudo systemctl stop auspex-api"
echo
echo "  Check status:"
echo "    sudo systemctl status auspex-poller"
echo "    sudo systemctl status auspex-alerter"
echo "    sudo systemctl status auspex-api"
echo
echo "  View logs:"
echo "    sudo journalctl -u auspex-poller -f"
echo "    sudo journalctl -u auspex-alerter -f"
echo "    sudo journalctl -u auspex-api -f"
echo
echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. Edit ${INSTALL_DIR}/config/auspex.conf"
echo "  2. Initialize database: sudo -u postgres psql < ${INSTALL_DIR}/db-init-new.sql"
echo "  3. Start services: sudo systemctl start auspex-{poller,alerter,api}"
echo "  4. Open http://localhost:8080 in browser"
echo
