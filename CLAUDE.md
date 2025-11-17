# CLAUDE.md - AI Assistant Guide for Auspex

## Project Overview

**Auspex** is a lightweight, real-time SNMP network monitoring system with a web dashboard. It monitors network devices (routers, switches, firewalls, servers, etc.) via SNMPv2c and provides live status updates, latency tracking, and uptime statistics.

### Core Purpose
- Monitor SNMP-enabled network devices in real-time
- Provide a web-based dashboard for visualization
- Track historical latency and uptime metrics
- Offer REST API access to monitoring data

### Technology Stack
- **Backend Poller:** Go 1.25+ (SNMP polling daemon)
- **Web API:** Node.js + Express (REST API server)
- **Database:** PostgreSQL 12+ (data persistence)
- **Frontend:** Vanilla JavaScript + Chart.js (no framework)
- **SNMP Library:** gosnmp (github.com/gosnmp/gosnmp)
- **Database Driver:** pg (Node.js), lib/pq (Go)

## Repository Structure

```
auspex/
├── cmd/
│   └── poller/
│       └── main.go                 # Go SNMP polling daemon (core monitoring logic)
├── webui/
│   ├── server.js                   # Express API server (Node.js)
│   ├── index.html                  # Main dashboard (list all targets)
│   ├── target.html                 # Target detail page (graphs, stats)
│   └── user-guide.html             # User guide (currently empty)
├── api/
│   └── db-init.sql                 # Legacy/alternative DB init (empty)
├── config/                         # Created at runtime (gitignored)
│   └── auspex.conf                 # Main configuration file (NOT in repo)
├── db-init-new.sql                 # Database schema initialization
├── auspex.conf.example             # Example configuration template
├── .env.example                    # Alternative env format
├── add-target.sh                   # Interactive CLI to add targets
├── setup-database.sh               # Database setup automation
├── targets-template.csv            # CSV template for bulk import
├── package.json                    # Node.js dependencies
├── go.mod                          # Go module definition
├── go.sum                          # Go dependency checksums
├── README.md                       # User-facing documentation
├── GETTING-STARTED.md              # Quick start guide
├── DATABASE-SETUP.md               # Database configuration guide
├── SNMP-DEVICE-SETUP.md            # Device configuration guide
├── PRODUCTION-READY.md             # Production deployment guide
└── .gitignore                      # Git ignore rules
```

## Architecture

### System Components

```
┌─────────────────┐
│   Web Browser   │ (User Interface)
│  (Dashboard)    │
└────────┬────────┘
         │ HTTP (port 8080)
         ▼
┌─────────────────┐      ┌──────────────┐
│  Express API    │◄────►│  PostgreSQL  │
│  (Node.js)      │ SQL  │   Database   │
│  webui/         │      │  (port 5432) │
└─────────────────┘      └──────────────┘
         ▲                       ▲
         │                       │
         │ Reads poll results    │ Writes poll results
         │                       │
┌─────────────────┐              │
│  SNMP Poller    │──────────────┘
│  (Go daemon)    │
│  cmd/poller/    │
└────────┬────────┘
         │ SNMP (UDP port 161)
         ▼
┌──────────────────┐
│ Network Devices  │
│ (routers, etc.)  │
└──────────────────┘
```

### Data Flow

1. **Polling Cycle** (every 60 seconds by default):
   - Go poller reads enabled targets from PostgreSQL
   - Polls each device via SNMP (concurrent, up to 10 at once)
   - Writes poll results (status, latency, message) to PostgreSQL

2. **Web Dashboard**:
   - Browser requests data from Express API
   - Express queries PostgreSQL for latest results
   - API returns JSON data
   - Frontend updates UI with status indicators and charts
   - Auto-refreshes every 5-10 seconds

3. **User Actions**:
   - Add/edit/delete targets via web UI or API
   - Changes persist to PostgreSQL
   - Poller picks up changes on next cycle

## Database Schema

### `targets` Table
Stores SNMP target device configurations.

| Column       | Type         | Description                    |
|--------------|--------------|--------------------------------|
| id           | SERIAL       | Primary key                    |
| name         | VARCHAR(255) | Device display name            |
| host         | VARCHAR(255) | IP address or hostname         |
| port         | INTEGER      | SNMP port (default: 161)       |
| community    | VARCHAR(100) | SNMP community string          |
| snmp_version | VARCHAR(20)  | '1', '2c', or '3' (only 2c works) |
| enabled      | BOOLEAN      | Whether to poll this device    |
| created_at   | TIMESTAMP    | Record creation time           |
| updated_at   | TIMESTAMP    | Last modification time         |

