# Auspex Alerting Engine Setup Guide

**Get notified when your network devices go down!**

The Auspex alerting engine monitors your SNMP targets and sends notifications via **PagerDuty**, **Slack**, or **Email** when status changes occur.

---

## Features

- ✅ **Status change alerts** - Get notified when devices go down or come back up
- ✅ **Multiple channels** - PagerDuty, Slack (via email), standard email, webhooks
- ✅ **Per-target configuration** - Choose which devices trigger alerts
- ✅ **Alert suppression** - Schedule maintenance windows to silence alerts
- ✅ **De-duplication** - Prevent alert spam with configurable cooldown periods
- ✅ **Alert history** - Track all alerts and delivery status
- ✅ **Auto-resolution** - Automatically resolves alerts when devices recover

---

## Quick Start

### 1. Initialize Database Schema

Run the alerting schema initialization:

```bash
psql -U auspex -d auspexdb -f db-alerting-schema.sql
```

This creates the following tables:
- `alert_channels` - Notification channels (PagerDuty, Slack, Email)
- `alert_rules` - Alert rules per target
- `alert_history` - Alert firing history
- `alert_deliveries` - Notification delivery log
- `alert_suppressions` - Maintenance window schedules
- `alert_state` - Current state tracking for de-duplication

### 2. Configure SMTP (Required for Email & Slack)

Edit `config/auspex.conf`:

```bash
# Email/Slack configuration
AUSPEX_SMTP_HOST=smtp.gmail.com
AUSPEX_SMTP_PORT=587
AUSPEX_SMTP_USER=your-email@gmail.com
AUSPEX_SMTP_PASSWORD=your-app-password
AUSPEX_SMTP_FROM=auspex-alerts@yourdomain.com
```

**Gmail Users:** Generate an app-specific password at https://myaccount.google.com/apppasswords

**Office 365 Users:**
```bash
AUSPEX_SMTP_HOST=smtp-mail.outlook.com
AUSPEX_SMTP_PORT=587
```

### 3. Set Up Notification Channels

#### Option A: Via curl (Recommended)

**PagerDuty:**
```bash
curl -X POST http://localhost:8080/api/alert-channels \
  -H "Content-Type: application/json" \
  -d '{
    "name": "PagerDuty - Critical",
    "type": "pagerduty",
    "config": {
      "routing_key": "YOUR_PAGERDUTY_INTEGRATION_KEY"
    },
    "enabled": true
  }'
```

**Slack (Email-to-Channel):**
```bash
curl -X POST http://localhost:8080/api/alert-channels \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Slack - #alerts",
    "type": "slack_email",
    "config": {
      "email": "your-channel@yourworkspace.slack.com",
      "from": "auspex-alerts@yourdomain.com"
    },
    "enabled": true
  }'
```

**Email:**
```bash
curl -X POST http://localhost:8080/api/alert-channels \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Email - Ops Team",
    "type": "email",
    "config": {
      "to": "ops@yourdomain.com",
      "from": "auspex-alerts@yourdomain.com"
    },
    "enabled": true
  }'
```

#### Option B: Via psql

```sql
-- PagerDuty
INSERT INTO alert_channels (name, type, config, enabled) VALUES
  ('PagerDuty - Critical', 'pagerduty',
   '{"routing_key": "YOUR_PAGERDUTY_INTEGRATION_KEY"}', true);

-- Slack
INSERT INTO alert_channels (name, type, config, enabled) VALUES
  ('Slack - #alerts', 'slack_email',
   '{"email": "your-channel@yourworkspace.slack.com"}', true);

-- Email
INSERT INTO alert_channels (name, type, config, enabled) VALUES
  ('Email - Ops', 'email',
   '{"to": "ops@yourdomain.com", "from": "auspex-alerts@yourdomain.com"}', true);
```

### 4. Create Alert Rules for Targets

Get your channel IDs:
```bash
curl http://localhost:8080/api/alert-channels
```

Create an alert rule for a target:
```bash
curl -X POST http://localhost:8080/api/alert-rules \
  -H "Content-Type: application/json" \
  -d '{
    "target_id": 1,
    "name": "Core Router Down Alert",
    "rule_type": "status_change",
    "severity": "critical",
    "enabled": true,
    "channels": [1, 2]
  }'
```

