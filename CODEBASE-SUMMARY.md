# Auspex Codebase Summary

**Generated:** 2025-11-17
**Purpose:** Quick reference guide for AI assistants and developers working on the Auspex SNMP Network Monitor

---

## Project Overview

**Auspex** is a lightweight, real-time SNMP network monitoring system with a web-based dashboard. It monitors network devices (routers, switches, servers, firewalls, etc.) via SNMPv2c protocol, storing poll results in PostgreSQL and displaying real-time status via a web UI.

**Key Features:**
- Real-time SNMP polling with configurable intervals
- Web dashboard with auto-refresh (5-second updates)
- Historical latency tracking and uptime statistics
- REST API for programmatic access
- Concurrent polling with semaphore-based concurrency control
- PostgreSQL backend with optimized indexes
- Support for 1000+ devices per instance

---

## Architecture

### Component Diagram

```
┌─────────────────┐
│   Web Browser   │
│  (Dashboard)    │
└────────┬────────┘
         │ HTTP
         ▼
┌─────────────────┐      ┌──────────────┐
│  Express API    │◄────►│  PostgreSQL  │
│  (Node.js)      │      │   Database   │
│  Port 8080      │      └──────────────┘
└─────────────────┘
         ▲
         │ SQL Queries
         │
┌─────────────────┐      ┌──────────────┐
│  SNMP Poller    │─────►│   Network    │
│  (Go daemon)    │ SNMP │   Devices    │
│  60s interval   │      │ (UDP:161)    │
└─────────────────┘      └──────────────┘
```

### Components

| Component | Technology | File Location | Purpose |
|-----------|-----------|---------------|---------|
| **SNMP Poller** | Go 1.25.4 | `cmd/poller/main.go` | Queries SNMP devices, writes results to DB |
| **API Server** | Node.js + Express 4.18.2 | `webui/server.js` | REST API and static file serving |
| **Database** | PostgreSQL 12+ | `db-init-new.sql` | Stores targets and poll history |
| **Web UI** | Vanilla JavaScript + Chart.js | `webui/index.html`, `webui/target.html` | Real-time dashboard with graphs |

---

## Directory Structure

```
/home/jmcclain/projects/auspex/
├── cmd/poller/
│   └── main.go                   # Go SNMP polling daemon (244 lines)
├── webui/
│   ├── server.js                 # Express.js API server (247 lines)
│   ├── index.html                # Main dashboard (222 lines)
│   ├── target.html               # Target detail page (182 lines)
│   └── user-guide.html           # User documentation (placeholder)
├── api/
│   └── db-init.sql               # Empty placeholder (deprecated)
├── db-init-new.sql               # PostgreSQL schema + sample data (93 lines)
├── setup-database.sh             # Database initialization script (102 lines)
├── add-target.sh                 # Interactive device addition (88 lines)
├── targets-template.csv          # CSV bulk import template
├── auspex.conf.example           # Configuration template (24 lines)
├── .env.example                  # Alternative config format
├── go.mod / go.sum               # Go dependencies
├── package.json                  # Node.js dependencies
├── README.md                     # Main documentation
├── GETTING-STARTED.md            # Usage guide (455 lines)
├── SNMP-DEVICE-SETUP.md          # Device configuration (397 lines)
├── PRODUCTION-READY.md           # Security & deployment (476 lines)
├── DATABASE-SETUP.md             # Database troubleshooting (263 lines)
└── .gitignore                    # Git ignore patterns
```

---

## Technology Stack

### Backend
- **Go 1.25.4** - SNMP poller daemon
  - `github.com/gosnmp/gosnmp v1.42.1` - SNMP client library
  - `github.com/lib/pq v1.10.9` - PostgreSQL driver
- **Node.js 16+** - Web API server
  - `express 4.18.2` - HTTP web framework
  - `pg 8.11.3` - PostgreSQL client
  - `dotenv 16.3.1` - Environment configuration
  - `body-parser` - JSON/form parsing

### Frontend
- **HTML5** - Semantic markup
- **Vanilla JavaScript** - DOM manipulation, Fetch API
- **Chart.js** - Latency visualization (CDN)
- **CSS3** - Inline styling

### Database
- **PostgreSQL 12+** - Relational database with optimized indexes

### Protocol
- **SNMPv2c** - Device communication (UDP port 161)

---

## Database Schema

### Table: `targets`

