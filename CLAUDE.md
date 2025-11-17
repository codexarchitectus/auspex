# Auspex CLAUDE.md - AI Assistant Reference

**Version:** 1.1
**Last Updated:** 2025-11-17
**Reflects Commit:** db202be (Merge alerting engine into main)
**Branch:** main

---

## Overview

**Auspex** is a lightweight real-time SNMP network monitoring system featuring a web dashboard and alerting engine. It monitors network devices via SNMPv2c, provides status updates, latency tracking, uptime statistics, and sends notifications when devices go down.

---

## Core Technology Stack

- **Backend Poller:** Go 1.25+ (SNMP polling daemon)
- **Alerting Engine:** Go 1.25+ (Alert monitoring and notification daemon) 🆕
- **Web API:** Node.js + Express (REST API server)
- **Database:** PostgreSQL 12+
- **Frontend:** Vanilla JavaScript + Chart.js
- **SNMP Library:** gosnmp
- **Database Driver:** pg (Node.js), lib/pq (Go)

---

## Recent Changes & New Features

### 🆕 Alerting Engine (v1.1 - Merged db202be)

**Major new feature** that provides enterprise-grade monitoring alerts:

- **Multi-channel notifications** - PagerDuty, Slack (via email), standard email
- **Status change detection** - Device down/recovery alerts with auto-resolution
- **Alert suppression** - Scheduled maintenance windows (one-time, daily, weekly, monthly)
- **De-duplication** - Prevents alert spam with state tracking
- **Complete audit trail** - Alert history and delivery logs
- **REST API** - Full programmatic control over channels, rules, and suppressions

**Key Files:**
- `cmd/alerter/main.go` - Alert monitoring daemon (784 lines)
- `db-alerting-schema.sql` - Database schema (6 new tables)
- `ALERTING-SETUP.md` - Comprehensive setup guide

**Configuration:**
```bash
AUSPEX_ALERTER_ENABLED=true
AUSPEX_ALERTER_CHECK_INTERVAL_SECONDS=30
AUSPEX_ALERTER_DEDUP_WINDOW_MINUTES=15
AUSPEX_SMTP_HOST=smtp.gmail.com
AUSPEX_SMTP_PORT=587
AUSPEX_SMTP_USER=your-email@gmail.com
AUSPEX_SMTP_PASSWORD=your-app-password
AUSPEX_SMTP_FROM=auspex-alerts@yourdomain.com
```

**New API Endpoints:**
```
GET/POST/PUT/DELETE /api/alert-channels       # Notification channel management
GET/POST/PUT/DELETE /api/alert-rules          # Alert rules per target
GET                 /api/alert-history        # Alert history (paginated)
GET                 /api/alert-history/active # Unresolved alerts
GET                 /api/alert-stats          # Alert statistics
GET/POST/PUT/DELETE /api/alert-suppressions   # Maintenance windows
```

**Database Tables:**
- `alert_channels` - Notification channel configs
- `alert_rules` - Rules mapping targets to channels
- `alert_history` - Complete alert firing history
- `alert_deliveries` - Delivery attempt logs
- `alert_suppressions` - Maintenance window schedules
- `alert_state` - Current state for de-duplication

---

## Repository Structure

The codebase organizes as follows:
- `cmd/poller/main.go` - Go SNMP polling daemon
- `cmd/alerter/main.go` - Go alerting daemon 🆕
- `webui/` - Express API server and HTML dashboard
- `db-init-new.sql` - Core database schema
- `db-alerting-schema.sql` - Alerting database schema 🆕
- Configuration files (auspex.conf.example, .env.example)
- Helper scripts (add-target.sh, setup-database.sh, start-alerter.sh 🆕)

---

## System Architecture

Four core components interact:
1. **Web Browser** → HTTP requests to Express API (port 8080)
2. **Express API** ↔ PostgreSQL (SQL queries)
3. **Go Poller** → SNMP queries to devices (UDP 161)
4. **Go Alerter** → Monitors database, sends notifications (HTTPS/SMTP) 🆕

The polling cycle executes every 60 seconds by default: poller reads enabled targets, queries devices concurrently, writes results to database.

The alerting cycle executes every 30 seconds: alerter checks alert rules, detects status changes, verifies suppressions, and sends notifications via configured channels.

