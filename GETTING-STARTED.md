# Auspex - Getting Started Guide

## Quick Start

Auspex is ready to monitor your SNMP-enabled network devices!

### Current Status

✓ PostgreSQL database configured
✓ SNMP poller running (polls every 60 seconds)
✓ Web API server running on port 8080
✓ Sample data removed - ready for real targets

### Access the Dashboard

Open your browser to: **http://localhost:8080**

## Adding Your First Device

### Method 1: Interactive Script (Easiest)

```bash
./add-target.sh
```

Follow the prompts to enter:
- Device name (e.g., "Office Router")
- IP address
- SNMP port (default: 161)
- Community string (default: public)
- SNMP version (default: 2c)

### Method 2: Direct API Call

```bash
curl -X POST http://localhost:8080/api/targets \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Office-Router",
    "host": "192.168.1.1",
    "port": 161,
    "community": "public",
    "snmp_version": "2c",
    "enabled": true
  }'
```

### Method 3: Web Dashboard

1. Open http://localhost:8080
2. Look for "Add Target" button
3. Fill in the form
4. Click "Add"

### Method 4: Bulk CSV Import

1. Edit `targets-template.csv` with your devices:
   ```csv
   name,host,port,community,snmp_version,enabled
   My-Router,192.168.1.1,161,public,2c,true
   My-Switch,192.168.1.2,161,public,2c,true
   ```

2. Use the web dashboard's CSV import feature

### Method 5: Direct SQL

```bash
psql -U auspex -d auspexdb
```

```sql
INSERT INTO targets (name, host, port, community, snmp_version, enabled)
VALUES ('My-Router', '192.168.1.1', 161, 'public', '2c', true);
```

## Testing Device Connectivity

Before adding a device to Auspex, test SNMP connectivity:

### Install SNMP Tools (if needed)

```bash
# macOS
brew install net-snmp

# Ubuntu/Debian
sudo apt-get install snmp

# RHEL/CentOS
sudo yum install net-snmp-utils
```

### Test SNMP Query

```bash
snmpwalk -v 2c -c public 192.168.1.1 system
```

**Expected output:**
```
SNMPv2-MIB::sysDescr.0 = STRING: Cisco IOS Software...
SNMPv2-MIB::sysObjectID.0 = OID: SNMPv2-SMI::enterprises.9.1.1
SNMPv2-MIB::sysUpTime.0 = Timeticks: (12345678) 1 day, 10:17:36.78
SNMPv2-MIB::sysContact.0 = STRING: admin@example.com
SNMPv2-MIB::sysName.0 = STRING: office-router
SNMPv2-MIB::sysLocation.0 = STRING: Server Room
```

**If you see output:** Device is ready for monitoring!

**If timeout or error:** See [SNMP-DEVICE-SETUP.md](SNMP-DEVICE-SETUP.md) for device configuration

## Viewing Results

### Web Dashboard

1. **Main Dashboard:** http://localhost:8080
   - Shows all targets
   - Color-coded status (green=up, red=down, gray=unknown)
   - Last poll time
   - Auto-refreshes every 5 seconds

2. **Target Details:** http://localhost:8080/target.html?id=1
   - Detailed metrics for specific device
   - Latency chart (last hour)
   - Statistics (min/max/avg latency, uptime %)
   - Configuration editor
   - Auto-refreshes every 10 seconds

### API Endpoints

```bash
# List all targets with latest status
curl http://localhost:8080/api/targets

# Get specific target info
curl http://localhost:8080/api/targets/1/info

# Get latest poll result
curl http://localhost:8080/api/targets/1/latest

# Get latency samples (last hour)
curl http://localhost:8080/api/targets/1/latency

# Get statistics (last hour)
curl http://localhost:8080/api/targets/1/stats
```

### Database Queries

```bash
psql -U auspex -d auspexdb
```

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
) pr ON TRUE
ORDER BY t.name;