Stores network device configurations to be monitored.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | SERIAL | PRIMARY KEY | Unique target ID |
| `name` | VARCHAR(255) | NOT NULL | Device display name |
| `host` | VARCHAR(255) | NOT NULL | IP address or hostname |
| `port` | INTEGER | NOT NULL, DEFAULT 161 | SNMP port (1-65535) |
| `community` | VARCHAR(100) | NOT NULL, DEFAULT 'public' | SNMP community string |
| `snmp_version` | VARCHAR(20) | NOT NULL, DEFAULT '2c' | SNMP version ('1', '2c', '3') |
| `enabled` | BOOLEAN | NOT NULL, DEFAULT true | Whether to poll this device |
| `created_at` | TIMESTAMP | NOT NULL, DEFAULT NOW() | Record creation time |
| `updated_at` | TIMESTAMP | NOT NULL, DEFAULT NOW() | Last update time |

**Indexes:**
- `idx_targets_enabled` - Fast lookup of enabled targets (used by poller)
- `idx_targets_host` - Fast lookup by hostname

### Table: `poll_results`

Stores historical SNMP poll results for each target.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | BIGSERIAL | PRIMARY KEY | Unique result ID |
| `target_id` | INTEGER | NOT NULL, FOREIGN KEY → targets(id) ON DELETE CASCADE | Target reference |
| `status` | VARCHAR(20) | NOT NULL, CHECK IN ('up', 'down', 'unknown') | Poll status |
| `latency_ms` | INTEGER | NOT NULL, DEFAULT 0, CHECK >= 0 | Response time in milliseconds |
| `message` | TEXT | NULL | SNMP response or error message |
| `polled_at` | TIMESTAMP | NOT NULL, DEFAULT NOW() | When poll occurred |

**Indexes:**
- `idx_poll_results_target_polled` - Critical for latest poll lookup per target
- `idx_poll_results_polled_at` - Time-based queries
- `idx_poll_results_status` - Status filtering

**Relationship:**
- Foreign key constraint: `poll_results.target_id` → `targets.id` with CASCADE delete

---

## Key Source Files

### 1. `cmd/poller/main.go` (244 lines)

**Purpose:** Go daemon that continuously polls SNMP devices and stores results.

**Key Functions:**

- `main()` - Entry point: initializes DB connection, starts polling ticker
- `pollOnce(db, maxConcurrent)` - Executes one complete polling cycle for all enabled targets
- `loadTargets(db)` - Fetches enabled targets from database
- `pollTargetSNMP(target)` - Performs actual SNMP v2c query
  - Queries 3 OIDs: sysDescr, sysUpTime, sysName
  - Returns status ('up'/'down'), latency (ms), and message
  - Connection timeout: 2 seconds, 1 retry
- `insertResult(db, targetID, status, latency, message)` - Persists poll result to DB
- `snmpValueToString(v)` - Safely converts SNMP PDU values to strings
- `getenv(key, fallback)` - Retrieves environment variables with defaults

**Configuration (Environment Variables):**
- `AUSPEX_DB_HOST` (default: localhost)
- `AUSPEX_DB_PORT` (default: 5432)
- `AUSPEX_DB_NAME` (default: auspexdb)
- `AUSPEX_DB_USER` (default: auspex)
- `AUSPEX_DB_PASSWORD` (required)
- `AUSPEX_POLL_INTERVAL_SECONDS` (default: 60)
- `AUSPEX_MAX_CONCURRENT_POLLS` (default: 10)

**SNMP Query Details:**
- Queries 3 standard OIDs:
  - `1.3.6.1.2.1.1.1.0` - sysDescr (device description)
  - `1.3.6.1.2.1.1.3.0` - sysUpTime (uptime in timeticks)
  - `1.3.6.1.2.1.1.5.0` - sysName (device name)
- Success criteria: All 3 OIDs return values
- Failure triggers: Timeout, connection error, missing OID response

**Concurrency Model:**
- Uses Go semaphore pattern with buffered channel
- `sync.WaitGroup` ensures all polls complete before next cycle
- Configurable max concurrent polls (default: 10)

---

### 2. `webui/server.js` (247 lines)

**Purpose:** Express.js web server providing REST API and static file serving.

**API Routes:**

**Target Management:**
- `GET /api/targets` - List all targets with latest poll status
- `POST /api/targets` - Create new target
- `PUT /api/targets/:id` - Update target configuration
- `DELETE /api/targets/:id` - Soft-delete (disable) target
- `DELETE /api/targets/:id/delete` - Hard-delete target and all poll history

