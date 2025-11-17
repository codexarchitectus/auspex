# Auspex SNMP Network Monitor

A lightweight, real-time SNMP monitoring system for network devices with a web dashboard.

## Features

- ✅ **Real-time SNMP polling** - Continuously monitors device health via SNMPv2c
- ✅ **Web dashboard** - Live status updates with color-coded indicators
- ✅ **Historical data** - Latency tracking and uptime statistics
- ✅ **REST API** - Full programmatic access to targets and poll results
- ✅ **PostgreSQL backend** - Reliable data storage with performance indexes
- ✅ **Concurrent polling** - Efficiently monitors multiple devices simultaneously
- ✅ **Auto-refresh** - Dashboard updates every 5 seconds without page reload

## Installation

**New to Auspex?** Start with the comprehensive installation guide:

📦 **[INSTALLATION.md](INSTALLATION.md)** - Complete step-by-step installation from scratch

**Quick Install (Ubuntu/Debian):**
```bash
# Install dependencies
sudo apt update && sudo apt install -y postgresql golang nodejs npm

# Clone repository
git clone https://github.com/codexarchitectus/auspex.git
cd auspex

# Setup database
./setup-database.sh

# Install dependencies
npm install --prefix webui
go mod download

# Start services (in separate terminals)
export $(cat config/auspex.conf | xargs)
go run cmd/poller/main.go        # Terminal 1
node webui/server.js             # Terminal 2
```

**Access Dashboard:** http://localhost:8080

---

## Quick Start

### Add Your First Device

**Interactive script:**
```bash
./add-target.sh
```

**Quick API call:**
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

**Via web UI:**
1. Go to http://localhost:8080
2. Click "Add Target" (or use CSV bulk import)
3. Enter device details
4. Start monitoring!

## Architecture

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

## Components

| Component | Technology | Purpose |
|-----------|-----------|---------|
| **Poller** | Go + gosnmp | Queries SNMP devices, writes results to DB |
| **API Server** | Node.js + Express | REST API and static file serving |
| **Database** | PostgreSQL | Stores targets and poll history |
| **Web UI** | HTML + JavaScript + Chart.js | Real-time dashboard with graphs |

## Documentation

### Getting Started

📦 **[INSTALLATION.md](INSTALLATION.md)** - Complete installation guide from scratch

📘 **[GETTING-STARTED.md](GETTING-STARTED.md)** - Adding targets, viewing results, managing services

📗 **[SNMP-DEVICE-SETUP.md](SNMP-DEVICE-SETUP.md)** - Configure SNMP on routers, switches, servers, firewalls

### Operations & Deployment

📕 **[PRODUCTION-READY.md](PRODUCTION-READY.md)** - Security hardening, backups, systemd services

📙 **[DATABASE-SETUP.md](DATABASE-SETUP.md)** - Database configuration and troubleshooting

### Development & Planning

🗺️ **[ROADMAP.md](ROADMAP.md)** - Project roadmap and planned features

📖 **[CODEBASE-SUMMARY.md](CODEBASE-SUMMARY.md)** - Architecture and code reference for developers

📋 **Feature Proposals:**
- [SNMP MIB Database](docs/SNMP-MIB-DATABASE-PROPOSAL.md) - Device-specific OID monitoring
- [ICMP Ping Polling](docs/ICMP-POLLING-PROPOSAL.md) - Alternative polling via ping
- [Splunk HEC Integration](SPLUNK-HEC-IMPLEMENTATION-PLAN.md) - Export to Splunk

### Helper Scripts

- **add-target.sh** - Interactive script to add devices
- **targets-template.csv** - CSV template for bulk import
- **setup-database.sh** - Automated database initialization

## System Requirements

- **PostgreSQL** 12 or higher
- **Go** 1.18 or higher
- **Node.js** 16 or higher
- **Network access** to SNMP devices (UDP port 161)

**Supported Platforms:**
- Linux (Ubuntu 20.04+, Debian 11+, CentOS/RHEL 8+)
- macOS 11+
- Windows 10+ (via WSL2)

## Supported Devices

Auspex can monitor any device supporting SNMPv2c:

- **Network:** Routers, switches, firewalls, access points, load balancers
- **Servers:** Linux, Windows, VMware ESXi, Proxmox
- **Storage:** NAS devices (Synology, QNAP, TrueNAS)
- **Other:** UPS systems, environmental monitors, printers

See [SNMP-DEVICE-SETUP.md](SNMP-DEVICE-SETUP.md) for device-specific configuration.

## Configuration

Edit `config/auspex.conf`:

```bash
# Database
AUSPEX_DB_HOST=localhost
AUSPEX_DB_PORT=5432
AUSPEX_DB_NAME=auspexdb
AUSPEX_DB_USER=auspex
AUSPEX_DB_PASSWORD=yourpassword  # ⚠️  CHANGE THIS!

# API Server
AUSPEX_API_PORT=8080

# Poller Settings
AUSPEX_POLL_INTERVAL_SECONDS=60      # Poll frequency
AUSPEX_MAX_CONCURRENT_POLLS=10       # Concurrent device polls
```

## API Endpoints

### Targets

- `GET /api/targets` - List all targets with latest status
- `POST /api/targets` - Add new target
- `PUT /api/targets/:id` - Update target
- `DELETE /api/targets/:id` - Soft-delete (disable) target
- `DELETE /api/targets/:id/delete` - Hard-delete target

### Target Details

- `GET /api/targets/:id/info` - Target configuration
- `GET /api/targets/:id/latest` - Most recent poll result
- `GET /api/targets/:id/latency` - Latency samples (last hour)
- `GET /api/targets/:id/stats` - Statistics (min/max/avg, uptime %)

### Web UI

- `GET /` or `/index.html` - Main dashboard
- `GET /target.html?id=1` - Target detail page

## Database Schema

### targets

| Column | Type | Description |
|--------|------|-------------|
| id | serial | Primary key |
| name | varchar(255) | Device display name |
| host | varchar(255) | IP address or hostname |
| port | integer | SNMP port (default: 161) |
| community | varchar(100) | SNMP community string |
| snmp_version | varchar(20) | SNMP version (1, 2c, or 3) |
| enabled | boolean | Whether to poll this device |
| created_at | timestamp | Record creation time |
| updated_at | timestamp | Last update time |

### poll_results

| Column | Type | Description |
|--------|------|-------------|
| id | bigserial | Primary key |
| target_id | integer | Foreign key to targets |
| status | varchar(20) | 'up', 'down', or 'unknown' |
| latency_ms | integer | Response time in milliseconds |
| message | text | SNMP response or error message |
| polled_at | timestamp | When poll occurred |

## Common Tasks

### View Running Services

```bash
# Check all Auspex processes
ps aux | grep -E "go run.*poller|node.*server.js"

# Check database
pg_isready
```

### View Latest Polls

```bash
psql -U auspex -d auspexdb -c "
  SELECT t.name, pr.status, pr.latency_ms, pr.polled_at
  FROM targets t
  JOIN LATERAL (
    SELECT * FROM poll_results
    WHERE target_id = t.id
    ORDER BY polled_at DESC
    LIMIT 1
  ) pr ON TRUE;"
```

### Stop/Restart Services

```bash
# Stop (Ctrl+C in running terminals, or kill PIDs)
kill <poller_pid> <api_pid>

# Start poller
cd /path/to/auspex
export $(cat config/auspex.conf | xargs)
go run cmd/poller/main.go &

# Start API
export $(cat config/auspex.conf | xargs)
node webui/server.js &
```

For production deployments with systemd, see [PRODUCTION-READY.md](PRODUCTION-READY.md).

## Performance

**Expected capacity (single instance):**
- Targets: 1,000+ devices
- Poll rate: 16 devices/second @ 60s interval
- Database growth: ~100 MB/day (60s interval, 1000 devices)
- API latency: <100ms per request
- Memory: 50-100 MB (poller), 50 MB (API)

## Security Notes

⚠️ **Before production use:**

1. Change database password (default is `yourpassword`)
2. Change SNMP community strings (default is `public`)
3. Restrict PostgreSQL access to localhost
4. Set file permissions: `chmod 600 config/auspex.conf`
5. Configure firewall rules (allow UDP 161 from monitoring server only)

