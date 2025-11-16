#!/bin/bash

# Auspex Add Target Script
# Interactive script to add SNMP targets to the monitoring system

set -e

# Load configuration
CONFIG_FILE="/Users/mcclainje/Documents/Code/auspex/config/auspex.conf"
if [ -f "$CONFIG_FILE" ]; then
    export $(grep -v '^#' "$CONFIG_FILE" | xargs)
else
    echo "Error: Config file not found at $CONFIG_FILE"
    exit 1
fi

echo "========================================="
echo "Auspex - Add SNMP Target"
echo "========================================="
echo

# Prompt for target details
read -p "Device Name (e.g., 'Office Router'): " TARGET_NAME
read -p "IP Address or Hostname: " TARGET_HOST
read -p "SNMP Port [161]: " TARGET_PORT
TARGET_PORT=${TARGET_PORT:-161}

read -p "SNMP Community String [public]: " TARGET_COMMUNITY
TARGET_COMMUNITY=${TARGET_COMMUNITY:-public}

read -p "SNMP Version (1, 2c, 3) [2c]: " TARGET_VERSION
TARGET_VERSION=${TARGET_VERSION:-2c}

read -p "Enabled (true/false) [true]: " TARGET_ENABLED
TARGET_ENABLED=${TARGET_ENABLED:-true}

echo
echo "========================================="
echo "Target Details:"
echo "========================================="
echo "Name:       $TARGET_NAME"
echo "Host:       $TARGET_HOST"
echo "Port:       $TARGET_PORT"
echo "Community:  $TARGET_COMMUNITY"
echo "Version:    $TARGET_VERSION"
echo "Enabled:    $TARGET_ENABLED"
echo "========================================="
echo

read -p "Add this target? (y/n): " CONFIRM

if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Cancelled."
    exit 0
fi

# Add target via API
echo
echo "Adding target via API..."

RESPONSE=$(curl -s -X POST http://localhost:${AUSPEX_API_PORT:-8080}/api/targets \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"$TARGET_NAME\",
    \"host\": \"$TARGET_HOST\",
    \"port\": $TARGET_PORT,
    \"community\": \"$TARGET_COMMUNITY\",
    \"snmp_version\": \"$TARGET_VERSION\",
    \"enabled\": $TARGET_ENABLED
  }")

if echo "$RESPONSE" | grep -q '"id"'; then
    TARGET_ID=$(echo "$RESPONSE" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
    echo
    echo "✓ Target added successfully!"
    echo "  ID: $TARGET_ID"
    echo "  Next poll will occur within 60 seconds"
    echo
    echo "View target details:"
    echo "  http://localhost:${AUSPEX_API_PORT:-8080}/target.html?id=$TARGET_ID"
    echo
else
    echo
    echo "✗ Error adding target:"
    echo "$RESPONSE"
    exit 1
fi
