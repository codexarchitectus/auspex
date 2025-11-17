# Auspex Database Configuration Guide

## Prerequisites

1. **PostgreSQL** installed and running:
   ```bash
   # macOS
   brew install postgresql
   brew services start postgresql

   # Ubuntu/Debian
   sudo apt-get install postgresql postgresql-contrib
   sudo systemctl start postgresql
   ```

2. **Verify PostgreSQL is running**:
   ```bash
   pg_isready
   ```

## Quick Setup (Automated)

Run the automated setup script:

```bash
./setup-database.sh
```

This script will:
- Create the database user (`auspex`)
- Create the database (`auspexdb`)
- Initialize tables (`targets`, `poll_results`)
- Add sample data for testing

**Note**: You may need to authenticate as the `postgres` superuser. Default password is often empty or `postgres`.

## Manual Setup (Alternative)

If you prefer manual setup or the script doesn't work:

### 1. Create Database and User

```bash
# Connect as postgres superuser
psql -U postgres

# Run these SQL commands:
CREATE USER auspex WITH PASSWORD 'yourpassword';
CREATE DATABASE auspexdb OWNER auspex;
\q
```

### 2. Initialize Schema

```bash
# Run the initialization script
psql -U auspex -d auspexdb -f db-init-new.sql
```

### 3. Verify Setup

```bash
# Connect to the database
psql -U auspex -d auspexdb

# Check tables
\dt

# View sample data
SELECT * FROM targets;
SELECT COUNT(*) FROM poll_results;

\q
```

### 4. (Optional) Initialize Alerting Schema

If you want to use the alerting engine (PagerDuty, Slack, Email notifications), initialize the alerting tables:

```bash
# Run the alerting schema script
psql -U auspex -d auspexdb -f db-alerting-schema.sql
```

This creates additional tables:
- `alert_channels` - Notification channel configurations
- `alert_rules` - Per-target alert rules
- `alert_history` - Alert firing history
- `alert_deliveries` - Notification delivery logs
- `alert_suppressions` - Maintenance window schedules
- `alert_state` - De-duplication state tracking

**Verify alerting tables:**
```bash
psql -U auspex -d auspexdb -c "\dt alert*"
```

**See [ALERTING-SETUP.md](ALERTING-SETUP.md) for complete alerting configuration guide.**

## Configuration File

Edit `/Users/mcclainje/Documents/Code/auspex/config/auspex.conf`:

```bash
AUSPEX_DB_HOST=localhost
AUSPEX_DB_PORT=5432
AUSPEX_DB_NAME=auspexdb
AUSPEX_DB_USER=auspex
AUSPEX_DB_PASSWORD=yourpassword
AUSPEX_API_PORT=8080
AUSPEX_POLL_INTERVAL_SECONDS=60
AUSPEX_MAX_CONCURRENT_POLLS=10
```

**Important**: Update `AUSPEX_DB_PASSWORD` to match your chosen password!

## Database Schema

### Tables

**targets** - SNMP devices to monitor:
- `id` - Auto-increment primary key
- `name` - Display name for the target
- `host` - IP address or hostname
- `port` - SNMP port (default: 161)
- `community` - SNMP community string (default: 'public')
- `snmp_version` - SNMP version ('1', '2c', or '3')
- `enabled` - Whether to poll this target
- `created_at`, `updated_at` - Timestamps

**poll_results** - Historical polling data:
- `id` - Auto-increment primary key
- `target_id` - Foreign key to targets table
- `status` - 'up', 'down', or 'unknown'
- `latency_ms` - Response time in milliseconds
- `message` - SNMP response details or error message
- `polled_at` - When the poll occurred

### Indexes

Optimized for common queries:
- Fast lookup of enabled targets
- Latest poll per target (critical for dashboard)
- Time-based queries for statistics
- Status filtering

## Sample Data

The initialization script includes 4 sample targets:
- **Router-Core-01** (192.168.1.1) - Enabled
- **Switch-Access-02** (192.168.1.10) - Enabled
- **Firewall-Edge** (192.168.1.254) - Enabled
- **Demo-Disabled** (192.168.1.99) - Disabled

And some example poll results for demonstration.

**To remove sample data** after testing:
```sql
DELETE FROM poll_results;
DELETE FROM targets;
```

## Troubleshooting

### Connection Refused

```
Error: Cannot connect to PostgreSQL
```

**Solution**: Start PostgreSQL service
```bash
# macOS
brew services start postgresql

# Linux
sudo systemctl start postgresql
```

### Authentication Failed

```
FATAL: password authentication failed
```

**Solutions**:
1. Update password in `config/auspex.conf`
2. Reset PostgreSQL password:
   ```bash
   psql -U postgres
   ALTER USER auspex WITH PASSWORD 'newpassword';
   ```

### Permission Denied on db-init.sql

If `/Users/mcclainje/Documents/Code/auspex/api/db-init.sql` is owned by root:

```bash
# Option 1: Fix permissions
sudo chown mcclainje:staff api/db-init.sql

# Option 2: Use the copy instead
# The script already uses db-init-new.sql which has correct permissions
```

### PostgreSQL Not Installed

**macOS**:
```bash
brew install postgresql@14
brew services start postgresql@14
```

**Ubuntu/Debian**:
```bash
sudo apt-get update
sudo apt-get install postgresql postgresql-contrib
sudo systemctl enable postgresql
sudo systemctl start postgresql
```

## Next Steps

After database setup:

1. **Test database connection**:
   ```bash
   psql -U auspex -d auspexdb -c "SELECT COUNT(*) FROM targets;"
   ```

2. **Start the SNMP poller**:
   ```bash
   cd /Users/mcclainje/Documents/Code/auspex
   export $(cat config/auspex.conf | xargs)
   go run cmd/poller/main.go
   ```

3. **Start the API server**:
   ```bash
   cd /Users/mcclainje/Documents/Code/auspex/webui
   node server.js
   ```

4. **Access the dashboard**:
   - Open browser to http://localhost:8080
   - View targets and polling status

## Database Maintenance

### Viewing Live Polls

```sql
-- Latest poll for each target
SELECT t.name, t.host, pr.status, pr.latency_ms, pr.polled_at
FROM targets t
LEFT JOIN LATERAL (
    SELECT * FROM poll_results
    WHERE target_id = t.id
    ORDER BY polled_at DESC
    LIMIT 1
) pr ON TRUE
ORDER BY t.id;
```

### Cleaning Old Data

```sql
-- Delete polls older than 30 days
DELETE FROM poll_results WHERE polled_at < NOW() - INTERVAL '30 days';
```

### Adding New Targets

```sql
INSERT INTO targets (name, host, port, community, snmp_version, enabled)
VALUES ('My-Router', '10.0.0.1', 161, 'public', '2c', true);
```

## Security Notes

1. **Change default password**: Update `AUSPEX_DB_PASSWORD` in `config/auspex.conf`
2. **Restrict network access**: Configure PostgreSQL `pg_hba.conf` for trusted hosts only
3. **Use strong community strings**: Replace 'public' with custom SNMP community strings
4. **File permissions**: Protect `config/auspex.conf` from unauthorized access:
   ```bash
   chmod 600 config/auspex.conf
   ```
