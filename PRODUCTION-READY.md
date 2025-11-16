# Auspex Production Deployment Guide

## Security Hardening Checklist

Before deploying Auspex in production, complete these security steps:

### 1. Change Database Password ⚠️

**CRITICAL:** The default password `yourpassword` is insecure!

**Update PostgreSQL:**
```bash
psql -U postgres
ALTER USER auspex WITH PASSWORD 'YourSecurePassword123!';
\q
```

**Update configuration file:**
```bash
# Edit config/auspex.conf
AUSPEX_DB_PASSWORD=YourSecurePassword123!
```

**Restart services:**
- Stop the poller (Ctrl+C or kill process)
- Stop the API server (Ctrl+C or kill process)
- Restart both with new password from config

### 2. Change SNMP Community Strings

**Never use default community strings in production!**

❌ Default: `public`
✓ Secure: `M0n1t0r!ng_2024_Str1ng`

**Requirements:**
- At least 16 characters
- Mix of letters, numbers, and symbols
- Different from database password
- Unique per environment (dev/staging/prod)

### 3. File Permissions

**Protect configuration file:**
```bash
chmod 600 /Users/mcclainje/Documents/Code/auspex/config/auspex.conf
chown mcclainje:staff /Users/mcclainje/Documents/Code/auspex/config/auspex.conf
```

**Verify:**
```bash
ls -l config/auspex.conf
# Should show: -rw------- 1 mcclainje staff
```

### 4. Network Security

**PostgreSQL:**
- Configure `pg_hba.conf` to only accept connections from localhost
- If remote access needed, use SSL/TLS
- Block port 5432 at firewall (external access)

**API Server:**
- Consider adding authentication middleware
- Use reverse proxy (nginx) with HTTPS
- Implement rate limiting
- Add CORS restrictions

**SNMP:**
- Use firewall rules to restrict SNMP access
- Only allow monitoring server IP to query devices
- Use read-only community strings only

### 5. Database Backups

**Create backup script:**
```bash
#!/bin/bash
# backup-auspex-db.sh

BACKUP_DIR="/Users/mcclainje/backups/auspex"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/auspexdb_$DATE.sql"

mkdir -p "$BACKUP_DIR"

PGPASSWORD='YourSecurePassword123!' pg_dump \
  -h localhost \
  -U auspex \
  -d auspexdb \
  -f "$BACKUP_FILE"

# Compress
gzip "$BACKUP_FILE"

# Delete backups older than 30 days
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +30 -delete

echo "Backup completed: ${BACKUP_FILE}.gz"
```

**Schedule with cron:**
```bash
# Daily backup at 2 AM
0 2 * * * /Users/mcclainje/Documents/Code/auspex/backup-auspex-db.sh
```

### 6. Log Management

**Configure log rotation:**
```bash
# Create /etc/logrotate.d/auspex
/Users/mcclainje/Documents/Code/auspex/logs/*.log {
    daily
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 mcclainje staff
}
```

**Redirect poller and API logs:**
```bash
# Run with logging
AUSPEX_DB_PASSWORD=YourSecurePassword123! go run cmd/poller/main.go \
  2>&1 | tee -a logs/poller.log &

AUSPEX_DB_PASSWORD=YourSecurePassword123! node webui/server.js \
  2>&1 | tee -a logs/api.log &
```

### 7. Database Maintenance

**Auto-vacuum configuration:**
```sql
-- Connect to database
psql -U auspex -d auspexdb

-- Enable auto-vacuum (usually on by default)
ALTER TABLE poll_results SET (autovacuum_enabled = true);
ALTER TABLE targets SET (autovacuum_enabled = true);
```

**Purge old poll results:**
```sql
-- Delete polls older than 90 days
DELETE FROM poll_results WHERE polled_at < NOW() - INTERVAL '90 days';
```

**Create cleanup script:**
```bash
#!/bin/bash
# cleanup-old-polls.sh

PGPASSWORD='YourSecurePassword123!' psql \
  -h localhost \
  -U auspex \
  -d auspexdb \
  -c "DELETE FROM poll_results WHERE polled_at < NOW() - INTERVAL '90 days';"

echo "Deleted poll results older than 90 days"
```

