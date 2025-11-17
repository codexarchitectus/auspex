# Auspex Installation Guide

Complete step-by-step installation guide for Auspex SNMP Network Monitor.

---

## Table of Contents

1. [System Requirements](#system-requirements)
2. [Installation Overview](#installation-overview)
3. [Step 1: Install PostgreSQL](#step-1-install-postgresql)
4. [Step 2: Install Go](#step-2-install-go)
5. [Step 3: Install Node.js](#step-3-install-nodejs)
6. [Step 4: Download Auspex](#step-4-download-auspex)
7. [Step 5: Configure Database](#step-5-configure-database)
8. [Step 6: Configure Auspex](#step-6-configure-auspex)
9. [Step 7: Install Dependencies](#step-7-install-dependencies)
10. [Step 8: Start Services](#step-8-start-services)
11. [Step 9: Verify Installation](#step-9-verify-installation)
12. [Next Steps](#next-steps)
13. [Troubleshooting](#troubleshooting)

---

## System Requirements

### Minimum Requirements
- **OS:** Linux (Ubuntu 20.04+, CentOS 8+, Debian 11+), macOS 11+, or Windows 10+ with WSL2
- **CPU:** 1 core (2+ cores recommended for 100+ devices)
- **RAM:** 512 MB (1 GB+ recommended)
- **Disk:** 2 GB free space (more for historical data)
- **Network:** Access to SNMP devices on UDP port 161

### Software Requirements
- **PostgreSQL:** 12 or higher
- **Go:** 1.18 or higher
- **Node.js:** 16 or higher
- **Network Tools:** snmpwalk (optional, for testing)

### Supported Platforms
| Platform | Tested | Notes |
|----------|--------|-------|
| Ubuntu 20.04+ | ✅ | Recommended for production |
| Debian 11+ | ✅ | Recommended for production |
| CentOS/RHEL 8+ | ✅ | Use dnf for packages |
| macOS 11+ | ✅ | Great for development |
| Windows 10+ (WSL2) | ⚠️ | Use Ubuntu on WSL2 |
| Docker | ✅ | See Docker section |

---

## Installation Overview

**Estimated Time:** 20-30 minutes

**Installation Steps:**
1. Install PostgreSQL database
2. Install Go programming language
3. Install Node.js runtime
4. Download/clone Auspex
5. Configure database (create user, schema)
6. Configure Auspex (edit config file)
7. Install Go and Node.js dependencies
8. Start SNMP poller and API server
9. Verify installation via web dashboard

**Quick Install (Ubuntu/Debian):**
```bash
# All-in-one script (copy and paste)
sudo apt update && \
sudo apt install -y postgresql postgresql-contrib golang nodejs npm && \
sudo systemctl start postgresql && \
git clone https://github.com/yourusername/auspex.git && \
cd auspex && \
./setup-database.sh && \
npm install && \
go mod download
```

---

## Step 1: Install PostgreSQL

PostgreSQL is the database backend for storing targets and poll results.

### Ubuntu / Debian

```bash
# Update package list
sudo apt update

# Install PostgreSQL
sudo apt install -y postgresql postgresql-contrib

# Start PostgreSQL service
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Verify installation
pg_isready
# Expected output: /var/run/postgresql:5432 - accepting connections
```

### CentOS / RHEL

```bash
# Install PostgreSQL
sudo dnf install -y postgresql-server postgresql-contrib

# Initialize database
sudo postgresql-setup --initdb

# Start PostgreSQL service
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Verify installation
pg_isready
```

### macOS

```bash
# Install via Homebrew
brew install postgresql

# Start PostgreSQL service
brew services start postgresql

# Verify installation
pg_isready
# Expected output: /tmp/.s.PGSQL.5432 - accepting connections
```

### Verify PostgreSQL Version

```bash
psql --version
# Expected: psql (PostgreSQL) 12.x or higher
```

**Common Issues:**
- **"pg_isready: command not found"** → Add PostgreSQL bin to PATH
- **"could not connect to server"** → PostgreSQL service not running, try `sudo systemctl start postgresql`

---

## Step 2: Install Go

Go is required to run the SNMP polling daemon.

### Ubuntu / Debian

```bash
# Option 1: Install from official Ubuntu repository (may be older version)
sudo apt install -y golang

# Option 2: Install latest version manually
wget https://go.dev/dl/go1.21.5.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.21.5.linux-amd64.tar.gz

# Add to PATH (add to ~/.bashrc for persistence)
export PATH=$PATH:/usr/local/go/bin
```

### CentOS / RHEL

```bash
# Install Go
sudo dnf install -y golang

# Verify version (if too old, use manual install method above)
go version
```

### macOS

```bash
# Install via Homebrew
brew install go
```

### Verify Go Installation

```bash
go version
# Expected: go version go1.18 or higher

# Verify GOPATH
go env GOPATH
# Expected: /home/username/go or similar
```

**Common Issues:**
- **"go: command not found"** → Add `/usr/local/go/bin` to PATH
- **Version too old** → Use manual installation method above

---

## Step 3: Install Node.js

Node.js is required to run the API server and web dashboard.

### Ubuntu / Debian

```bash
# Option 1: Install from NodeSource (recommended for latest version)
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs

# Option 2: Install from Ubuntu repository (may be older)
sudo apt install -y nodejs npm
```

### CentOS / RHEL

```bash
# Install from NodeSource
curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
sudo dnf install -y nodejs
```

### macOS

```bash
# Install via Homebrew
brew install node
```

### Verify Node.js Installation

```bash
node --version
# Expected: v16.x or higher

npm --version
# Expected: 8.x or higher
```

**Common Issues:**
- **"node: command not found"** → Restart terminal or check PATH
- **Permission errors with npm** → Use NodeSource installation or configure npm prefix

---

## Step 4: Download Auspex

### Option 1: Clone from Git (Recommended)

```bash
# Clone repository
git clone https://github.com/yourusername/auspex.git

# Navigate to directory
cd auspex

# Check current directory
pwd
# Expected: /home/username/auspex or similar
```

### Option 2: Download Release Archive

```bash
# Download latest release
wget https://github.com/yourusername/auspex/archive/refs/heads/main.zip

# Extract
unzip main.zip
cd auspex-main
```

### Option 3: Manual Download

1. Visit https://github.com/yourusername/auspex
2. Click "Code" → "Download ZIP"
3. Extract to desired location
4. Open terminal in extracted directory

### Verify Download

```bash
ls -la
# Expected: You should see:
# - cmd/poller/main.go
# - webui/server.js
# - db-init-new.sql
# - README.md
# etc.
```

---

## Step 5: Configure Database

### Automated Setup (Recommended)

```bash
# Run the automated setup script
./setup-database.sh

# Follow the prompts:
# - PostgreSQL superuser password (often empty or "postgres")
# - New database password for 'auspex' user (you choose this)
```

The script will:
- Create database user: `auspex`
- Create database: `auspexdb`
- Create tables: `targets`, `poll_results`
- Add sample data (optional)

### Manual Setup (Alternative)

If the automated script doesn't work or you prefer manual control:

**1. Connect to PostgreSQL as superuser:**
```bash
# Linux
sudo -u postgres psql

# macOS
psql postgres
```

**2. Create database and user:**
```sql
-- Create user
CREATE USER auspex WITH PASSWORD 'your_secure_password_here';

-- Create database
CREATE DATABASE auspexdb OWNER auspex;

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE auspexdb TO auspex;

-- Exit
\q
```

**3. Initialize schema:**
```bash
# Run initialization script
psql -U auspex -d auspexdb -f db-init-new.sql

# You'll be prompted for the password you set above
```

**4. Verify setup:**
```bash
# Connect to database
psql -U auspex -d auspexdb

# Check tables
\dt

# Expected output:
#              List of relations
#  Schema |     Name      | Type  | Owner
# --------+---------------+-------+-------
#  public | poll_results  | table | auspex
#  public | targets       | table | auspex

# View sample targets (if you included sample data)
SELECT id, name, host FROM targets;

# Exit
\q
```

### Database Configuration Notes

**Important:** Remember the password you set! You'll need it in Step 6.

**Default values:**
- Database host: `localhost`
- Database port: `5432`
- Database name: `auspexdb`
- Database user: `auspex`
- Database password: (you choose this)

---

## Step 6: Configure Auspex

### Create Configuration Directory

```bash
# Create config directory
mkdir -p config

# Copy example config
cp auspex.conf.example config/auspex.conf

# Set secure permissions
chmod 600 config/auspex.conf
```

### Edit Configuration File

```bash
# Edit config file (use your preferred editor)
nano config/auspex.conf
# or
vim config/auspex.conf
# or
code config/auspex.conf  # VS Code
```

### Configuration Template

```bash
# Database Configuration
AUSPEX_DB_HOST=localhost
AUSPEX_DB_PORT=5432
AUSPEX_DB_NAME=auspexdb
AUSPEX_DB_USER=auspex
AUSPEX_DB_PASSWORD=your_secure_password_here  # ← CHANGE THIS!

# API Server Configuration
AUSPEX_API_PORT=8080

# SNMP Poller Configuration
AUSPEX_POLL_INTERVAL_SECONDS=60       # Poll every 60 seconds
AUSPEX_MAX_CONCURRENT_POLLS=10        # Poll 10 devices simultaneously
```

### Required Changes

1. **`AUSPEX_DB_PASSWORD`** - Set to the password you chose in Step 5
2. **Optional:** Adjust poll interval (default 60 seconds is good for most cases)
3. **Optional:** Adjust concurrent polls (10 is suitable for up to 1000 devices)

### Verify Configuration

```bash
# Test database connection with your config
export $(cat config/auspex.conf | xargs)
psql -h $AUSPEX_DB_HOST -p $AUSPEX_DB_PORT -U $AUSPEX_DB_USER -d $AUSPEX_DB_NAME -c "SELECT 1"

# Expected output:
#  ?column?
# ----------
#         1
# (1 row)
```

---

## Step 7: Install Dependencies

### Install Go Dependencies

```bash
# Download Go modules
go mod download

# Verify dependencies
go mod verify
# Expected: all modules verified

# Optional: Tidy dependencies
go mod tidy
```

### Install Node.js Dependencies

```bash
# Navigate to webui directory
cd webui

# Install npm packages
npm install

# Expected output:
# added X packages...

# Return to project root
cd ..
```

### Verify Dependencies

```bash
# Check Go dependencies
go list -m all | head -5

# Check Node.js dependencies
npm list --depth=0 --prefix webui
# Expected: express, pg, dotenv, body-parser
```

**Common Issues:**
- **"go.mod not found"** → Ensure you're in the auspex root directory
- **npm permission errors** → Don't use sudo, fix npm permissions instead
- **Network errors** → Check internet connection and proxy settings

---

## Step 8: Start Services

### Terminal Setup

You'll need **two terminal windows** (or use `tmux`/`screen`):
- Terminal 1: SNMP Poller (Go daemon)
- Terminal 2: API Server (Node.js)

### Terminal 1: Start SNMP Poller

```bash
# Navigate to auspex directory
cd /path/to/auspex

# Load configuration
export $(cat config/auspex.conf | xargs)

# Start poller
go run cmd/poller/main.go

# Expected output:
# 2025/11/17 08:00:00 Auspex SNMP poller started (interval=60s, maxConcurrent=10)
# 2025/11/17 08:00:00 polling 0 targets
# 2025/11/17 08:00:00 no enabled targets to poll
```

**Leave this terminal running!** The poller will continuously check for targets every 60 seconds.

### Terminal 2: Start API Server

```bash
# Navigate to auspex directory (in new terminal)
cd /path/to/auspex

# Load configuration
export $(cat config/auspex.conf | xargs)

# Start API server
node webui/server.js

# Expected output:
# Auspex API running on port 8080
```

**Leave this terminal running!** The API server handles web requests.

### Alternative: Background Processes

If you want to run as background processes:

```bash
# Load config
export $(cat config/auspex.conf | xargs)

# Start poller in background
nohup go run cmd/poller/main.go > logs/poller.log 2>&1 &
echo $! > logs/poller.pid

# Start API server in background
nohup node webui/server.js > logs/api.log 2>&1 &
echo $! > logs/api.pid

# View logs
tail -f logs/poller.log
tail -f logs/api.log

# Stop services later
kill $(cat logs/poller.pid)
kill $(cat logs/api.pid)
```

**For Production:** Use systemd services (see [PRODUCTION-READY.md](PRODUCTION-READY.md))

---

## Step 9: Verify Installation

### 1. Check Processes

```bash
# Check if poller is running
ps aux | grep "go run.*poller"

# Check if API server is running
ps aux | grep "node.*server.js"

# Expected: You should see both processes
```

### 2. Test API Endpoint

```bash
# Test API response
curl http://localhost:8080/api/targets

# Expected output (empty array if no targets added yet):
# []

# or with sample data:
# [{"id":1,"name":"Office-Router","host":"192.168.1.1",...}]
```

### 3. Access Web Dashboard

1. Open your web browser
2. Navigate to: **http://localhost:8080**
3. You should see the Auspex dashboard

**Expected:**
- Clean interface with "Add Target" button
- Empty target table (if no sample data)
- No errors in browser console (F12)

### 4. Add Test Target

```bash
# Add a test target via API
curl -X POST http://localhost:8080/api/targets \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test-Device",
    "host": "127.0.0.1",
    "port": 161,
    "community": "public",
    "snmp_version": "2c",
    "enabled": true
  }'

# Expected output:
# {"id":1,"name":"Test-Device","host":"127.0.0.1",...}
```

### 5. Verify Polling

```bash
# Wait 60 seconds for first poll cycle

# Check poll results
psql -U auspex -d auspexdb -c "SELECT * FROM poll_results LIMIT 5;"

# Expected: You should see poll results (likely "down" for 127.0.0.1)
```

### 6. Check Dashboard Updates

1. Refresh web dashboard (http://localhost:8080)
2. You should see "Test-Device" in the table
3. Status should show (likely red/down for localhost)
4. Dashboard should auto-refresh every 5 seconds

---

## Next Steps

### 1. Configure SNMP on Your Devices

See [SNMP-DEVICE-SETUP.md](SNMP-DEVICE-SETUP.md) for device-specific guides:
- Cisco routers and switches
- Linux servers
- Windows servers
- Network firewalls
- NAS devices

### 2. Add Real Monitoring Targets

**Option A: Interactive Script**
```bash
./add-target.sh
```

**Option B: Web UI**
1. Go to http://localhost:8080
2. Click "Add Target"
3. Fill in device details
4. Submit

**Option C: Bulk CSV Import**
1. Edit `targets-template.csv`
2. Add your devices
3. Import via web UI

### 3. Secure Your Installation

See [PRODUCTION-READY.md](PRODUCTION-READY.md) for:
- Changing default passwords
- Firewall configuration
- Systemd service setup
- SSL/TLS encryption
- Database backups

### 4. Learn to Use Auspex

See [GETTING-STARTED.md](GETTING-STARTED.md) for:
- Adding and managing targets
- Viewing poll results
- Using the API
- Troubleshooting devices

---

## Troubleshooting

### Installation Issues

#### PostgreSQL won't start
```bash
# Check status
sudo systemctl status postgresql

# Check logs
sudo journalctl -u postgresql -n 50

# Common fixes:
# 1. Port 5432 already in use
sudo lsof -i :5432
# Kill conflicting process or change PostgreSQL port

# 2. Data directory not initialized (CentOS/RHEL)
sudo postgresql-setup --initdb
```

#### Go module download fails
```bash
# Clear module cache
go clean -modcache

# Try again
go mod download

# If behind proxy, set proxy environment variables:
export GOPROXY=https://proxy.golang.org,direct
go mod download
```

#### npm install fails
```bash
# Clear npm cache
npm cache clean --force

# Try again
cd webui
npm install

# If permission errors, fix npm permissions:
mkdir -p ~/.npm-global
npm config set prefix '~/.npm-global'
echo 'export PATH=~/.npm-global/bin:$PATH' >> ~/.bashrc
source ~/.bashrc
```

#### Database connection refused
```bash
# Check PostgreSQL is listening
sudo netstat -plnt | grep 5432

# Check pg_hba.conf allows local connections
sudo cat /etc/postgresql/*/main/pg_hba.conf | grep "local.*all"

# Should see:
# local   all             all                                     peer
# or
# local   all             all                                     md5

# If not, edit pg_hba.conf and restart PostgreSQL
sudo systemctl restart postgresql
```

### Runtime Issues

#### Poller shows "no enabled targets"
```bash
# Check targets in database
psql -U auspex -d auspexdb -c "SELECT id, name, enabled FROM targets;"

# If no targets, add one:
curl -X POST http://localhost:8080/api/targets \
  -H "Content-Type: application/json" \
  -d '{"name":"Test","host":"192.168.1.1","port":161,"community":"public","snmp_version":"2c","enabled":true}'
```

#### Device shows "down" but is online
```bash
# Test SNMP manually (install snmpwalk if needed)
snmpwalk -v 2c -c public DEVICE_IP system

# Common issues:
# 1. SNMP not enabled on device → Enable SNMP
# 2. Wrong community string → Check device config
# 3. Firewall blocking UDP 161 → Allow UDP 161 from monitoring server
# 4. Wrong SNMP version → Verify device uses SNMPv2c

# See SNMP-DEVICE-SETUP.md for device configuration
```

#### Dashboard doesn't load
```bash
# Check API server is running
curl http://localhost:8080/api/targets

# If connection refused:
# 1. API server not running → Start it
# 2. Port 8080 in use → Check `lsof -i :8080`, kill or change port

# Check browser console (F12) for errors
# Common issue: API server on different port than expected
```

#### Can't connect to database
```bash
# Test connection manually
psql -U auspex -d auspexdb

# If "password authentication failed":
# 1. Wrong password in config/auspex.conf
# 2. User doesn't exist → Create user in PostgreSQL

# If "database does not exist":
# Run setup again: ./setup-database.sh

# If "could not connect to server":
# PostgreSQL not running → sudo systemctl start postgresql
```

### Getting Help

**Check Logs:**
```bash
# Poller logs (if running in foreground)
# Check Terminal 1 output

# API server logs (if running in foreground)
# Check Terminal 2 output

# Database logs
sudo tail -f /var/log/postgresql/postgresql-*.log

# System logs
sudo journalctl -xe
```

**Documentation:**
- [README.md](README.md) - Quick start and feature overview
- [GETTING-STARTED.md](GETTING-STARTED.md) - Using Auspex
- [DATABASE-SETUP.md](DATABASE-SETUP.md) - Database configuration
- [SNMP-DEVICE-SETUP.md](SNMP-DEVICE-SETUP.md) - Device configuration
- [PRODUCTION-READY.md](PRODUCTION-READY.md) - Production deployment

**Community:**
- GitHub Issues: https://github.com/yourusername/auspex/issues
- Discussions: https://github.com/yourusername/auspex/discussions

---

## Quick Reference Commands

### Start Services
```bash
# Terminal 1: Poller
export $(cat config/auspex.conf | xargs) && go run cmd/poller/main.go

# Terminal 2: API Server
export $(cat config/auspex.conf | xargs) && node webui/server.js
```

### Check Status
```bash
# Processes
ps aux | grep -E "go run.*poller|node.*server"

# Database
psql -U auspex -d auspexdb -c "SELECT COUNT(*) FROM targets;"

# API
curl http://localhost:8080/api/targets

# Dashboard
open http://localhost:8080  # macOS
xdg-open http://localhost:8080  # Linux
```

### Stop Services
```bash
# Find PIDs
ps aux | grep -E "go run.*poller|node.*server"

# Kill processes
kill <PID>

# Or Ctrl+C in each terminal
```

---

**Installation Complete!**

Your Auspex SNMP Network Monitor is now ready to use.

**Next:** Read [GETTING-STARTED.md](GETTING-STARTED.md) to learn how to add devices and use Auspex.