This will:
- Monitor target ID 1 (your router)
- Send alerts to channels 1 and 2 (e.g., PagerDuty + Slack)
- Trigger on status changes (up ↔ down)
- Mark as "critical" severity

### 5. Start the Alerter

```bash
./start-alerter.sh
```

Or run directly:
```bash
export $(cat config/auspex.conf | xargs)
go run cmd/alerter/main.go
```

---

## Integration Guides

### PagerDuty Setup

1. Log in to PagerDuty
2. Go to **Services** → Select your service (or create one)
3. Go to **Integrations** tab
4. Click **Add Integration**
5. Select **Events API v2**
6. Copy the **Integration Key**
7. Use this key in your alert channel config

**Features:**
- Automatic incident creation when device goes down
- Automatic resolution when device comes back up
- De-duplication by target ID
- Severity mapping (critical/warning/info)

### Slack Setup (Email-to-Channel)

1. Open your Slack channel (e.g., `#alerts`)
2. Click channel name → **Integrations** → **Add an app**
3. Search for **Email** → **Get Email Address**
4. Copy the email address (format: `random-id@yourworkspace.slack.com`)
5. Use this email in your Slack channel config

**Features:**
- Real-time alerts in your Slack channel
- Formatted with emoji and severity levels
- Links to device details

### Email Setup

Standard SMTP email delivery to any address or distribution list.

**Supported Providers:**
- Gmail (use app passwords)
- Office 365 / Outlook
- SendGrid
- Amazon SES
- Custom SMTP servers

---

## Alert Suppression (Maintenance Windows)

Suppress alerts during maintenance windows to avoid noise.

### One-Time Suppression

Suppress a specific target for 2 hours:

```bash
curl -X POST http://localhost:8080/api/alert-suppressions \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Router Maintenance",
    "target_id": 1,
    "start_time": "2025-11-17T22:00:00Z",
    "end_time": "2025-11-18T00:00:00Z",
    "enabled": true,
    "reason": "Firmware upgrade"
  }'
```

### Recurring Suppression (Daily Quiet Hours)

Suppress alerts every night from 2 AM - 6 AM:

```bash
curl -X POST http://localhost:8080/api/alert-suppressions \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Nightly Quiet Hours",
    "target_id": null,
    "start_time": "2025-11-17T02:00:00Z",
    "end_time": "2025-11-17T06:00:00Z",
    "recurrence": "daily",
    "enabled": true,
    "reason": "Off-hours suppression"
  }'
```

**Note:** `target_id: null` means this applies to ALL targets globally.

### Weekly Suppression (Weekend Maintenance)

Suppress alerts every Saturday and Sunday:

```bash
curl -X POST http://localhost:8080/api/alert-suppressions \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Weekend Maintenance",
    "target_id": null,
    "start_time": "2025-11-17T00:00:00Z",
    "end_time": "2025-11-17T23:59:59Z",
    "recurrence": "weekly",
    "days_of_week": [0, 6],
    "enabled": true,
    "reason": "Weekend maintenance window"
  }'
```

**Days of week:** 0 = Sunday, 1 = Monday, ..., 6 = Saturday

---

## API Reference

### Alert Channels

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/alert-channels` | GET | List all channels |
| `/api/alert-channels` | POST | Create channel |
| `/api/alert-channels/:id` | PUT | Update channel |
| `/api/alert-channels/:id` | DELETE | Delete channel |

### Alert Rules

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/alert-rules` | GET | List all rules |
| `/api/alert-rules/target/:id` | GET | Get rules for target |
| `/api/alert-rules` | POST | Create rule |
| `/api/alert-rules/:id` | PUT | Update rule |
| `/api/alert-rules/:id` | DELETE | Delete rule |