**Schedule weekly:**
```bash
# Every Sunday at 3 AM
0 3 * * 0 /Users/mcclainje/Documents/Code/auspex/cleanup-old-polls.sh
```

## Running as System Services

### macOS LaunchDaemon

**Poller service (`~/Library/LaunchAgents/com.auspex.poller.plist`):**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.auspex.poller</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/go</string>
        <string>run</string>
        <string>/Users/mcclainje/Documents/Code/auspex/cmd/poller/main.go</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>AUSPEX_DB_HOST</key>
        <string>localhost</string>
        <key>AUSPEX_DB_PORT</key>
        <string>5432</string>
        <key>AUSPEX_DB_NAME</key>
        <string>auspexdb</string>
        <key>AUSPEX_DB_USER</key>
        <string>auspex</string>
        <key>AUSPEX_DB_PASSWORD</key>
        <string>YourSecurePassword123!</string>
        <key>AUSPEX_POLL_INTERVAL_SECONDS</key>
        <string>60</string>
        <key>AUSPEX_MAX_CONCURRENT_POLLS</key>
        <string>10</string>
    </dict>
    <key>StandardOutPath</key>
    <string>/Users/mcclainje/Documents/Code/auspex/logs/poller.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/mcclainje/Documents/Code/auspex/logs/poller.err</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
```

**API service (`~/Library/LaunchAgents/com.auspex.api.plist`):**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.auspex.api</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/node</string>
        <string>/Users/mcclainje/Documents/Code/auspex/webui/server.js</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>AUSPEX_DB_HOST</key>
        <string>localhost</string>
        <key>AUSPEX_DB_PORT</key>
        <string>5432</string>
        <key>AUSPEX_DB_NAME</key>
        <string>auspexdb</string>
        <key>AUSPEX_DB_USER</key>
        <string>auspex</string>
        <key>AUSPEX_DB_PASSWORD</key>
        <string>YourSecurePassword123!</string>
        <key>AUSPEX_API_PORT</key>
        <string>8080</string>
    </dict>
    <key>StandardOutPath</key>
    <string>/Users/mcclainje/Documents/Code/auspex/logs/api.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/mcclainje/Documents/Code/auspex/logs/api.err</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
```

**Load services:**
```bash
launchctl load ~/Library/LaunchAgents/com.auspex.poller.plist
launchctl load ~/Library/LaunchAgents/com.auspex.api.plist
```

**Manage services:**
```bash
# Check status
launchctl list | grep auspex

# Stop service
launchctl unload ~/Library/LaunchAgents/com.auspex.poller.plist

# Start service
launchctl load ~/Library/LaunchAgents/com.auspex.poller.plist
```

### Linux Systemd

**Poller service (`/etc/systemd/system/auspex-poller.service`):**
```ini
[Unit]
Description=Auspex SNMP Poller
After=network.target postgresql.service

[Service]
Type=simple
User=auspex
WorkingDirectory=/opt/auspex
Environment="AUSPEX_DB_HOST=localhost"
Environment="AUSPEX_DB_PORT=5432"
Environment="AUSPEX_DB_NAME=auspexdb"
Environment="AUSPEX_DB_USER=auspex"
Environment="AUSPEX_DB_PASSWORD=YourSecurePassword123!"
Environment="AUSPEX_POLL_INTERVAL_SECONDS=60"
Environment="AUSPEX_MAX_CONCURRENT_POLLS=10"
ExecStart=/usr/local/go/bin/go run /opt/auspex/cmd/poller/main.go
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**API service (`/etc/systemd/system/auspex-api.service`):**
```ini
[Unit]
Description=Auspex Web API
After=network.target postgresql.service

[Service]
Type=simple
User=auspex
WorkingDirectory=/opt/auspex/webui
Environment="AUSPEX_DB_HOST=localhost"
Environment="AUSPEX_DB_PORT=5432"
Environment="AUSPEX_DB_NAME=auspexdb"
Environment="AUSPEX_DB_USER=auspex"
Environment="AUSPEX_DB_PASSWORD=YourSecurePassword123!"
Environment="AUSPEX_API_PORT=8080"
ExecStart=/usr/bin/node /opt/auspex/webui/server.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**Enable and start:**
```bash
sudo systemctl daemon-reload
sudo systemctl enable auspex-poller auspex-api
sudo systemctl start auspex-poller auspex-api
sudo systemctl status auspex-poller auspex-api
```