**Architecture Diagram (Updated):**
```
┌─────────────────────────────────────────────────────────────────┐
│                        Auspex Architecture                       │
└─────────────────────────────────────────────────────────────────┘

                    ┌─────────────────┐
                    │   Web Browser   │
                    │   (Dashboard)   │
                    └────────┬────────┘
                             │
                             │ HTTP (Port 8080)
                             ▼
                    ┌─────────────────┐
                    │  Express API    │
                    │  (Node.js)      │
                    │  • REST API     │
                    │  • Static Files │
                    └────────┬────────┘
                             │
                    ┌────────┴────────┐
                    │                 │
                    ▼                 ▼
            ┌──────────────┐   ┌──────────────┐
            │  PostgreSQL  │   │   Web UI     │
            │   Database   │   │  • Dashboard │
            │              │   │  • Details   │
            └──────┬───────┘   └──────────────┘
                   ▲
                   │
        ┌──────────┼──────────┐
        │          │          │
        │ INSERT   │ SELECT   │ SELECT (polling)
        │          │          │
        ▼          │          ▼
┌─────────────┐    │    ┌─────────────┐
│ SNMP Poller │────┘    │  Alerter    │ 🆕
│ (Go Daemon) │         │ (Go Daemon) │
│ • 60s poll  │         │ • Monitors  │
│ • Concurrent│         │ • Notifies  │
└──────┬──────┘         └──────┬──────┘
       │                       │
       │ SNMP                  │ HTTPS/SMTP
       │ (UDP:161)             │
       ▼                       ▼
┌─────────────┐         ┌─────────────┐
│  Network    │         │Notification │
│  Devices    │         │  Services   │
│ • Routers   │         │ • PagerDuty │
│ • Switches  │         │ • Slack     │
│ • Servers   │         │ • Email     │
└─────────────┘         └─────────────┘
```

---

## Database Schema

### Core Tables

**targets table** stores device configurations:
- id (SERIAL, primary key)
- name, host, port, community, snmp_version
- enabled (BOOLEAN for polling control)
- created_at, updated_at (TIMESTAMP)

**poll_results table** stores historical data:
- id (BIGSERIAL)
- target_id (foreign key)
- status ('up', 'down', 'unknown')
- latency_ms (integer ≥ 0)
- message (TEXT)
- polled_at (TIMESTAMP)

Indexes optimize queries: enabled status filtering, target/timestamp combinations.

### Alerting Tables 🆕

**alert_channels table** stores notification configurations:
- id (SERIAL, primary key)
- name, type ('pagerduty', 'slack_email', 'email', 'webhook')
- config (JSONB - channel-specific settings)
- enabled (BOOLEAN)
- created_at, updated_at (TIMESTAMP)

**alert_rules table** maps targets to channels:
- id (SERIAL, primary key)
- target_id (foreign key to targets)
- channel_ids (INTEGER[] - array of channel IDs)
- rule_type ('status_change', 'latency_threshold', 'consecutive_failures')
- severity ('info', 'warning', 'critical')
- enabled (BOOLEAN)

**alert_history table** tracks all alerts:
- id (BIGSERIAL, primary key)
- target_id, rule_id, channel_ids
- alert_type ('device_down', 'device_up', 'latency_high', etc.)
- severity, message
- fired_at, resolved_at (TIMESTAMP)
- notification_count, last_notification_at

**alert_deliveries table** logs delivery attempts:
- id (BIGSERIAL, primary key)
- alert_id, channel_id
- status ('success', 'failure')
- error_message (if failed)
- delivered_at (TIMESTAMP)

**alert_suppressions table** schedules maintenance windows:
- id (SERIAL, primary key)
- name, target_id (NULL for global)
- start_time, end_time
- recurrence ('daily', 'weekly', 'monthly', NULL for one-time)
- days_of_week (INTEGER[] for weekly recurrence)
- reason, enabled

**alert_state table** tracks current state:
- target_id (primary key)
- last_status ('up', 'down')
- alert_active (BOOLEAN)
- active_alert_id (foreign key to alert_history)
- state_change_count (INTEGER)
- last_checked_at, last_state_change_at

---

## Configuration

Environment variables control behavior:
- `AUSPEX_DB_*` - Database connection parameters
- `AUSPEX_API_PORT` - API server port (default: 8080)
- `AUSPEX_POLL_INTERVAL_SECONDS` - Polling frequency (default: 60)
- `AUSPEX_MAX_CONCURRENT_POLLS` - Concurrency limit (default: 10)
- `AUSPEX_ALERTER_ENABLED` - Enable alerting daemon (default: true) 🆕
- `AUSPEX_ALERTER_CHECK_INTERVAL_SECONDS` - Alert check frequency (default: 30) 🆕
- `AUSPEX_ALERTER_DEDUP_WINDOW_MINUTES` - De-duplication window (default: 15) 🆕
- `AUSPEX_SMTP_HOST`, `AUSPEX_SMTP_PORT`, `AUSPEX_SMTP_USER`, `AUSPEX_SMTP_PASSWORD`, `AUSPEX_SMTP_FROM` - SMTP configuration 🆕

**Configuration Path Note:**
The Node.js server references configuration at `/opt/auspex/config/auspex.conf`. For local development:
- Create symlink: `sudo mkdir -p /opt/auspex && sudo ln -s $(pwd)/config /opt/auspex/config`
- Or modify `webui/server.js` to use relative path: `./config/auspex.conf`
- Go daemons load config from environment variables (no hardcoded paths)