### Alert History

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/alert-history` | GET | List alert history (paginated) |
| `/api/alert-history/active` | GET | List active (unresolved) alerts |
| `/api/alert-history/:id/deliveries` | GET | Get delivery log for alert |
| `/api/alert-stats` | GET | Get alert statistics |

### Alert Suppressions

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/alert-suppressions` | GET | List all suppressions |
| `/api/alert-suppressions/active` | GET | List currently active suppressions |
| `/api/alert-suppressions` | POST | Create suppression |
| `/api/alert-suppressions/:id` | PUT | Update suppression |
| `/api/alert-suppressions/:id` | DELETE | Delete suppression |

---

## Configuration Options

Edit `config/auspex.conf`:

```bash
# Alerter Settings
AUSPEX_ALERTER_ENABLED=true
AUSPEX_ALERTER_CHECK_INTERVAL_SECONDS=30    # How often to check for alerts
AUSPEX_ALERTER_DEDUP_WINDOW_MINUTES=15      # Don't duplicate alerts within 15min

# SMTP Settings
AUSPEX_SMTP_HOST=smtp.gmail.com
AUSPEX_SMTP_PORT=587
AUSPEX_SMTP_USER=your-email@gmail.com
AUSPEX_SMTP_PASSWORD=your-app-password
AUSPEX_SMTP_FROM=auspex-alerts@yourdomain.com

# PagerDuty (optional - can be set per channel)
AUSPEX_PAGERDUTY_INTEGRATION_KEY=your-key-here
```

---

## Troubleshooting

### Alerter not starting

**Check logs:**
```bash
./start-alerter.sh
# Look for error messages
```

**Common issues:**
- Database schema not initialized → Run `db-alerting-schema.sql`
- Config file missing → Check `config/auspex.conf` exists
- Database connection failed → Verify credentials in config

### Alerts not sending

**Check alert rules exist:**
```bash
curl http://localhost:8080/api/alert-rules
```

**Check alert channels are enabled:**
```bash
curl http://localhost:8080/api/alert-channels
```

**Check alert history:**
```bash
curl http://localhost:8080/api/alert-history
```

**Check delivery log:**
```bash
curl http://localhost:8080/api/alert-history/1/deliveries
```

### PagerDuty not receiving alerts

1. Verify integration key is correct
2. Check PagerDuty service is active
3. Look for errors in alerter logs
4. Test manually:
```bash
curl -X POST https://events.pagerduty.com/v2/enqueue \
  -H "Content-Type: application/json" \
  -d '{
    "routing_key": "YOUR_KEY",
    "event_action": "trigger",
    "payload": {
      "summary": "Test alert",
      "severity": "critical",
      "source": "test"
    }
  }'
```

### Slack not receiving alerts

1. Verify email address is correct (check Slack channel settings)
2. Verify SMTP is configured correctly
3. Test email sending manually
4. Check spam folder in Slack

### Email not sending

1. Verify SMTP credentials
2. For Gmail: Use app-specific password, not account password
3. Check firewall allows outbound SMTP (port 587 or 25)
4. Test with telnet:
```bash
telnet smtp.gmail.com 587
```

---

## Alert Example Messages

### Email/Slack (Device Down)
```
🔴 Target Router-Core-01 (192.168.1.1) is DOWN

Target: Router-Core-01
Host: 192.168.1.1
Status: DOWN
Time: 2025-11-17 14:23:45 UTC

Details:
SNMP timeout

---
Auspex SNMP Monitor
View Target: http://localhost:8080/target.html?id=1
```

### Email/Slack (Device Up)
```
✅ Target Router-Core-01 (192.168.1.1) is back UP (latency: 45ms)

Target: Router-Core-01
Host: 192.168.1.1
Status: UP
Latency: 45ms
Time: 2025-11-17 14:28:12 UTC

Details:
sysName="core-router" sysDescr="Cisco IOS"

---
Auspex SNMP Monitor
View Target: http://localhost:8080/target.html?id=1
```

### PagerDuty (Incident Created)
```
Summary: Target Router-Core-01 (192.168.1.1) is DOWN
Severity: critical
Source: auspex-monitor

Custom Details:
- Target ID: 1
- Target Name: Router-Core-01
- Host: 192.168.1.1
- Status: down
- Message: SNMP timeout
```

---

## Database Schema

### alert_channels
Stores notification channel configurations.