## Monitoring Recommendations

### Poll Interval Tuning

**Default:** 60 seconds

**Adjust based on needs:**
- **Critical infrastructure:** 30 seconds
- **Normal monitoring:** 60 seconds (recommended)
- **Low-priority devices:** 300 seconds (5 minutes)
- **Bandwidth-constrained:** 600 seconds (10 minutes)

**Update config:**
```bash
AUSPEX_POLL_INTERVAL_SECONDS=30
```

### Concurrent Polling

**Default:** 10 concurrent polls

**Guidelines:**
- Small network (<50 devices): 10
- Medium network (50-200 devices): 20-50
- Large network (200+ devices): 50-100

**Update config:**
```bash
AUSPEX_MAX_CONCURRENT_POLLS=50
```

### Database Performance

**For large deployments (1000+ polls/minute):**

```sql
-- Increase shared buffers
-- Edit postgresql.conf
shared_buffers = 256MB
effective_cache_size = 1GB

-- Restart PostgreSQL
```

**Add indexes for custom queries:**
```sql
-- Index for querying by host
CREATE INDEX idx_targets_host_enabled ON targets(host) WHERE enabled = true;

-- Index for time-range queries
CREATE INDEX idx_poll_results_time_range ON poll_results(polled_at) WHERE polled_at > NOW() - INTERVAL '24 hours';
```

## Alerting (Future Enhancement)

Auspex currently stores poll results but doesn't send alerts. Consider adding:

1. **Email alerts** when devices go down
2. **Slack/Discord webhooks** for notifications
3. **PagerDuty integration** for critical infrastructure
4. **Threshold alerts** for latency spikes

**Example alert query:**
```sql
-- Devices down for >5 minutes
SELECT t.name, t.host, pr.status, pr.polled_at
FROM targets t
JOIN LATERAL (
    SELECT * FROM poll_results
    WHERE target_id = t.id
    ORDER BY polled_at DESC
    LIMIT 1
) pr ON TRUE
WHERE pr.status = 'down'
  AND pr.polled_at < NOW() - INTERVAL '5 minutes';
```

## High Availability Setup

For mission-critical monitoring:

1. **Redundant poller instances** (active/passive)
2. **PostgreSQL replication** (streaming replication)
3. **Load-balanced API servers** (nginx + multiple nodes)
4. **Backup monitoring server** (different location/network)

## Performance Benchmarks

**Expected performance (single instance):**
- Targets: 1,000+ devices
- Poll rate: 16 polls/second @ 60s interval
- Database growth: ~100 MB/day (60s interval, 1000 devices)
- API response time: <100ms per request
- Memory usage: 50-100 MB (poller), 50 MB (API)

## Troubleshooting

**High latency / slow polls:**
- Increase `AUSPEX_MAX_CONCURRENT_POLLS`
- Reduce `AUSPEX_POLL_INTERVAL_SECONDS`
- Check network connectivity to devices
- Verify device SNMP response times

**Database growing too large:**
- Reduce poll retention (delete older than 30/60/90 days)
- Increase poll interval
- Use table partitioning for poll_results

**Poller crashing:**
- Check Go version compatibility
- Verify database connection
- Review error logs
- Ensure sufficient memory

**API returning stale data:**
- Check database connection
- Verify poller is running: `ps aux | grep poller`
- Check latest poll times: `SELECT MAX(polled_at) FROM poll_results;`

## Production Checklist

- [ ] Change database password from default
- [ ] Change SNMP community strings
- [ ] Set file permissions (600 on config files)
- [ ] Configure database backups
- [ ] Set up log rotation
- [ ] Configure old data cleanup
- [ ] Set up systemd/launchd services
- [ ] Configure firewall rules
- [ ] Test failover procedures
- [ ] Document device credentials securely
- [ ] Set up monitoring of monitoring (meta-monitoring)
- [ ] Configure off-site backups
- [ ] Review and test disaster recovery plan

## Support

For issues or questions:
- Check logs: `logs/poller.log` and `logs/api.log`
- Verify services: `ps aux | grep -E 'go run|node.*server.js'`
- Check database: `psql -U auspex -d auspexdb`
- Test SNMP: `snmpwalk -v 2c -c COMMUNITY DEVICE_IP system`
