#!/bin/bash

# Auspex Systemd Service Uninstallation Script

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}=========================================${NC}"
echo -e "${RED}Auspex Systemd Service Uninstaller${NC}"
echo -e "${RED}=========================================${NC}"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root or with sudo${NC}"
    exit 1
fi

# Default installation directory
INSTALL_DIR="/opt/auspex"
read -p "Installation directory to remove [${INSTALL_DIR}]: " USER_DIR
INSTALL_DIR="${USER_DIR:-$INSTALL_DIR}"

echo
echo -e "${YELLOW}This will:${NC}"
echo "  1. Stop all Auspex services"
echo "  2. Disable services from auto-start"
echo "  3. Remove systemd service files"
echo "  4. Optionally remove installation directory: ${INSTALL_DIR}"
echo "  5. Optionally remove auspex user"
echo

read -p "Continue with uninstallation? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstallation cancelled."
    exit 0
fi

# Stop services
echo
echo -e "${YELLOW}Stopping services...${NC}"
systemctl stop auspex-poller.service 2>/dev/null || echo "  auspex-poller not running"
systemctl stop auspex-alerter.service 2>/dev/null || echo "  auspex-alerter not running"
systemctl stop auspex-api.service 2>/dev/null || echo "  auspex-api not running"

# Disable services
echo -e "${YELLOW}Disabling services...${NC}"
systemctl disable auspex-poller.service 2>/dev/null || true
systemctl disable auspex-alerter.service 2>/dev/null || true
systemctl disable auspex-api.service 2>/dev/null || true

# Remove service files
echo -e "${YELLOW}Removing systemd service files...${NC}"
rm -f /etc/systemd/system/auspex-poller.service
rm -f /etc/systemd/system/auspex-alerter.service
rm -f /etc/systemd/system/auspex-api.service

# Reload systemd
systemctl daemon-reload

# Remove installation directory
echo
read -p "Remove installation directory ${INSTALL_DIR}? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Removing ${INSTALL_DIR}...${NC}"
    rm -rf "${INSTALL_DIR}"
    echo "  Directory removed"
else
    echo "  Keeping installation directory"
fi

# Remove user
echo
read -p "Remove auspex user? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    userdel auspex 2>/dev/null && echo "  User removed" || echo "  User not found or already removed"
else
    echo "  Keeping auspex user"
fi

echo
echo -e "${GREEN}Uninstallation complete!${NC}"
echo