**Indexes:**
- `idx_targets_enabled` on `enabled` (WHERE enabled = true)
- `idx_targets_host` on `host`

### `poll_results` Table
Stores historical polling results.

| Column     | Type      | Description                        |
|------------|-----------|------------------------------------|
| id         | BIGSERIAL | Primary key                        |
| target_id  | INTEGER   | Foreign key to targets(id)         |
| status     | VARCHAR(20) | 'up', 'down', or 'unknown'       |
| latency_ms | INTEGER   | Response time in milliseconds      |
| message    | TEXT      | SNMP response or error message     |
| polled_at  | TIMESTAMP | When poll occurred                 |

**Indexes:**
- `idx_poll_results_target_polled` on `(target_id, polled_at DESC)`
- `idx_poll_results_polled_at` on `polled_at DESC`
- `idx_poll_results_status` on `status`

**Important:** `poll_results` grows continuously. Production deployments should implement data retention policies.

## Configuration

### Environment Variables

Configuration is loaded from `auspex.conf` (or `.env`) with these variables:

```bash
# Database
AUSPEX_DB_HOST=localhost           # PostgreSQL host
AUSPEX_DB_PORT=5432                # PostgreSQL port
AUSPEX_DB_NAME=auspexdb            # Database name
AUSPEX_DB_USER=auspex              # Database user
AUSPEX_DB_PASSWORD=CHANGE_THIS     # Database password (CRITICAL: change in production!)

# API Server
AUSPEX_API_PORT=8080               # Express server port

# Poller Settings
AUSPEX_POLL_INTERVAL_SECONDS=60    # How often to poll devices
AUSPEX_MAX_CONCURRENT_POLLS=10     # Max concurrent SNMP polls
```

### Configuration File Locations

The code expects configuration at hardcoded paths:
- **Go poller:** Reads from environment variables (loaded via `export $(cat config/auspex.conf | xargs)`)
- **Node.js API:** Hardcoded to `/opt/auspex/config/auspex.conf` in webui/server.js:2
  - **AI Assistant Note:** This is a deployment-specific path. For local development, you may need to adjust this path or use environment variables directly.

## Key Code Files

### cmd/poller/main.go (Go Poller)

**Purpose:** Main SNMP polling daemon

**Key Functions:**
- `main()` - Entry point, connects to DB, starts polling loop
- `pollOnce()` - Executes one polling cycle for all enabled targets
- `loadTargets()` - Queries DB for enabled targets
- `pollTargetSNMP()` - Performs actual SNMP query to device
- `insertResult()` - Writes poll result to database

**SNMP Polling Logic:**
- Queries three OIDs: sysDescr, sysUpTime, sysName (1.3.6.1.2.1.1.{1,3,5}.0)
- Timeout: 2 seconds per device
- Retries: 1
- Success = all three OIDs return values
- Latency = round-trip time from Connect() to Get() response

**Concurrency:**
- Uses goroutines with semaphore pattern (`sem := make(chan struct{}, maxConcurrent)`)
- WaitGroup ensures all polls complete before next cycle

**Error Handling:**
- Logs errors but continues polling other targets
- Failed polls recorded as status='down', latency_ms=0

### webui/server.js (Express API)

**Purpose:** REST API server and static file host

**Key Routes:**

**Target Management:**
- `GET /api/targets` - List all targets with latest poll status (uses LATERAL join)
- `POST /api/targets` - Add new target
- `PUT /api/targets/:id` - Update target configuration
- `DELETE /api/targets/:id` - Soft-delete (set enabled=false)
- `DELETE /api/targets/:id/delete` - Hard-delete (removes all data)

**Target Details:**
- `GET /api/targets/:id/info` - Target configuration
- `GET /api/targets/:id/latest` - Most recent poll result
- `GET /api/targets/:id/latency` - Last hour of latency samples
- `GET /api/targets/:id/stats` - Last hour statistics (min/max/avg, uptime %)

**Static Files:**
- `GET /` or `/index.html` - Main dashboard
- `GET /target.html?id=X` - Target detail page
- All files in `webui/` directory are served statically