---

## Key Code Files

### cmd/poller/main.go

**Core SNMP polling daemon** implementing:
- `main()` (line 26) - Entry point, database connection, polling loop
- `pollOnce()` (line 74) - Single polling cycle
- `loadTargets()` (line 113) - Query enabled targets
- `pollTargetSNMP()` (line 147) - Execute SNMP query
- `insertResult()` (line 228) - Write results to database

SNMP logic queries three OIDs (sysDescr, sysUpTime, sysName) with 2-second timeout and 1 retry. Latency measures round-trip time. Concurrency uses goroutine semaphore pattern with WaitGroup synchronization.

### cmd/alerter/main.go 🆕

**Alert monitoring and notification daemon** implementing:
- `main()` (line 87) - Entry point, database connection, alerting loop
- `checkForAlerts()` (line 159) - Main loop - loads rules and processes each
- `processAlertRule()` (line 182) - Checks if alert conditions are met
- `handleStatusChange()` (line 247) - Creates/resolves alerts on status change
- `isSuppressed()` (line 309) - Checks if target is in maintenance window
- `createAlert()` (line 341) - Inserts alert into alert_history
- `resolveAlert()` (line 359) - Sets resolved_at timestamp
- `sendNotifications()` (line 373) - Dispatches to all configured channels
- `sendPagerDutyAlert()` (line 433) - PagerDuty Events API v2 integration
- `sendSlackEmailAlert()` (line 501) - SMTP to Slack channel email
- `sendEmailAlert()` (line 540) - Standard SMTP email
- Additional helper functions: `logDelivery()`, `loadAlertRules()`, `loadAlertChannels()`, `getLatestPollResult()`, `getAlertState()`, `saveAlertState()`

**Alert Triggering Flow:**
```
Monitoring Loop (every 30s)
  ↓
Load enabled alert rules
  ↓
For each rule: Get latest poll result
  ↓
Get current alert state (de-duplication)
  ↓
Check for status changes (up ↔ down)
  ↓
If status changed:
  ├─ Check if suppressed (maintenance window)
  ├─ If device down: Create alert, send notifications
  └─ If device up: Resolve active alert, send recovery notification
  ↓
Update alert_state for de-duplication
```

### webui/server.js

**Express REST API** serving:

**Target Endpoints:**
- `GET /api/targets` - List all targets with latest poll status (LATERAL join)
- `POST /api/targets` - Add new target
- `PUT /api/targets/:id` - Update configuration
- `DELETE /api/targets/:id` - Soft-delete
- `GET /api/targets/:id/*` - Details, latest, latency, stats

**Alert Endpoints:** 🆕
- `GET /api/alert-channels` - List all notification channels
- `POST /api/alert-channels` - Create notification channel
- `PUT /api/alert-channels/:id` - Update channel
- `DELETE /api/alert-channels/:id` - Delete channel
- `GET /api/alert-rules` - List all alert rules
- `GET /api/alert-rules/target/:id` - Rules for specific target
- `POST /api/alert-rules` - Create alert rule
- `PUT /api/alert-rules/:id` - Update rule
- `DELETE /api/alert-rules/:id` - Delete rule
- `GET /api/alert-history` - Alert history (paginated, default 100 limit)
- `GET /api/alert-history/active` - Unresolved alerts
- `GET /api/alert-history/:id/deliveries` - Delivery log for alert
- `GET /api/alert-stats` - Alert statistics
- `GET /api/alert-suppressions` - List maintenance windows
- `GET /api/alert-suppressions/active` - Currently active suppressions
- `POST /api/alert-suppressions` - Create suppression
- `PUT /api/alert-suppressions/:id` - Update suppression
- `DELETE /api/alert-suppressions/:id` - Delete suppression

Static file serving for dashboard HTML pages.

### db-init-new.sql

**Database initialization** creates schema with constraints (port 1-65535, version '1'/'2c'/'3', status values). Foreign key includes CASCADE deletion. Sample data available (comment out for production).

### db-alerting-schema.sql 🆕

**Alerting schema initialization** creates 6 tables for alert management with proper constraints, indexes, and foreign keys. Includes sample data for testing.

---

## Development Workflows

### First-Time Setup

**Before running services, complete initial setup:**

```bash
# 1. Create config file from template
cp config/auspex.conf.template config/auspex.conf
chmod 600 config/auspex.conf

# 2. Edit config - set database password and SMTP settings
nano config/auspex.conf

# 3. Run database setup script (uses peer authentication)
./setup-database.sh

# 4. Install Node.js dependencies
cd webui && npm install && cd ..
```

### Starting Services (Development)

```bash
# Load environment variables (required for each terminal session)
export $(grep -v '^#' config/auspex.conf | xargs)

# Terminal 1: Poller
go run cmd/poller/main.go

# Terminal 2: Alerter 🆕
go run cmd/alerter/main.go

# Terminal 3: API Server
node webui/server.js

# Terminal 4: Access
curl http://localhost:8080/api/targets
```