**Target Details:**
- `GET /api/targets/:id/info` - Full target configuration
- `GET /api/targets/:id/latest` - Most recent poll result
- `GET /api/targets/:id/latency` - Latency samples for last hour
- `GET /api/targets/:id/stats` - Statistics (min/max/avg latency, uptime %)
- `POST /api/targets/:id/update` - Alternative update endpoint

**Web UI:**
- `GET /` or `/index.html` - Main dashboard
- `GET /api/user-guide` - User guide page (currently empty)

**Configuration:**
- Loads config from `/opt/auspex/config/auspex.conf` or environment variables
- Uses PostgreSQL connection pooling via `pg` library
- Default port: 8080

---

### 3. `webui/index.html` (222 lines)

**Purpose:** Main dashboard page displaying all monitored devices.

**Features:**
- Real-time target status table with color-coded indicators:
  - Green = up
  - Red = down
  - Gray = unknown
- Auto-refresh every 5 seconds via `setInterval(loadTargets, 5000)`
- Add Target form for manual device addition
- Edit Target panel for configuration updates
- Bulk CSV import functionality
- Click-through to detail pages

**Key JavaScript Functions:**
- `loadTargets()` - Fetches all targets via API, renders table
- `addTarget(e)` - Submits new target via POST
- `editTarget(id)` - Opens edit panel with pre-filled data
- `saveEdit()` - Updates target via PUT
- `deleteTarget(id)` - Soft-deletes target
- `bulkImport()` - Parses CSV and bulk uploads targets

---

### 4. `webui/target.html` (182 lines)

**Purpose:** Target detail page showing metrics, charts, and configuration.

**Features:**
- Target configuration editor
- Latest poll result display
- Last-hour statistics (min/max/avg latency, uptime %)
- Line chart showing latency over last hour (Chart.js)
- Auto-refresh every 10 seconds
- Delete target button (hard delete)

**Key JavaScript Functions:**
- `loadConfig()` - Fetches target settings, displays in form
- `saveTarget()` - Updates target configuration via POST
- `deleteTarget()` - Hard-deletes target and history
- `loadLatest()` - Shows most recent poll result
- `loadStats()` - Calculates and displays uptime/latency stats
- `loadChart()` - Renders Chart.js latency graph with last hour's data

---

## API Reference

### Target Endpoints

| Method | Endpoint | Description | Request Body |
|--------|----------|-------------|--------------|
| GET | `/api/targets` | List all targets + latest status | - |
| POST | `/api/targets` | Add new target | `{name, host, port, community, snmp_version, enabled}` |
| PUT | `/api/targets/:id` | Update target | `{name, host, port, community, snmp_version, enabled}` |
| DELETE | `/api/targets/:id` | Soft-delete (disable) | - |
| DELETE | `/api/targets/:id/delete` | Hard-delete (permanent) | - |

### Analytics Endpoints

| Method | Endpoint | Description | Response |
|--------|----------|-------------|----------|
| GET | `/api/targets/:id/info` | Target configuration | `{id, name, host, port, ...}` |
| GET | `/api/targets/:id/latest` | Most recent poll | `{status, latency_ms, message, polled_at}` |
| GET | `/api/targets/:id/latency` | Last hour latency samples | `[{latency_ms, polled_at}, ...]` |
| GET | `/api/targets/:id/stats` | Last hour statistics | `{min_latency, max_latency, avg_latency, up_count, total_count}` |

---

## Configuration

### Configuration File: `config/auspex.conf` or `.env`

```bash
# Database
AUSPEX_DB_HOST=localhost
AUSPEX_DB_PORT=5432
AUSPEX_DB_NAME=auspexdb
AUSPEX_DB_USER=auspex
AUSPEX_DB_PASSWORD=yourpassword  # CHANGE THIS!

# API Server
AUSPEX_API_PORT=8080

# Poller Settings
AUSPEX_POLL_INTERVAL_SECONDS=60      # Poll frequency
AUSPEX_MAX_CONCURRENT_POLLS=10       # Concurrent device polls
```

### Loading Configuration

**Poller (Go):**
- Reads directly from environment variables using `os.Getenv()`
- Fallback defaults if variable not set

**API Server (Node.js):**
- Uses `dotenv` to load from `/opt/auspex/config/auspex.conf`
- Can also read from environment variables

---

## Helper Scripts

### 1. `setup-database.sh` (102 lines)

**Purpose:** Automated database initialization