**Database Connection:**
- Uses connection pool (`pg.Pool`)
- No explicit connection management (pool handles it)

### db-init-new.sql (Database Schema)

**Purpose:** Initialize PostgreSQL database schema

**What it does:**
1. Drops existing tables (CASCADE)
2. Creates `targets` table with constraints
3. Creates `poll_results` table with foreign key
4. Adds performance indexes
5. Inserts sample data (comment out for production!)

**Important Constraints:**
- Port: 1-65535
- SNMP version: must be '1', '2c', or '3'
- Status: must be 'up', 'down', or 'unknown'
- Latency: must be >= 0
- ON DELETE CASCADE: deleting target removes all poll results

## Development Workflows

### Starting the Application

**Prerequisites:**
1. PostgreSQL running and initialized
2. Configuration file created (copy from auspex.conf.example)
3. Dependencies installed (`npm install`, `go mod download`)

**Start Services:**

```bash
# Terminal 1: Start poller
cd /home/user/auspex
export $(cat auspex.conf.example | xargs)
go run cmd/poller/main.go

# Terminal 2: Start API server
cd /home/user/auspex
export $(cat auspex.conf.example | xargs)
node webui/server.js

# Terminal 3: Access dashboard
curl http://localhost:8080/api/targets
# Or open http://localhost:8080 in browser
```

**Note:** The hardcoded path in server.js may cause issues. Consider modifying to use relative paths or environment variables.

### Adding a New Target

**Method 1: Interactive Script**
```bash
./add-target.sh
```

**Method 2: API Call**
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

**Method 3: Direct SQL**
```sql
INSERT INTO targets (name, host, port, community, snmp_version, enabled)
VALUES ('My-Router', '192.168.1.1', 161, 'public', '2c', true);
```

### Testing SNMP Connectivity

Before adding a device, test SNMP manually:

```bash
# Install snmp tools (if needed)
# Ubuntu: sudo apt-get install snmp
# macOS: brew install net-snmp

# Test query
snmpwalk -v 2c -c public 192.168.1.1 system
```

Expected output should include sysDescr, sysUpTime, sysName, etc.

### Database Operations

**Connect to Database:**
```bash
psql -U auspex -d auspexdb
```

**Common Queries:**
```sql
-- View all targets
SELECT * FROM targets;

-- View latest poll for each target
SELECT t.name, t.host, pr.status, pr.latency_ms, pr.polled_at
FROM targets t
LEFT JOIN LATERAL (
    SELECT * FROM poll_results
    WHERE target_id = t.id
    ORDER BY polled_at DESC
    LIMIT 1
) pr ON TRUE;

-- View devices currently down
SELECT t.name, pr.status, pr.message
FROM targets t
JOIN LATERAL (
    SELECT * FROM poll_results
    WHERE target_id = t.id
    ORDER BY polled_at DESC
    LIMIT 1
) pr ON TRUE
WHERE pr.status = 'down';

-- View uptime % (last 24 hours)
SELECT t.name,
       COUNT(*) FILTER (WHERE pr.status = 'up') * 100.0 / COUNT(*) as uptime_pct
FROM targets t
JOIN poll_results pr ON pr.target_id = t.id
WHERE pr.polled_at > NOW() - INTERVAL '24 hours'
GROUP BY t.name;
```

## Code Conventions & Patterns

### Go Code (cmd/poller/)