**Important:** The `export` command must be run in each terminal before starting services.

### Production Deployment (systemd)

**Automated Installation:**
```bash
# Install as systemd services (builds binaries, creates services)
sudo ./install-systemd-services.sh

# Edit production config
sudo nano /opt/auspex/config/auspex.conf

# Start services
sudo systemctl start auspex-poller auspex-alerter auspex-api

# Enable auto-start on boot (done automatically by installer)
sudo systemctl enable auspex-poller auspex-alerter auspex-api
```

**Manual Service Management:**
```bash
# Start services
sudo systemctl start auspex-poller
sudo systemctl start auspex-alerter
sudo systemctl start auspex-api

# Stop services
sudo systemctl stop auspex-poller auspex-alerter auspex-api

# View logs
sudo journalctl -u auspex-poller -f
sudo journalctl -u auspex-alerter -f
sudo journalctl -u auspex-api -f

# Check status
sudo systemctl status auspex-poller auspex-alerter auspex-api
```

**Uninstall Services:**
```bash
sudo ./uninstall-systemd-services.sh
```

### Adding Targets

Four methods (in order of ease):
1. **Web UI:** Navigate to http://localhost:8080, fill out "Add New Target" form, or use CSV bulk import
2. **Script:** `./add-target.sh` - Interactive command-line wizard
3. **API:** POST JSON to `/api/targets` - See API endpoints section
4. **SQL:** Direct INSERT into targets table - For advanced use only

### Setting Up Alerts 🆕

**1. Create notification channel:**
```bash
curl -X POST http://localhost:8080/api/alert-channels \
  -H "Content-Type: application/json" \
  -d '{
    "name": "PagerDuty - Critical",
    "type": "pagerduty",
    "config": {"routing_key": "YOUR_KEY"},
    "enabled": true
  }'
```

**2. Create alert rule:**
```bash
curl -X POST http://localhost:8080/api/alert-rules \
  -H "Content-Type: application/json" \
  -d '{
    "target_id": 1,
    "channel_ids": [1],
    "rule_type": "status_change",
    "severity": "critical",
    "enabled": true
  }'
```

**3. Schedule maintenance window:**
```bash
curl -X POST http://localhost:8080/api/alert-suppressions \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Nightly Maintenance",
    "target_id": null,
    "recurrence": "daily",
    "start_time": "2025-11-17T02:00:00Z",
    "end_time": "2025-11-17T06:00:00Z",
    "enabled": true
  }'
```

### Testing SNMP Connectivity

Before adding devices, verify with: `snmpwalk -v 2c -c public <host> system`

---

## Code Conventions

### Go (cmd/poller/, cmd/alerter/)
- Standard gofmt formatting
- Error handling logs and continues (resilient to individual failures)
- Goroutines with semaphore rate limiting
- All config loaded at startup via environment variables
- JSON for structured logging (alerter)
- SMTP.PlainAuth for email authentication
- HTTP client with timeouts for external APIs

### Node.js (webui/)
- Modern ES6+ with async/await
- Parameterized queries (never string concatenation)
- Error responses as `{ error: "message" }` with HTTP status codes
- LATERAL joins for "latest per target" pattern
- JSONB for flexible channel configurations

### Frontend (webui/*.html)
- Vanilla JavaScript (no framework)
- Auto-refresh: 5 seconds (dashboard), 10 seconds (detail page)
- Status colors: Green (up), Red (down), Gray (unknown)
- Chart.js for visualization

---

## Testing Strategies

### Manual Testing

**Polling verification:** Watch logs for "polling X targets" and per-device results.

**API verification:** Test CRUD operations on targets:
```bash
curl http://localhost:8080/api/targets
curl -X POST ... # Add
curl -X PUT ... # Update
curl -X DELETE ... # Remove
```

**Alerting verification:** 🆕
```bash
# Check alert rules
curl http://localhost:8080/api/alert-rules

# Check alert history
curl http://localhost:8080/api/alert-history

# Check active alerts
curl http://localhost:8080/api/alert-history/active

# Check suppressions
curl http://localhost:8080/api/alert-suppressions/active
```

**Database validation:** Query latest status, uptime percentages, check enabled targets only.

### Edge Cases

**Polling:**
- Invalid SNMP credentials (status='down', message shows error)
- Network timeouts (status='unknown')
- Concurrent polls exceeding max limit (semaphore queues)
- Disabled targets ignored (enabled filter in query)
- Zero latency on failed polls (latency_ms = 0)

**Alerting:** 🆕
- Status flapping (rapid up/down changes) - handled by de-duplication
- Alert during maintenance window - suppressed, no notification
- Multiple channels failing - logged in alert_deliveries
- PagerDuty API timeout - retries with backoff
- SMTP authentication failure - logged as delivery failure
- Duplicate alerts for same state - prevented by alert_state table