See [PRODUCTION-READY.md](PRODUCTION-READY.md) for complete security checklist.

## Troubleshooting

### Device shows "down" but it's online

1. Test SNMP manually: `snmpwalk -v 2c -c public DEVICE_IP system`
2. Verify community string matches
3. Check firewall rules (allow UDP 161)
4. Confirm SNMP is enabled on device

See [SNMP-DEVICE-SETUP.md](SNMP-DEVICE-SETUP.md) for device configuration help.

### Dashboard not updating

1. Verify poller is running: `ps aux | grep "go run.*poller"`
2. Check database has recent polls: `SELECT MAX(polled_at) FROM poll_results;`
3. Hard refresh browser (Cmd+Shift+R)
4. Check browser console for errors

## Development

### File Structure

```
auspex/
├── cmd/poller/main.go          # SNMP polling daemon (Go)
├── webui/
│   ├── server.js               # Express API server (Node.js)
│   ├── index.html              # Main dashboard
│   └── target.html             # Target detail page
├── config/auspex.conf          # Configuration file
├── db-init-new.sql             # Database schema
├── add-target.sh               # Helper script
├── targets-template.csv        # CSV import template
└── *.md                        # Documentation
```

### Tech Stack

- **Backend:** Go 1.25 (poller), Node.js 25 (API)
- **Database:** PostgreSQL 14
- **Frontend:** Vanilla JavaScript, Chart.js
- **Protocol:** SNMPv2c (gosnmp library)

## Roadmap & Future Features

Auspex is actively developed with several exciting features planned:

### 🚀 Planned Features (High Priority)

- **SNMP MIB Database** - Device-specific OID groups and templates
- **ICMP Ping Polling** - Alternative polling via ping (no SNMP required)
- **Splunk HEC Integration** - Export metrics to Splunk

### 🔮 Under Consideration

- Alerting & Notifications (email, SMS, webhooks)
- User Authentication & Authorization
- SNMPv3 Support (encrypted polling)
- Advanced Dashboards & Reporting
- Mobile Application
- Multi-Tenancy

See **[ROADMAP.md](ROADMAP.md)** for complete roadmap and detailed feature proposals.

---

## Contributing

Contributions are welcome! Whether it's bug reports, feature requests, or code contributions.

**How to Contribute:**
1. Check the [ROADMAP.md](ROADMAP.md) for planned features
2. Open an issue to discuss your idea
3. Fork the repository
4. Create a feature branch
5. Submit a pull request

---

## License

MIT License - see LICENSE file for details

---

## Support

**📚 Documentation:**
- [INSTALLATION.md](INSTALLATION.md) - Installation guide
- [GETTING-STARTED.md](GETTING-STARTED.md) - Usage guide
- [SNMP-DEVICE-SETUP.md](SNMP-DEVICE-SETUP.md) - Device configuration
- [PRODUCTION-READY.md](PRODUCTION-READY.md) - Production deployment
- [DATABASE-SETUP.md](DATABASE-SETUP.md) - Database help
- [CODEBASE-SUMMARY.md](CODEBASE-SUMMARY.md) - Developer reference

**Check status:**
```bash
# System health
ps aux | grep -E "postgres|go run|node.*server"
psql -U auspex -d auspexdb -c "SELECT COUNT(*) FROM targets WHERE enabled = true;"
curl -s http://localhost:8080/api/targets | grep -c '"id"'
```

**🐛 Issues & Bug Reports:**
- GitHub Issues: https://github.com/codexarchitectus/auspex/issues

**💬 Community:**
- GitHub Discussions: https://github.com/codexarchitectus/auspex/discussions

---

## Getting Started Checklist

Ready to monitor your network? Follow these steps:

1. ✅ **Install Auspex** - Follow [INSTALLATION.md](INSTALLATION.md)
2. ✅ **Configure SNMP** - See [SNMP-DEVICE-SETUP.md](SNMP-DEVICE-SETUP.md) for your devices
3. ✅ **Add Targets** - Use `./add-target.sh` or the web UI
4. ✅ **View Dashboard** - Open http://localhost:8080
5. ✅ **Secure Installation** - Follow [PRODUCTION-READY.md](PRODUCTION-READY.md)

**Happy monitoring! 🎯**
