#!/bin/bash

# Auspex Database Setup Script
# This script creates the PostgreSQL database and initializes the schema

set -e  # Exit on error

# Load configuration
CONFIG_FILE="/Users/mcclainje/Documents/Code/auspex/config/auspex.conf"
if [ -f "$CONFIG_FILE" ]; then
    export $(grep -v '^#' "$CONFIG_FILE" | xargs)
else
    echo "Warning: Config file not found at $CONFIG_FILE"
    echo "Using default values..."
    AUSPEX_DB_HOST=${AUSPEX_DB_HOST:-localhost}
    AUSPEX_DB_PORT=${AUSPEX_DB_PORT:-5432}
    AUSPEX_DB_NAME=${AUSPEX_DB_NAME:-auspexdb}
    AUSPEX_DB_USER=${AUSPEX_DB_USER:-auspex}
    AUSPEX_DB_PASSWORD=${AUSPEX_DB_PASSWORD:-yourpassword}
fi

echo "========================================="
echo "Auspex Database Setup"
echo "========================================="
echo "Host:     $AUSPEX_DB_HOST"
echo "Port:     $AUSPEX_DB_PORT"
echo "Database: $AUSPEX_DB_NAME"
echo "User:     $AUSPEX_DB_USER"
echo "========================================="
echo

# Check if PostgreSQL is installed
if ! command -v psql &> /dev/null; then
    echo "Error: PostgreSQL client (psql) not found."
    echo "Please install PostgreSQL first:"
    echo "  macOS:   brew install postgresql"
    echo "  Ubuntu:  sudo apt-get install postgresql-client"
    exit 1
fi

# Check if PostgreSQL server is running
echo "Checking PostgreSQL connection..."
if ! pg_isready -h "$AUSPEX_DB_HOST" -p "$AUSPEX_DB_PORT" &> /dev/null; then
    echo "Error: Cannot connect to PostgreSQL server at $AUSPEX_DB_HOST:$AUSPEX_DB_PORT"
    echo "Please ensure PostgreSQL is running:"
    echo "  macOS:   brew services start postgresql"
    echo "  Ubuntu:  sudo systemctl start postgresql"
    exit 1
fi

echo "PostgreSQL is running."
echo

# Step 1: Create database user if it doesn't exist
echo "Step 1: Creating database user '$AUSPEX_DB_USER' (if needed)..."
psql -h "$AUSPEX_DB_HOST" -p "$AUSPEX_DB_PORT" -U postgres -tc \
    "SELECT 1 FROM pg_user WHERE usename = '$AUSPEX_DB_USER'" | grep -q 1 || \
    psql -h "$AUSPEX_DB_HOST" -p "$AUSPEX_DB_PORT" -U postgres -c \
    "CREATE USER $AUSPEX_DB_USER WITH PASSWORD '$AUSPEX_DB_PASSWORD';"

echo "User created or already exists."
echo

# Step 2: Create database if it doesn't exist
echo "Step 2: Creating database '$AUSPEX_DB_NAME' (if needed)..."
psql -h "$AUSPEX_DB_HOST" -p "$AUSPEX_DB_PORT" -U postgres -tc \
    "SELECT 1 FROM pg_database WHERE datname = '$AUSPEX_DB_NAME'" | grep -q 1 || \
    psql -h "$AUSPEX_DB_HOST" -p "$AUSPEX_DB_PORT" -U postgres -c \
    "CREATE DATABASE $AUSPEX_DB_NAME OWNER $AUSPEX_DB_USER;"

echo "Database created or already exists."
echo

# Step 3: Run schema initialization
echo "Step 3: Initializing database schema..."
SQL_FILE="/Users/mcclainje/Documents/Code/auspex/db-init-new.sql"

if [ ! -f "$SQL_FILE" ]; then
    echo "Error: SQL initialization file not found at $SQL_FILE"
    exit 1
fi

PGPASSWORD="$AUSPEX_DB_PASSWORD" psql \
    -h "$AUSPEX_DB_HOST" \
    -p "$AUSPEX_DB_PORT" \
    -U "$AUSPEX_DB_USER" \
    -d "$AUSPEX_DB_NAME" \
    -f "$SQL_FILE"

echo
echo "========================================="
echo "Database setup completed successfully!"
echo "========================================="
echo
echo "Next steps:"
echo "1. Review the sample data in the database"
echo "2. Update config/auspex.conf if needed"
echo "3. Start the poller: go run cmd/poller/main.go"
echo "4. Start the API: node webui/server.js"
echo "5. Open http://localhost:8080 in your browser"
echo