---

## Common Error Messages

Understanding typical error messages helps diagnose issues quickly:

**Database Errors:**
- `relation "targets" does not exist` → Database schema not initialized; run `db-init-new.sql`
- `relation "alert_channels" does not exist` → Alerting schema not initialized; run `db-alerting-schema.sql`
- `password authentication failed for user "auspex"` → Incorrect `AUSPEX_DB_PASSWORD` or user not created
- `database "auspexdb" does not exist` → Run `setup-database.sh` or create database manually
- `could not connect to server` → PostgreSQL not running or wrong host/port

**SNMP Errors:**
- `Request timeout (after 0 retries)` → Network connectivity issue, firewall blocking UDP 161, or device down
- `Unknown host` → DNS resolution failure or invalid hostname
- `Authentication failed` → Incorrect community string
- `No Such Name` → OID not supported by device (check SNMP version compatibility)

**Alerting Errors:**
- `SMTP authentication failed` → Check `AUSPEX_SMTP_USER` and `AUSPEX_SMTP_PASSWORD`
- `dial tcp: i/o timeout` (SMTP) → SMTP server unreachable, check `AUSPEX_SMTP_HOST` and port
- `535 5.7.8 Username and Password not accepted` (Gmail) → Use app-specific password, not account password
- `PagerDuty API error: 401` → Invalid integration key in alert channel config
- `PagerDuty API error: 400` → Malformed request payload; check alert data

**API Errors:**
- `Cannot read property of undefined` → Missing required field in request body
- `Foreign key violation` → Referenced target/channel doesn't exist
- `duplicate key value violates unique constraint` → Record already exists
- `column "X" does not exist` → Schema mismatch; update database schema

**Configuration Errors:**
- `AUSPEX_DB_PASSWORD environment variable not set` → Configuration file not sourced; run `export $(grep -v '^#' config/auspex.conf | xargs)`
- `listen EADDRINUSE :::8080` → Port 8080 already in use; find process with `sudo lsof -i :8080` or `ss -tlnp | grep :8080`, then kill it
- `permission denied` (config file) → Fix permissions: `chmod 600 config/auspex.conf`
- `config/auspex.conf: No such file or directory` → Create from template: `cp config/auspex.conf.template config/auspex.conf`

**Setup Script Errors:**
- `setup-database.sh: password authentication failed for user "postgres"` → Script uses peer authentication with `sudo -u postgres psql` (no password needed)
- `failed to ping DB: pq: password authentication failed for user "auspex"` → Environment variables not loaded; run export command first

---

## Security Considerations

### Critical Items

- **Database password:** Change from example (`yourpassword`) in production (CRITICAL)
- **Community strings:** SNMPv2c community strings in plaintext (design limitation)
- **API endpoints:** No authentication implemented; assume internal network
- **Poll results:** Include device messages (potential info disclosure)
- **Data retention:** poll_results table grows unbounded (implement purge policy)
- **SMTP credentials:** Stored in environment variables; protect auspex.conf file 🆕
- **PagerDuty keys:** Stored in database as JSONB; restrict database access 🆕
- **Alert channels:** Email addresses visible in database; consider encryption 🆕

### Best Practices 🆕

**File Permissions:**
```bash
chmod 600 config/auspex.conf
chown auspex:auspex config/auspex.conf
```

**Database Access:**
```bash
# Restrict PostgreSQL to localhost only
# Edit postgresql.conf: listen_addresses = 'localhost'
# Edit pg_hba.conf: host auspexdb auspex 127.0.0.1/32 scram-sha-256
```

**SMTP Security:**
- Use app-specific passwords (Gmail)
- Enable TLS (port 587, not 465)
- Rotate passwords regularly

---

## Performance Characteristics

Understanding expected performance helps identify issues:

**Resource Usage:**
- **Memory:** ~20-50MB per Go daemon (poller/alerter) under normal load
- **CPU:** Minimal (<5%) during polling; spikes briefly during SNMP queries
- **Database:** Read-heavy (90% SELECT), write spikes every poll interval
- **Network:** Burst traffic during poll cycles (UDP 161), continuous HTTPS/SMTP for alerts

**Latency Expectations:**
- **SNMP polls:** <100ms for healthy devices (2-second timeout configured)
- **API calls:** <50ms for simple queries, <200ms for complex aggregations
- **Database queries:** <10ms for indexed lookups, <100ms for history queries
- **Alert delivery:** 1-5 seconds (SMTP/HTTPS round-trip to external services)

**Scalability:**
- **Tested with:** 100+ targets, 10,000+ poll_results records
- **Recommended limits:**
  - Max targets: 500 (with default 60s poll interval)
  - Max concurrent polls: 20 (adjust `AUSPEX_MAX_CONCURRENT_POLLS`)
  - Poll interval: Minimum 30 seconds (to avoid overwhelming devices)