**Actions:**
1. Loads configuration from `auspex.conf`
2. Checks PostgreSQL installation and connectivity
3. Creates database user if needed
4. Creates database if needed
5. Runs schema initialization from `db-init-new.sql`
6. Provides helpful error messages

**Usage:**
```bash
./setup-database.sh
```

### 2. `add-target.sh` (88 lines)

**Purpose:** Interactive script for adding SNMP devices

**Actions:**
1. Prompts for device configuration (name, IP, port, community, version)
2. Validates configuration file location
3. Calls REST API to add target
4. Returns device ID and detail page URL

**Usage:**
```bash
./add-target.sh
```

### 3. `targets-template.csv`

**Purpose:** CSV template for bulk device import

**Format:**
```csv
name,host,port,community,snmp_version,enabled
Office-Router,192.168.1.1,161,public,2c,true
Core-Switch,192.168.1.2,161,public,2c,true
```

**Usage:**
1. Edit CSV with your devices
2. Use web dashboard's CSV import feature

---

## Common Workflows

### Starting the System

```bash
# Terminal 1: Start poller
cd /home/jmcclain/projects/auspex
export $(cat config/auspex.conf | xargs)
go run cmd/poller/main.go

# Terminal 2: Start API server
export $(cat config/auspex.conf | xargs)
node webui/server.js

# Terminal 3: Access dashboard
open http://localhost:8080
```

### Adding a Device

**Method 1: Interactive script**
```bash
./add-target.sh
```

**Method 2: API call**
```bash
curl -X POST http://localhost:8080/api/targets \
  -H "Content-Type: application/json" \
  -d '{
    "name": "My-Router",
    "host": "192.168.1.1",
    "port": 161,
    "community": "public",
    "snmp_version": "2c",
    "enabled": true
  }'
```

**Method 3: Web UI**
1. Go to http://localhost:8080
2. Click "Add Target"
3. Fill in form and submit

### Testing SNMP Connectivity

Before adding a device, test with:
```bash
snmpwalk -v 2c -c public 192.168.1.1 system
```

Expected output should show sysDescr, sysUpTime, sysName, etc.

### Viewing Poll Results

**Via Web UI:**
- Main dashboard: http://localhost:8080
- Target details: http://localhost:8080/target.html?id=1

**Via API:**
```bash
curl http://localhost:8080/api/targets/1/latest
curl http://localhost:8080/api/targets/1/stats
```

**Via SQL:**
```bash
psql -U auspex -d auspexdb
```
```sql
SELECT t.name, pr.status, pr.latency_ms, pr.polled_at
FROM targets t
LEFT JOIN LATERAL (
    SELECT * FROM poll_results
    WHERE target_id = t.id
    ORDER BY polled_at DESC
    LIMIT 1
) pr ON TRUE
ORDER BY t.name;
```

---

## Performance Characteristics

**Expected Capacity (Single Instance):**
- **Devices:** 1,000+ targets
- **Poll Rate:** 16 devices/second @ 60-second intervals
- **Database Growth:** ~100 MB/day (60s interval, 1000 devices)
- **API Latency:** <100ms per request
- **Memory Usage:**
  - Poller: 50-100 MB
  - API: 50 MB
  - Database: Variable based on history

**Optimization Notes:**
- Critical indexes on `poll_results.target_id` and `poll_results.polled_at`
- LATERAL JOIN pattern for efficient latest-poll queries
- Semaphore-based concurrency control prevents overwhelming network
- Connection pooling in API server

---

## Supported Devices

Any device supporting SNMPv2c protocol:

**Network Equipment:**
- Routers, switches, firewalls, access points, load balancers

**Servers:**
- Linux (net-snmp), Windows (SNMP service), VMware ESXi, Proxmox

**Storage:**
- NAS devices (Synology, QNAP, TrueNAS)

**Other:**
- UPS systems, environmental monitors, printers

See `SNMP-DEVICE-SETUP.md` for device-specific configuration guides.

---

## Security Considerations

**Default Security Issues:**
- Default database password: `yourpassword`
- Default SNMP community: `public`
- No authentication on API endpoints
- PostgreSQL may accept remote connections

**Production Hardening (See PRODUCTION-READY.md):**
1. Change database password
2. Use unique SNMP community strings
3. Restrict PostgreSQL to localhost
4. Set file permissions: `chmod 600 config/auspex.conf`
5. Configure firewall rules (allow UDP 161 from monitoring server only)
6. Add API authentication (not implemented by default)
7. Enable PostgreSQL SSL/TLS
8. Set up systemd services for auto-start
9. Configure log rotation
10. Implement database backups