| Column | Type | Description |
|--------|------|-------------|
| id | serial | Primary key |
| name | varchar(255) | Channel name |
| type | varchar(50) | Channel type (pagerduty, slack_email, email, webhook) |
| config | jsonb | Channel-specific config (API keys, emails, etc.) |
| enabled | boolean | Whether channel is active |

### alert_rules
Defines alert rules per target.

| Column | Type | Description |
|--------|------|-------------|
| id | serial | Primary key |
| target_id | integer | Target to monitor |
| name | varchar(255) | Rule name |
| rule_type | varchar(50) | Rule type (status_change, latency_threshold, etc.) |
| severity | varchar(20) | Severity level (info, warning, critical) |
| enabled | boolean | Whether rule is active |
| channels | integer[] | Array of alert_channel IDs to notify |

### alert_history
Tracks all fired alerts.

| Column | Type | Description |
|--------|------|-------------|
| id | bigserial | Primary key |
| rule_id | integer | Alert rule that triggered |
| target_id | integer | Target that triggered alert |
| alert_type | varchar(50) | Alert type (device_down, device_up, etc.) |
| severity | varchar(20) | Severity level |
| message | text | Alert message |
| fired_at | timestamp | When alert was triggered |
| resolved_at | timestamp | When alert was resolved (NULL if active) |
| notified | boolean | Whether notifications were sent |

### alert_deliveries
Logs each notification attempt.

| Column | Type | Description |
|--------|------|-------------|
| id | bigserial | Primary key |
| alert_history_id | bigint | Alert that was sent |
| channel_id | integer | Channel used |
| channel_type | varchar(50) | Channel type |
| recipient | text | Recipient (email, webhook URL, etc.) |
| delivered_at | timestamp | When delivery was attempted |
| status | varchar(20) | Delivery status (sent, failed, bounced) |
| error_message | text | Error message if failed |

### alert_suppressions
Defines maintenance windows.

| Column | Type | Description |
|--------|------|-------------|
| id | serial | Primary key |
| name | varchar(255) | Suppression name |
| target_id | integer | Target to suppress (NULL = global) |
| start_time | timestamp | Suppression start |
| end_time | timestamp | Suppression end |
| recurrence | varchar(50) | Recurrence type (daily, weekly, monthly, NULL) |
| days_of_week | integer[] | Days of week for weekly recurrence |
| enabled | boolean | Whether suppression is active |
| reason | text | Reason for suppression |

---

## Best Practices

1. **Start with Email** - Test with email alerts first before configuring PagerDuty
2. **Use Suppressions** - Configure quiet hours to avoid alert fatigue
3. **Monitor Critical Devices First** - Don't alert on everything, start with key infrastructure
4. **Test Your Channels** - Verify alerts are being received before relying on them
5. **Set Up Multiple Channels** - Use PagerDuty for critical, Slack for warnings
6. **Review Alert History** - Use `/api/alert-history` to audit your alerting effectiveness

---

## Security Notes

1. **Protect config file:**
   ```bash
   chmod 600 config/auspex.conf
   ```

2. **Use app-specific passwords** for Gmail/Office 365

3. **Rotate PagerDuty integration keys** if exposed

4. **Don't commit** `auspex.conf` to version control

5. **Use environment variables** in production deployments

---

## Production Deployment

For production use, run the alerter as a systemd service:

```bash
sudo nano /etc/systemd/system/auspex-alerter.service
```

```ini
[Unit]
Description=Auspex Alerting Engine
After=network.target postgresql.service

[Service]
Type=simple
User=auspex
WorkingDirectory=/opt/auspex
EnvironmentFile=/opt/auspex/config/auspex.conf
ExecStart=/usr/bin/go run /opt/auspex/cmd/alerter/main.go
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl enable auspex-alerter
sudo systemctl start auspex-alerter
sudo systemctl status auspex-alerter
```

---

## Support

For issues or questions:
- Check logs: `./start-alerter.sh` output
- Verify database schema: `\dt alert*` in psql
- Test API endpoints: `curl http://localhost:8080/api/alert-channels`
- Review alert history: `SELECT * FROM alert_history ORDER BY fired_at DESC LIMIT 10;`

---

**Happy alerting! 🚨**