- **Database growth:** ~1MB per 10,000 poll results; implement retention policy

**Bottlenecks:**
- **Database size:** Unbounded `poll_results` table; archive/purge old data
- **SNMP timeouts:** Slow/unresponsive devices delay entire poll cycle
- **Alert spam:** Status flapping can overwhelm notification channels
- **Concurrent polls:** Too many simultaneous SNMP queries can saturate network

---

## Common Development Tasks

### Adding API Endpoint

1. Add route to server.js with proper error handling
2. Use parameterized queries for database access
3. Return JSON with 200/400/500 status codes
4. Log requests for debugging

### Modifying SNMP Poll Logic

Edit `pollTargetSNMP()` in cmd/poller/main.go:
- Adjust OIDs queried
- Modify timeout/retry values
- Change success criteria

### Adding Alert Notification Channel 🆕

1. Add new channel type to alert_channels table
2. Implement sender function in cmd/alerter/main.go (e.g., `sendWebhookAlert()`)
3. Add channel type to `sendNotifications()` switch statement
4. Update API validation in webui/server.js
5. Document in ALERTING-SETUP.md

### Adding Database Index

Create in db-init-new.sql or db-alerting-schema.sql:
```sql
CREATE INDEX idx_name ON table (column);
```
Then reload schema.

### Implementing Data Retention

Add scheduled purge job:
```sql
-- Poll results (keep 30 days)
DELETE FROM poll_results
WHERE polled_at < NOW() - INTERVAL '30 days';

-- Alert history (keep 90 days)
DELETE FROM alert_history
WHERE fired_at < NOW() - INTERVAL '90 days';
```

---

## Deployment Notes

### Production Checklist

**Core System:**
- Change database password
- Set `enabled=true` only for real targets
- Configure appropriate poll interval
- Implement data retention policy
- Use systemd service or container for auto-restart
- Monitor poller and API logs

**Alerting:** 🆕
- Configure SMTP credentials
- Set up notification channels (PagerDuty, Slack, Email)
- Create alert rules for critical targets
- Test alert delivery to all channels
- Schedule maintenance windows for planned downtime
- Set de-duplication window appropriately
- Enable alerter service

### Systemd Service Example

**Poller:**
```ini
[Unit]
Description=Auspex SNMP Poller
After=network.target postgresql.service

[Service]
Type=simple
User=auspex
WorkingDirectory=/opt/auspex
EnvironmentFile=/opt/auspex/config/auspex.conf
ExecStart=/opt/auspex/bin/auspex-poller
# Development alternative: ExecStart=/usr/bin/go run /opt/auspex/cmd/poller/main.go
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

**Alerter:** 🆕
```ini
[Unit]
Description=Auspex Alerting Engine
After=network.target postgresql.service

[Service]
Type=simple
User=auspex
WorkingDirectory=/opt/auspex
EnvironmentFile=/opt/auspex/config/auspex.conf
ExecStart=/opt/auspex/bin/auspex-alerter
# Development alternative: ExecStart=/usr/bin/go run /opt/auspex/cmd/alerter/main.go
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

---

## Troubleshooting Guide

### Polling Issues

**"No enabled targets to poll"**

Check database: `SELECT * FROM targets WHERE enabled=true;`

**Target shows down despite online device**

Verify SNMP connectivity: `snmpwalk -v 2c -c <community> <host> system`

Check credentials, community string, network firewall rules.

**API returns 500 errors**

Check server logs for database connection issues, malformed queries, or parameter mismatches.

**Dashboard shows old data**

Verify poller runs continuously (check process, logs). Confirm database writes succeed. Check browser cache/refresh timing.

**High memory usage**

Monitor go process: `ps aux | grep poller`. Consider reducing poll interval or target count if memory grows unbounded.

**Database connection errors**

Verify PostgreSQL running, credentials correct, database exists. Check firewall between application and database server.

### Alerting Issues 🆕

**No alerts being sent**

1. Verify alerter is running: `ps aux | grep alerter`
2. Check alert rules exist: `SELECT * FROM alert_rules WHERE enabled=true;`
3. Check device status changed: `SELECT * FROM poll_results ORDER BY polled_at DESC LIMIT 10;`
4. Check alert state: `SELECT * FROM alert_state;`
5. Review alerter logs for errors

**Alerts not delivered**

1. Check delivery logs: `SELECT * FROM alert_deliveries WHERE status='failure';`
2. Verify SMTP configuration: `echo "Test" | mail -s "Test" test@example.com`
3. Test PagerDuty integration key
4. Verify Slack email address
5. Check network connectivity to external services

**Too many alerts (alert spam)**

1. Increase de-duplication window: `AUSPEX_ALERTER_DEDUP_WINDOW_MINUTES=30`
2. Check for status flapping: `SELECT * FROM alert_state WHERE state_change_count > 5;`
3. Create suppression for flapping targets
4. Review alert rule severity levels