-- View devices currently down
SELECT t.name, t.host, pr.status, pr.message, pr.polled_at
FROM targets t
JOIN LATERAL (
    SELECT * FROM poll_results
    WHERE target_id = t.id
    ORDER BY polled_at DESC
    LIMIT 1
) pr ON TRUE
WHERE pr.status = 'down';

-- View average latency per device (last 24 hours)
SELECT t.name,
       AVG(pr.latency_ms) as avg_latency,
       MIN(pr.latency_ms) as min_latency,
       MAX(pr.latency_ms) as max_latency
FROM targets t
JOIN poll_results pr ON pr.target_id = t.id
WHERE pr.polled_at > NOW() - INTERVAL '24 hours'
  AND pr.status = 'up'
GROUP BY t.name
ORDER BY avg_latency DESC;

-- View uptime percentage (last 24 hours)
SELECT t.name,
       COUNT(*) FILTER (WHERE pr.status = 'up') * 100.0 / COUNT(*) as uptime_pct
FROM targets t
JOIN poll_results pr ON pr.target_id = t.id
WHERE pr.polled_at > NOW() - INTERVAL '24 hours'
GROUP BY t.name
ORDER BY uptime_pct ASC;
```

## Managing Services

### Check Status

```bash
# Check if poller is running
ps aux | grep "go run.*poller"

# Check if API server is running
ps aux | grep "node.*server.js"

# Check PostgreSQL
pg_isready

# View poller output (in the terminal where it's running)
# Or check the background job output
```

### Stop Services

```bash
# Find process IDs
ps aux | grep -E "go run.*poller|node.*server"

# Kill processes
kill <PID>

# Or use Ctrl+C in the terminal where they're running
```

### Restart Services

```bash
# In separate terminals:

# Terminal 1: Poller
cd /Users/mcclainje/Documents/Code/auspex
export $(cat config/auspex.conf | xargs)
go run cmd/poller/main.go

# Terminal 2: API Server
cd /Users/mcclainje/Documents/Code/auspex
export $(cat config/auspex.conf | xargs)
node webui/server.js

# Terminal 3: Access dashboard
open http://localhost:8080
```

## Configuration

Edit `/Users/mcclainje/Documents/Code/auspex/config/auspex.conf`:

```bash
# Database settings
AUSPEX_DB_HOST=localhost
AUSPEX_DB_PORT=5432
AUSPEX_DB_NAME=auspexdb
AUSPEX_DB_USER=auspex
AUSPEX_DB_PASSWORD=yourpassword  # CHANGE THIS!

# API server
AUSPEX_API_PORT=8080

# Poller settings
AUSPEX_POLL_INTERVAL_SECONDS=60      # How often to poll
AUSPEX_MAX_CONCURRENT_POLLS=10       # Concurrent device polls
```

**After changing config:** Restart the poller and API server

## Common Operations

### Update Target Configuration

**Via Web UI:**
1. Go to http://localhost:8080/target.html?id=1
2. Click "Edit Configuration"
3. Update fields
4. Click "Save"

**Via API:**
```bash
curl -X PUT http://localhost:8080/api/targets/1 \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Updated-Name",
    "host": "192.168.1.1",
    "port": 161,
    "community": "newcommunity",
    "snmp_version": "2c",
    "enabled": true
  }'
```

### Disable Target (Stop Polling)

```bash
curl -X PUT http://localhost:8080/api/targets/1 \
  -H "Content-Type: application/json" \
  -d '{"enabled": false, "name": "Old-Router", "host": "192.168.1.1", "port": 161, "community": "public", "snmp_version": "2c"}'
```

Or use the soft-delete endpoint:
```bash
curl -X DELETE http://localhost:8080/api/targets/1
```

### Delete Target Permanently

```bash
curl -X DELETE http://localhost:8080/api/targets/1/delete
```

**Warning:** This deletes all poll history for this target!

### Clear All Poll Results

```bash
psql -U auspex -d auspexdb -c "DELETE FROM poll_results;"
```

### Export Data

```bash
# Export targets to CSV
psql -U auspex -d auspexdb -c "COPY targets TO STDOUT WITH CSV HEADER" > targets-backup.csv

