#!/bin/bash
# Auspex Alerting Engine Startup Script
# ======================================
# Starts the alerting daemon with proper environment configuration

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration file path
CONFIG_FILE="$SCRIPT_DIR/config/auspex.conf"

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Configuration file not found: $CONFIG_FILE"
    echo "Please create the config file or update the path in this script."
    exit 1
fi

# Load environment variables from config
echo "Loading configuration from $CONFIG_FILE"
export $(cat "$CONFIG_FILE" | grep -v '^#' | grep -v '^$' | xargs)

# Check if alerter is enabled
if [ "$AUSPEX_ALERTER_ENABLED" != "true" ]; then
    echo "Alerting engine is disabled (AUSPEX_ALERTER_ENABLED != true)"
    echo "To enable, set AUSPEX_ALERTER_ENABLED=true in $CONFIG_FILE"
    exit 0
fi

# Check database connection
echo "Checking database connection..."
if ! command -v psql &> /dev/null; then
    echo "WARNING: psql not found, skipping database check"
else
    PGPASSWORD="$AUSPEX_DB_PASSWORD" psql -h "$AUSPEX_DB_HOST" -p "$AUSPEX_DB_PORT" \
        -U "$AUSPEX_DB_USER" -d "$AUSPEX_DB_NAME" -c "SELECT 1" &> /dev/null
    if [ $? -ne 0 ]; then
        echo "ERROR: Cannot connect to database"
        echo "Please check your database configuration in $CONFIG_FILE"
        exit 1
    fi
    echo "✓ Database connection OK"
fi

# Check if alerting schema exists
echo "Checking alerting schema..."
PGPASSWORD="$AUSPEX_DB_PASSWORD" psql -h "$AUSPEX_DB_HOST" -p "$AUSPEX_DB_PORT" \
    -U "$AUSPEX_DB_USER" -d "$AUSPEX_DB_NAME" \
    -c "SELECT 1 FROM information_schema.tables WHERE table_name='alert_channels'" &> /dev/null
if [ $? -ne 0 ]; then
    echo "WARNING: Alerting schema not found. Run: psql -U $AUSPEX_DB_USER -d $AUSPEX_DB_NAME -f db-alerting-schema.sql"
    echo "Continuing anyway..."
fi

# Check if Go is installed
if ! command -v go &> /dev/null; then
    echo "ERROR: Go is not installed"
    echo "Please install Go 1.18+ to run the alerter daemon"
    exit 1
fi

# Start the alerter
echo ""
echo "=========================================="
echo "Starting Auspex Alerting Engine"
echo "=========================================="
echo "Check interval: ${AUSPEX_ALERTER_CHECK_INTERVAL_SECONDS}s"
echo "Dedup window: ${AUSPEX_ALERTER_DEDUP_WINDOW_MINUTES}min"
echo "SMTP: ${AUSPEX_SMTP_HOST}:${AUSPEX_SMTP_PORT}"
echo "=========================================="
echo ""

cd "$SCRIPT_DIR"
exec go run cmd/alerter/main.go