**Alerts during maintenance**

1. Verify suppression exists: `SELECT * FROM alert_suppressions WHERE enabled=true;`
2. Check suppression times: `SELECT * FROM alert_suppressions WHERE target_id=X;`
3. Verify recurrence schedule matches maintenance window
4. Test suppression query: `SELECT * FROM isSuppressed(target_id);`

**PagerDuty incidents not created**

1. Verify integration key: Check config JSONB in alert_channels
2. Test PagerDuty API manually: `curl -X POST https://events.pagerduty.com/v2/enqueue ...`
3. Check PagerDuty service status
4. Review delivery logs for HTTP errors

**Email not received**

1. Check SMTP credentials: `AUSPEX_SMTP_USER`, `AUSPEX_SMTP_PASSWORD`
2. Verify SMTP server: `telnet smtp.gmail.com 587`
3. Check spam folder
4. Review email logs in alert_deliveries
5. Test SMTP authentication: Use mail command

---

## AI Assistant Best Practices

### Code Changes

- Test SNMP connectivity before database modifications
- Preserve existing polling logic when extending features
- Use parameterized queries exclusively
- Log all database operations for debugging
- For alerting changes, test notification delivery to all channels 🆕
- Verify alert de-duplication logic when modifying alert_state 🆕

### Debugging Issues

- Check logs first (poller stdout, alerter stdout, API stderr)
- Verify database state directly (psql queries)
- Test SNMP manually before claiming database issue
- Confirm configuration loaded (print env vars)
- For alerting: Check alert_history, alert_deliveries, and alert_state tables 🆕
- Test notification channels independently 🆕

### Adding Features

- Follow existing code style (gofmt, ES6)
- Add appropriate error handling
- Update database schema version if needed
- Document new endpoints/config variables
- For alerting features: Update both cmd/alerter/main.go and webui/server.js 🆕
- Add API endpoints before implementing daemon logic 🆕

---

## Important Files Reference

**Core:**
- **cmd/poller/main.go** - Polling logic
- **webui/server.js** - API routes
- **db-init-new.sql** - Core schema
- **webui/index.html** - Dashboard (includes add/edit/delete target UI)
- **webui/target.html** - Target detail page
- **config/auspex.conf.template** - Configuration template
- **package.json, go.mod** - Dependencies

**Alerting:** 🆕
- **cmd/alerter/main.go** - Alert monitoring logic
- **db-alerting-schema.sql** - Alerting schema
- **ALERTING-SETUP.md** - Alerting setup guide
- **start-alerter.sh** - Alerter startup script

**Setup Scripts:**
- **setup-database.sh** - Database initialization (uses peer auth)
- **install-systemd-services.sh** - Production deployment installer 🆕
- **uninstall-systemd-services.sh** - Service removal script 🆕
- **add-target.sh** - Interactive target addition wizard

**Documentation:**
- **README.md** - User-facing overview
- **GETTING-STARTED.md** - Quick start guide
- **DATABASE-SETUP.md** - Database configuration
- **SNMP-DEVICE-SETUP.md** - Device setup
- **PRODUCTION-READY.md** - Deployment guide
- **ROADMAP.md** - Project roadmap
- **CODEBASE-SUMMARY.md** - Developer reference
- **CLAUDE.md** - AI assistant reference (this document)

---

## Quick Command Reference

```bash
# Initial Setup
cp config/auspex.conf.template config/auspex.conf
chmod 600 config/auspex.conf
nano config/auspex.conf  # Edit database password
./setup-database.sh
cd webui && npm install && cd ..

# Development (load env vars first!)
export $(grep -v '^#' config/auspex.conf | xargs)
go run cmd/poller/main.go
go run cmd/alerter/main.go  # 🆕
node webui/server.js

# Production Installation
sudo ./install-systemd-services.sh
sudo systemctl start auspex-poller auspex-alerter auspex-api
sudo journalctl -u auspex-poller -f  # View logs

# Testing
snmpwalk -v 2c -c public <host> system
PGPASSWORD='yourpassword' psql -h localhost -U auspex -d auspexdb

# API - Targets
curl http://localhost:8080/api/targets
curl -X POST http://localhost:8080/api/targets -H "Content-Type: application/json" ...

# API - Alerts 🆕
curl http://localhost:8080/api/alert-channels
curl http://localhost:8080/api/alert-rules
curl http://localhost:8080/api/alert-history
curl http://localhost:8080/api/alert-history/active
curl http://localhost:8080/api/alert-suppressions

# Database (manual init)
sudo -u postgres psql -c "CREATE USER auspex WITH PASSWORD 'yourpassword';"
sudo -u postgres psql -c "CREATE DATABASE auspexdb OWNER auspex;"
PGPASSWORD='yourpassword' psql -h localhost -U auspex -d auspexdb -f db-init-new.sql
PGPASSWORD='yourpassword' psql -h localhost -U auspex -d auspexdb -f db-alerting-schema.sql  # 🆕

# Clean demo data
PGPASSWORD='yourpassword' psql -h localhost -U auspex -d auspexdb -c "DELETE FROM targets;"

# Systemd Service Management
sudo systemctl start auspex-poller
sudo systemctl start auspex-alerter  # 🆕
sudo systemctl start auspex-api
sudo systemctl status auspex-poller auspex-alerter auspex-api
sudo journalctl -u auspex-poller -f

# Troubleshooting
sudo lsof -i :8080  # Find process using port 8080
ps aux | grep -E "node|poller|alerter"  # Find running processes
sudo kill <PID>  # Stop conflicting process
```