---

## Documentation Files

| File | Lines | Purpose |
|------|-------|---------|
| `README.md` | 332 | Main project documentation, quick start, API reference |
| `GETTING-STARTED.md` | 455 | Detailed usage guide, adding targets, troubleshooting |
| `SNMP-DEVICE-SETUP.md` | 397 | Device-specific SNMP configuration guides |
| `PRODUCTION-READY.md` | 476 | Security hardening, systemd services, backups |
| `DATABASE-SETUP.md` | 263 | Database installation and troubleshooting |

**Total Documentation:** 1,923 lines

---

## Git Repository Information

**Current Branch:** `main`
**Last Commit:** `a779931 Initial commit: Auspex SNMP Network Monitor`
**Working Directory:** `/home/jmcclain/projects/auspex`
**Remote:** Not yet configured

---

## Quick Reference: Key Code Locations

### SNMP Polling Logic
- **File:** `cmd/poller/main.go:134-212`
- **Function:** `pollTargetSNMP(target)`
- **OIDs Queried:** sysDescr (1.3.6.1.2.1.1.1.0), sysUpTime (1.3.6.1.2.1.1.3.0), sysName (1.3.6.1.2.1.1.5.0)

### Database Queries (Latest Poll)
- **File:** `webui/server.js:30-53`
- **Pattern:** LATERAL JOIN for efficient per-target latest poll

### Dashboard Auto-Refresh
- **File:** `webui/index.html:15`
- **Code:** `setInterval(loadTargets, 5000)`

### Target Detail Charts
- **File:** `webui/target.html:95-140`
- **Function:** `loadChart()`
- **Library:** Chart.js (CDN)

### Database Schema
- **File:** `db-init-new.sql`
- **Key Indexes:** `idx_poll_results_target_polled` (lines 63-64)

---

## Development Notes

### Adding New SNMP OIDs

To poll additional SNMP OIDs beyond the standard three:

1. **Update poller:** Edit `cmd/poller/main.go:172-176`
   - Add OID to `oids` slice
   - Add parsing logic for new OID in lines 195-204
   - Update message format (line 210)

2. **Update database:** Add columns to `poll_results` table if storing structured data

3. **Update API:** Add new endpoints in `webui/server.js` if exposing via API

4. **Update UI:** Add display logic in `webui/target.html`

### Adding Authentication

Currently no authentication on API endpoints. To add:

1. Choose auth method (JWT, OAuth, basic auth)
2. Add middleware to `webui/server.js` before route definitions
3. Update frontend to include auth headers in fetch calls
4. See `PRODUCTION-READY.md` for security recommendations

### Extending Dashboard

To add new visualizations:

1. **Create new HTML page** in `webui/`
2. **Add route** in `webui/server.js`
3. **Create API endpoint** for data
4. **Link from dashboard** in `webui/index.html`

---

## Common Troubleshooting

### Device Shows "Down" But Is Online

**Check:**
1. SNMP enabled on device
2. Community string correct
3. Firewall allows UDP 161
4. Test with: `snmpwalk -v 2c -c public DEVICE_IP system`

**Fix:** See `SNMP-DEVICE-SETUP.md` for device configuration

### Poller Not Running

```bash
# Check process
ps aux | grep "go run.*poller"

# Check database
psql -U auspex -d auspexdb -c "SELECT 1"

# Restart
export $(cat config/auspex.conf | xargs)
go run cmd/poller/main.go
```

### Dashboard Not Updating

1. Verify poller is running
2. Check latest poll: `SELECT MAX(polled_at) FROM poll_results;`
3. Hard refresh browser (Ctrl+Shift+R)
4. Check browser console for errors

---

## Future Enhancement Ideas

- **SNMPv3 Support:** Add authentication and encryption
- **Alerting:** Email/SMS notifications for down devices
- **API Authentication:** JWT or OAuth2
- **Multi-tenancy:** Support multiple organizations
- **Custom OID Sets:** Per-device OID configurations
- **Graphing:** Additional visualizations (interface traffic, CPU, memory)
- **Mobile App:** Native mobile interface
- **Webhooks:** Push notifications to external systems
- **SNMP Traps:** Receive trap notifications from devices

---

## License

MIT License

---

**End of Codebase Summary**

*This document is intended as a quick reference for AI assistants and developers. For detailed information, refer to the individual documentation files and source code.*