**Style:**
- Standard Go formatting (gofmt)
- Error handling: log and continue (don't crash on single target failure)
- Concurrency: goroutines with semaphore pattern for rate limiting

**Logging:**
- All log output goes to stdout
- Format: `log.Printf("message %v", value)`
- Log every poll result for debugging

**Environment Variables:**
- Helper function: `getenv(key, fallback string)`
- All config loaded at startup

### Node.js Code (webui/)

**Style:**
- Modern JavaScript (ES6+)
- Async/await for database operations
- Error handling: try/catch with 500 status codes

**API Responses:**
- Success: JSON object or array
- Error: `{ error: "message" }` with appropriate HTTP status

**Database Queries:**
- Use parameterized queries ($1, $2, etc.) - **never string concatenation**
- LATERAL joins for "latest poll per target" pattern
- Connection pool managed automatically

### Frontend Code (webui/*.html)

**Style:**
- Vanilla JavaScript (no framework)
- Inline scripts in HTML files
- Chart.js for visualization

**Auto-refresh:**
- Main dashboard: 5 seconds
- Target detail: 10 seconds
- Uses setInterval + fetch API

**Status Indicators:**
- Green (#4CAF50): up
- Red (#f44336): down
- Gray (#999): unknown/no data

## Testing Strategies

### Manual Testing

**1. Test Polling:**
```bash
# Watch poller logs
go run cmd/poller/main.go

# Should see:
# "Auspex SNMP poller started (interval=60s, maxConcurrent=10)"
# "polling X targets"
# "polled target 1 (name) host=... status=up latency=45ms"
```

**2. Test API:**
```bash
# List targets
curl http://localhost:8080/api/targets

# Add target
curl -X POST http://localhost:8080/api/targets -H "Content-Type: application/json" \
  -d '{"name":"Test","host":"127.0.0.1","port":161,"community":"public","snmp_version":"2c","enabled":true}'

# Update target
curl -X PUT http://localhost:8080/api/targets/1 -H "Content-Type: application/json" \
  -d '{"name":"Updated","host":"127.0.0.1","port":161,"community":"public","snmp_version":"2c","enabled":false}'

# Delete target (soft)
curl -X DELETE http://localhost:8080/api/targets/1

# Delete target (hard)
curl -X DELETE http://localhost:8080/api/targets/1/delete
```

**3. Test Database:**
```sql
-- Verify schema
\dt
\d targets
\d poll_results

-- Verify indexes
\di

-- Check data
SELECT COUNT(*) FROM targets;
SELECT COUNT(*) FROM poll_results;
```

### Edge Cases to Consider

1. **Target with invalid IP:** Should poll, fail, record status='down'
2. **Target with wrong community string:** Status='down', message includes error
3. **Target with SNMP disabled:** Timeout, status='down'
4. **Database connection lost:** Poller should crash (current behavior), API returns 500
5. **Zero enabled targets:** Poller logs "no enabled targets to poll"
6. **Very high latency device:** Should still work (2s timeout)
7. **Malformed API requests:** Should return 500 with error message

## Security Considerations

### Critical Security Items

1. **Database Password:**
   - Default is `yourpassword` in examples - **MUST change in production**
   - File permissions: `chmod 600 auspex.conf`

2. **SNMP Community Strings:**
   - Default is `public` - **weak security**
   - Use strong, unique strings in production
   - Consider SNMPv3 for authentication/encryption (not currently implemented)

3. **API Authentication:**
   - **Currently no authentication!**
   - Anyone with network access can add/delete targets
   - Consider adding API keys or OAuth for production

4. **SQL Injection:**
   - Code uses parameterized queries - **secure**
   - Never modify to use string concatenation

5. **Configuration Files:**
   - `.gitignore` excludes auspex.conf, .env - **correct**
   - Verify not committed to repo

6. **Network Exposure:**
   - API runs on 0.0.0.0:8080 (all interfaces)
   - PostgreSQL should be localhost-only
   - Use firewall rules to restrict access

7. **SNMP Access:**
   - Read-only community strings only
   - Devices should firewall SNMP to monitoring server IP only

See PRODUCTION-READY.md for complete security checklist.

## Common Development Tasks

### Adding a New API Endpoint

**Example: Add endpoint to get poll count for a target**

1. Add route in webui/server.js:
```javascript
app.get("/api/targets/:id/poll-count", async (req, res) => {
    try {
        const id = req.params.id;
        const result = await pool.query(
            `SELECT COUNT(*) as count FROM poll_results WHERE target_id = $1`,
            [id]
        );
        res.json({ count: parseInt(result.rows[0].count) });
    } catch (err) {
        console.error("Error fetching poll count:", err);
        res.status(500).json({ error: err.message });
    }
});
```

2. Test:
```bash
curl http://localhost:8080/api/targets/1/poll-count
```

3. Update documentation (README.md, this file)

### Modifying SNMP Poll Logic

**Example: Add additional OID to poll**

1. Edit cmd/poller/main.go in `pollTargetSNMP()`:
```go
oids := []string{
    "1.3.6.1.2.1.1.1.0", // sysDescr
    "1.3.6.1.2.1.1.3.0", // sysUpTime
    "1.3.6.1.2.1.1.5.0", // sysName
    "1.3.6.1.2.1.1.6.0", // sysLocation (NEW)
}
```

2. Update parsing logic to handle new OID
3. Consider: does message field need to include new data?
4. Test with real device

### Adding a Database Index

**Example: Index for filtering by status**

1. Add to db-init-new.sql:
```sql
CREATE INDEX idx_poll_results_target_status ON poll_results(target_id, status);
```

2. Apply to existing database:
```sql
psql -U auspex -d auspexdb -c "CREATE INDEX idx_poll_results_target_status ON poll_results(target_id, status);"
```

3. Verify:
```sql
\di idx_poll_results_target_status
EXPLAIN SELECT * FROM poll_results WHERE target_id=1 AND status='down';
```

### Implementing Data Retention

**Example: Delete poll results older than 30 days**

1. Create cron script:
```bash
#!/bin/bash
# cleanup-old-polls.sh
psql -U auspex -d auspexdb -c "DELETE FROM poll_results WHERE polled_at < NOW() - INTERVAL '30 days';"
```

2. Add to crontab:
```bash
# Run daily at 2 AM
0 2 * * * /path/to/cleanup-old-polls.sh
```

3. Consider: add VACUUM ANALYZE after deletion

## Deployment Notes

### Production Deployment Checklist

1. ✅ Change database password
2. ✅ Change SNMP community strings
3. ✅ Set file permissions on auspex.conf (chmod 600)
4. ✅ Configure PostgreSQL for localhost-only access
5. ✅ Add API authentication (custom implementation needed)
6. ✅ Set up reverse proxy with HTTPS (nginx recommended)
7. ✅ Implement database backups (see PRODUCTION-READY.md)
8. ✅ Configure systemd services (see PRODUCTION-READY.md)
9. ✅ Set up data retention policy
10. ✅ Configure firewall rules
11. ✅ Monitor the monitoring system (meta-monitoring)

### Systemd Service Example

**Poller:**
```ini
[Unit]
Description=Auspex SNMP Poller
After=postgresql.service

[Service]
Type=simple
User=auspex
EnvironmentFile=/opt/auspex/config/auspex.conf
WorkingDirectory=/opt/auspex
ExecStart=/usr/local/go/bin/go run /opt/auspex/cmd/poller/main.go
Restart=always

[Install]
WantedBy=multi-user.target
```

**API Server:**
```ini
[Unit]
Description=Auspex Web API
After=postgresql.service

[Service]
Type=simple
User=auspex
EnvironmentFile=/opt/auspex/config/auspex.conf
WorkingDirectory=/opt/auspex/webui
ExecStart=/usr/bin/node /opt/auspex/webui/server.js
Restart=always

[Install]
WantedBy=multi-user.target
```

## Troubleshooting Guide for AI Assistants

### Issue: Poller shows "no enabled targets to poll"
- Check: `SELECT * FROM targets WHERE enabled = true;`
- Fix: Enable targets or add new ones

### Issue: Target shows "down" but device is online
- Check SNMP manually: `snmpwalk -v 2c -c public HOST system`
- Verify community string matches
- Check firewall rules (UDP 161)
- Confirm SNMP is enabled on device

### Issue: API returns 500 errors
- Check database connection: `psql -U auspex -d auspexdb -c "SELECT 1"`
- Check Node.js logs in terminal
- Verify PostgreSQL is running: `pg_isready`

### Issue: Dashboard shows old data
- Check poller is running: `ps aux | grep "go run.*poller"`
- Check latest poll time: `SELECT MAX(polled_at) FROM poll_results;`
- Hard refresh browser (Ctrl+Shift+R)

### Issue: High memory usage
- Check poll_results table size: `SELECT pg_size_pretty(pg_total_relation_size('poll_results'));`
- Consider implementing data retention
- Reduce AUSPEX_MAX_CONCURRENT_POLLS
- Increase AUSPEX_POLL_INTERVAL_SECONDS

### Issue: Database connection errors
- Verify PostgreSQL is running
- Check credentials in auspex.conf
- Test connection: `psql -U auspex -d auspexdb -h localhost`
- Check pg_hba.conf allows local connections

## AI Assistant Best Practices

### When Making Code Changes

1. **Understand the data flow:** Poller → Database ← API ← Frontend
2. **Maintain backward compatibility:** Old poll_results should still work
3. **Use parameterized queries:** Never concatenate SQL strings
4. **Log errors, don't crash:** Especially in poller (one failure shouldn't stop all polling)
5. **Update documentation:** README.md, GETTING-STARTED.md, this file
6. **Consider security:** API has no auth, be careful with new endpoints
7. **Test manually:** Run poller and API locally before committing

### When Debugging Issues

1. **Check logs first:** Poller and API output to stdout
2. **Query database directly:** Often reveals the actual state
3. **Test components independently:** SNMP, database, API, frontend
4. **Use curl for API testing:** Easier than browser for debugging
5. **Check process status:** `ps aux | grep -E "go run|node.*server"`

### When Adding Features

1. **Read existing code:** Follow established patterns
2. **Update schema carefully:** Consider migration path for existing data
3. **Add indexes for new queries:** Performance matters with large poll_results
4. **Update all documentation:** Users need to know about new features
5. **Consider configuration:** Should it be configurable via auspex.conf?

## Important Files Reference

| File | Purpose | Modify When |
|------|---------|-------------|
| cmd/poller/main.go | SNMP polling logic | Changing poll behavior, adding OIDs, modifying concurrency |
| webui/server.js | API endpoints | Adding/modifying API routes, database queries |
| webui/index.html | Main dashboard | Changing main UI, adding features to target list |
| webui/target.html | Target detail page | Changing detail view, graphs, stats |
| db-init-new.sql | Database schema | Adding tables, columns, indexes, constraints |
| auspex.conf.example | Configuration template | Adding new config options |
| README.md | User documentation | Major features, setup instructions |
| GETTING-STARTED.md | Quick start guide | Usage workflows, common tasks |
| PRODUCTION-READY.md | Production guide | Security, deployment, backups |
| add-target.sh | Helper script | Changing target creation workflow |

## Quick Command Reference

```bash
# Start poller
export $(cat auspex.conf.example | xargs) && go run cmd/poller/main.go

# Start API
export $(cat auspex.conf.example | xargs) && node webui/server.js

# Database shell
psql -U auspex -d auspexdb

# View targets
curl http://localhost:8080/api/targets

# Add target
./add-target.sh

# Test SNMP
snmpwalk -v 2c -c public 192.168.1.1 system

# Check running processes
ps aux | grep -E "go run.*poller|node.*server"

# View logs (if using systemd)
journalctl -u auspex-poller -f
journalctl -u auspex-api -f

# Database backup
pg_dump -U auspex auspexdb > backup.sql

# Reset database
psql -U auspex -d auspexdb -f db-init-new.sql
```

## Known Limitations & Future Improvements

### Current Limitations

1. **SNMPv3 not implemented** - Only v2c works despite schema allowing v1/v3
2. **No API authentication** - Anyone with network access can modify targets
3. **No alerting system** - Only displays status, doesn't notify on failures
4. **No data retention policy** - poll_results grows indefinitely
5. **Hardcoded config path** - webui/server.js line 2 has `/opt/auspex/config/auspex.conf`
6. **No multi-user support** - Single shared view of all targets
7. **No device grouping** - Large deployments become hard to manage
8. **No historical graphs beyond 1 hour** - Target detail page limited to last hour

### Potential Improvements

1. Implement SNMPv3 support (authentication, encryption)
2. Add API authentication (JWT, API keys)
3. Add alerting (email, Slack, webhook)
4. Automatic data retention/archival
5. Device grouping/tagging
6. Longer historical views (7 days, 30 days)
7. Health checks/SLA tracking
8. Multi-tenancy support
9. Configuration via environment variables (remove hardcoded paths)
10. Docker containerization

## Version History

- **Initial Release:** Basic SNMP polling, web dashboard, PostgreSQL storage
- **Current State:** Fully functional monitoring system, lacks authentication and advanced features

## Support & Resources

**Documentation:**
- README.md - Overview and features
- GETTING-STARTED.md - Installation and usage
- SNMP-DEVICE-SETUP.md - Configuring network devices
- PRODUCTION-READY.md - Deployment and security
- DATABASE-SETUP.md - Database configuration

**External Resources:**
- [gosnmp Documentation](https://github.com/gosnmp/gosnmp)
- [SNMP MIB-2 Reference](https://www.ietf.org/rfc/rfc1213.txt)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Express.js Documentation](https://expressjs.com/)

---

**Last Updated:** 2025-11-17 (initial creation)

**Maintained By:** AI Assistants working with this codebase should update this file when making significant changes to architecture, patterns, or workflows.