---

## Known Limitations & Future Improvements

### Current Limitations

- SNMPv2c only (no v1 or v3 support) - **SNMPv3 planned (see ROADMAP.md)**
- ~~No alerting/notifications~~ **✅ IMPLEMENTED in v1.1**
- No authentication on API endpoints
- Community strings stored in plaintext
- Unbounded poll_results table growth (implement retention policy)
- Hardcoded configuration paths
- SMTP credentials in plaintext environment variables
- No webhook notification channel (only PagerDuty, Slack email, SMTP) - **Planned for v1.2**

### Potential Improvements

**High Priority (See ROADMAP.md):**
- **SNMP MIB Database** - Device-specific OID monitoring with templates
- **ICMP Ping Polling** - Alternative polling via ping (no SNMP required)
- **Splunk HEC Integration** - Export metrics to Splunk

**Under Consideration:**
- API authentication/authorization
- Data retention policies with automatic archiving
- Web UI for alert management (currently API-only)
- Multi-user support
- Metric collection beyond status (CPU, memory, interfaces)
- SNMPv3 support with encryption
- Advanced dashboards & reporting
- Mobile application
- Multi-tenancy

**Alerting Enhancements:** 🆕
- Webhook notification channel
- Alert escalation policies
- Alert grouping and correlation
- Custom alert templates
- SMS notifications (Twilio integration)
- Microsoft Teams integration
- Alert acknowledgment and comments
- Alert routing based on time of day
- Integration with ticketing systems (Jira, ServiceNow)

---

## Roadmap Reference

See **[ROADMAP.md](ROADMAP.md)** for:
- Detailed feature proposals
- Priority levels and effort estimates
- Feature status tracking
- Community contribution guidelines

**Note:** The ROADMAP.md file may not yet reflect the completed alerting engine. Refer to this document for current state.

---

## Version History

**v1.1 (2025-11-17) - Alerting Engine**
- Added comprehensive alerting system with PagerDuty, Slack, and email notifications
- Implemented alert suppression with maintenance windows
- Added de-duplication and state tracking
- Created 6 new database tables for alert management
- Added 15+ new API endpoints for alert operations
- Updated architecture diagram
- Enhanced documentation with ALERTING-SETUP.md

**v1.0 (Initial Release) - 2025-11-17**
- Core SNMP monitoring functionality
- Web dashboard and REST API
- PostgreSQL backend
- Basic target management
- Documentation suite

---

## Support & Resources

Refer to companion documentation:
- **README.md** - User-facing overview
- **GETTING-STARTED.md** - Quick start
- **DATABASE-SETUP.md** - Database configuration
- **SNMP-DEVICE-SETUP.md** - Device setup
- **PRODUCTION-READY.md** - Deployment guide
- **ALERTING-SETUP.md** - Alerting configuration 🆕
- **ROADMAP.md** - Future features and planning

**Community:**
- GitHub Issues: Report bugs, request features
- GitHub Discussions: Ask questions, share ideas
- Pull Requests: Contribute code and documentation

---

**Document Version:** 1.2.0
**Last Review:** 2025-11-17 (Session-based improvements)
**Next Review:** As needed (after major feature releases)
**Reflects System:** Auspex v1.1 with Alerting Engine + Production Deployment Tools

**v1.2.0 Changes (Session-based improvements):**
- Added systemd installation scripts (`install-systemd-services.sh`, `uninstall-systemd-services.sh`)
- Enhanced Development Workflows with First-Time Setup section
- Updated setup-database.sh to use peer authentication (sudo -u postgres)
- Added Setup Script Errors to Common Error Messages section
- Documented web UI target management features
- Added troubleshooting commands for port conflicts
- Updated Quick Command Reference with complete workflow
- Added database cleanup commands for demo data
- Enhanced Important Files Reference with new scripts

**v1.1.1 Changes:**
- Fixed webhook support claim (removed from features, added to roadmap)
- Updated systemd service examples to use compiled binaries
- Added Common Error Messages section for faster debugging
- Added Performance Characteristics section
- Added function line numbers for key code files
- Enhanced Configuration section with development path workaround
- Standardized password examples to `yourpassword`