# Export poll results (last 7 days)
psql -U auspex -d auspexdb -c "COPY (SELECT * FROM poll_results WHERE polled_at > NOW() - INTERVAL '7 days') TO STDOUT WITH CSV HEADER" > polls-7days.csv
```

## Troubleshooting

### Device shows as "down" but it's online

**Check:**
1. Can you ping the device? `ping 192.168.1.1`
2. Is SNMP enabled on the device?
3. Test SNMP manually: `snmpwalk -v 2c -c public 192.168.1.1 system`
4. Is the community string correct?
5. Are there firewall rules blocking SNMP (UDP 161)?
6. Is the device on the same network/VLAN?

**Fix:**
- Enable SNMP on device (see [SNMP-DEVICE-SETUP.md](SNMP-DEVICE-SETUP.md))
- Update community string in Auspex
- Add firewall rules to allow UDP 161 from monitoring server

### Poller not running

```bash
# Check if process exists
ps aux | grep "go run.*poller"

# Check for errors in terminal output

# Verify database connection
psql -U auspex -d auspexdb -c "SELECT 1"

# Restart poller
cd /Users/mcclainje/Documents/Code/auspex
export $(cat config/auspex.conf | xargs)
go run cmd/poller/main.go
```

### API server not responding

```bash
# Check if running
ps aux | grep "node.*server.js"

# Check port is listening
lsof -i :8080

# Check for errors in terminal output

# Restart API server
cd /Users/mcclainje/Documents/Code/auspex
export $(cat config/auspex.conf | xargs)
node webui/server.js
```

### Dashboard shows old data

1. Check poller is running and polling
2. Verify latest poll time in database:
   ```sql
   SELECT MAX(polled_at) FROM poll_results;
   ```
3. Check browser console for API errors
4. Hard refresh browser (Cmd+Shift+R or Ctrl+Shift+R)

### High memory/CPU usage

**Poller:**
- Reduce `AUSPEX_MAX_CONCURRENT_POLLS`
- Increase `AUSPEX_POLL_INTERVAL_SECONDS`
- Check for network timeout issues causing retries

**Database:**
- Delete old poll results
- Run `VACUUM ANALYZE` on database
- Check for missing indexes

## Next Steps

1. **Add your devices** using one of the methods above
2. **Configure SNMP** on devices (see [SNMP-DEVICE-SETUP.md](SNMP-DEVICE-SETUP.md))
3. **Secure your installation** (see [PRODUCTION-READY.md](PRODUCTION-READY.md))
4. **Set up backups** for the database
5. **Monitor the monitoring** - ensure Auspex itself is running

## Documentation Index

- **[DATABASE-SETUP.md](DATABASE-SETUP.md)** - Database configuration and troubleshooting
- **[SNMP-DEVICE-SETUP.md](SNMP-DEVICE-SETUP.md)** - Configure SNMP on network devices
- **[PRODUCTION-READY.md](PRODUCTION-READY.md)** - Security hardening and production deployment
- **targets-template.csv** - CSV template for bulk import
- **add-target.sh** - Interactive script to add devices

## Support

**Check system status:**
```bash
# All services
ps aux | grep -E "postgres|go run.*poller|node.*server"

# Database connection
psql -U auspex -d auspexdb -c "SELECT COUNT(*) FROM targets;"

# Latest polls
psql -U auspex -d auspexdb -c "SELECT COUNT(*) FROM poll_results WHERE polled_at > NOW() - INTERVAL '5 minutes';"
```

**View logs:**
- Poller: Check terminal where `go run cmd/poller/main.go` is running
- API: Check terminal where `node webui/server.js` is running
- Database: `tail -f /opt/homebrew/var/log/postgresql@14.log`

**Reset everything:**
```bash
# Stop services
# Kill poller and API processes

# Drop and recreate database
psql -U postgres -c "DROP DATABASE auspexdb;"
psql -U postgres -c "CREATE DATABASE auspexdb OWNER auspex;"
psql -U auspex -d auspexdb -f db-init-new.sql

# Restart services
```
