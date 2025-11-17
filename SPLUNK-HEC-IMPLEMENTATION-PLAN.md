# Splunk HEC Integration - Implementation Plan

**Project:** Auspex SNMP Network Monitor
**Feature:** Splunk HTTP Event Collector (HEC) Integration
**Architecture:** Separate Export Service (Recommended)
**Date:** 2025-11-17

---

## Executive Summary

This document outlines the implementation plan for integrating Splunk HEC into Auspex. The solution uses a separate Go-based export service that reads poll results from PostgreSQL and forwards them to Splunk HEC with guaranteed delivery.

**Key Requirements:**
- ✅ Reliability: Guaranteed delivery with retry logic and DLQ
- ✅ Raw poll results: Every SNMP poll sent to Splunk
- ✅ Isolation: Zero impact on core SNMP monitoring

---

## Recommended Architecture

### Component Diagram

```
┌──────────────────┐
│  SNMP Poller     │  (EXISTING - No Changes)
│  cmd/poller/     │
└────────┬─────────┘
         │
         ▼ INSERT poll_results
┌─────────────────────────────────────┐
│         PostgreSQL Database          │
│  ┌─────────────────────────────┐    │
│  │ poll_results (existing)     │    │
│  │ splunk_export_state (NEW)   │    │
│  │ splunk_failures (NEW - DLQ) │    │
│  └─────────────────────────────┘    │
└───────┬─────────────────────────────┘
        │
        │ SELECT WHERE id > watermark
        ▼
┌─────────────────────────────┐
│  Splunk Exporter Service    │
│  (NEW: cmd/splunk-exporter/)│
│                             │
│  1. Query new poll results  │
│  2. Transform to HEC format │
│  3. Batch & send (retry 3x) │
│  4. Update watermark        │
│  5. Failed → DLQ            │
└────────┬────────────────────┘
         │ HTTPS POST
         ▼
┌─────────────────────────────┐
│  Splunk HEC Endpoint        │
└─────────────────────────────┘
```

---

## Database Schema Changes

### Table: `splunk_export_state`
Tracks export progress using watermark pattern.

```sql
CREATE TABLE splunk_export_state (
    id              SERIAL PRIMARY KEY,
    last_exported_id BIGINT NOT NULL DEFAULT 0,
    last_exported_at TIMESTAMP NOT NULL DEFAULT NOW(),
    export_count    BIGINT NOT NULL DEFAULT 0,
    failure_count   BIGINT NOT NULL DEFAULT 0,
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

INSERT INTO splunk_export_state (last_exported_id) VALUES (0);
```

### Table: `splunk_failures`
Dead Letter Queue for failed exports.

```sql
CREATE TABLE splunk_failures (
    id              BIGSERIAL PRIMARY KEY,
    poll_result_id  BIGINT NOT NULL,
    target_id       INTEGER,
    target_name     VARCHAR(255),
    target_host     VARCHAR(255),
    status          VARCHAR(20),
    latency_ms      INTEGER,
    message         TEXT,
    polled_at       TIMESTAMP,
    hec_payload     JSONB NOT NULL,
    error_message   TEXT NOT NULL,
    retry_count     INTEGER NOT NULL DEFAULT 0,
    failed_at       TIMESTAMP NOT NULL DEFAULT NOW(),
    reprocessed     BOOLEAN NOT NULL DEFAULT false,
    reprocessed_at  TIMESTAMP
);

CREATE INDEX idx_splunk_failures_failed_at ON splunk_failures(failed_at DESC);
CREATE INDEX idx_splunk_failures_reprocessed ON splunk_failures(reprocessed, failed_at);
```

---

## New Service: Splunk Exporter

### File: `cmd/splunk-exporter/main.go`

**Core Functions:**
- `main()` - Initialize, connect to DB, start export loop
- `exportOnce()` - Single export cycle (fetch → transform → send → update)
- `getWatermark()` - Read last_exported_id from database
- `fetchNewResults()` - Query poll_results WHERE id > watermark
- `transformToHEC()` - Convert poll results to HEC JSON format
- `sendToHECWithRetry()` - Send batch with exponential backoff retry
- `updateWatermark()` - Update last_exported_id on success
- `insertFailure()` - Write failed events to DLQ

**Configuration (Environment Variables):**
```bash
AUSPEX_SPLUNK_ENABLED=true
AUSPEX_SPLUNK_HEC_URL=https://splunk.example.com:8088/services/collector/event
AUSPEX_SPLUNK_HEC_TOKEN=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
AUSPEX_SPLUNK_EXPORT_INTERVAL_SECONDS=30
AUSPEX_SPLUNK_BATCH_SIZE=100
AUSPEX_SPLUNK_RETRY_ATTEMPTS=3
AUSPEX_SPLUNK_RETRY_BACKOFF_SECONDS=1
```

---

## HEC Event Format

### Single Event Example
```json
{
  "time": 1700000000,
  "host": "auspex-server-01",
  "source": "auspex:snmp",
  "sourcetype": "auspex:poll_result",
  "event": {
    "target_id": 1,
    "target_name": "Office-Router",
    "target_host": "192.168.1.1",
    "status": "up",
    "latency_ms": 45,
    "message": "sysName=\"router1\" sysDescr=\"Cisco IOS...\"",
    "polled_at": "2025-11-17T08:00:00Z"
  }
}
```

### Batch Format
HEC expects newline-delimited JSON (not array):
```json
{"time":1700000000,"host":"auspex-server-01","source":"auspex:snmp","sourcetype":"auspex:poll_result","event":{...}}
{"time":1700000060,"host":"auspex-server-01","source":"auspex:snmp","sourcetype":"auspex:poll_result","event":{...}}
```

---

## Error Handling Strategy

### Retry Logic
```
Attempt 1: Send immediately
  └─ Failure → Wait 1s

Attempt 2: Send after 1s
  └─ Failure → Wait 2s

Attempt 3: Send after 2s (total 3s)
  └─ Failure → Wait 4s

Attempt 4: Send after 4s (total 7s)
  └─ Failure → Write to DLQ, update watermark (move forward)
```

### Dead Letter Queue (DLQ)
- Failed events stored in `splunk_failures` table
- Includes full context: event data, error message, retry count
- Watermark advances to prevent blocking
- Manual or automated reprocessing capability

---

## Implementation Phases

### Phase 1: Core Implementation
**Goal:** Working exporter with basic functionality

**Tasks:**
- [ ] Database migration scripts (`splunk_export_state`, `splunk_failures`)
- [ ] Core exporter service (~350 lines Go)
- [ ] Main loop with ticker (30s default)
- [ ] Watermark read/write
- [ ] Fetch new results (batch of 100)
- [ ] Transform to HEC JSON
- [ ] Send to HEC (basic HTTP POST)
- [ ] Configuration loading
- [ ] Basic error logging

**Deliverable:** Functional exporter sending data to Splunk

### Phase 2: Reliability & Error Handling
**Goal:** Production-grade reliability

**Tasks:**
- [ ] Retry logic with exponential backoff
- [ ] DLQ implementation
- [ ] Enhanced logging (structured logs, metrics)
- [ ] Unit tests (config validation, transformation, retry)
- [ ] Integration tests (mock HEC server, end-to-end)

**Deliverable:** Resilient exporter with guaranteed delivery

### Phase 3: Operations & Monitoring
**Goal:** Production deployment readiness

**Tasks:**
- [ ] Systemd service file
- [ ] Deployment documentation
- [ ] Monitoring queries (lag, DLQ size, failure rate)
- [ ] Troubleshooting guide
- [ ] Documentation updates (README, SPLUNK-INTEGRATION.md)

**Deliverable:** Production-ready deployment

---

## Configuration

### Add to `auspex.conf.example`:
```bash
# Splunk HEC Export
AUSPEX_SPLUNK_ENABLED=false
AUSPEX_SPLUNK_HEC_URL=
AUSPEX_SPLUNK_HEC_TOKEN=
AUSPEX_SPLUNK_EXPORT_INTERVAL_SECONDS=30
AUSPEX_SPLUNK_BATCH_SIZE=100
AUSPEX_SPLUNK_RETRY_ATTEMPTS=3
AUSPEX_SPLUNK_RETRY_BACKOFF_SECONDS=1
```

---

## Deployment

### Systemd Service
**File:** `/etc/systemd/system/auspex-splunk-exporter.service`

```ini
[Unit]
Description=Auspex Splunk HEC Exporter
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=auspex
Group=auspex
WorkingDirectory=/opt/auspex
EnvironmentFile=/opt/auspex/config/auspex.conf
ExecStart=/opt/auspex/bin/splunk-exporter
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

### Deployment Steps
```bash
# 1. Run database migration
psql -U auspex -d auspexdb -f db-migrations/splunk-hec-setup.sql

# 2. Build exporter
go build -o bin/splunk-exporter cmd/splunk-exporter/main.go

# 3. Configure
vim /opt/auspex/config/auspex.conf

# 4. Start service
sudo systemctl enable auspex-splunk-exporter
sudo systemctl start auspex-splunk-exporter
sudo systemctl status auspex-splunk-exporter
```

---

## Monitoring

### Health Checks
```sql
-- Export status
SELECT last_exported_id, last_exported_at,
       export_count, failure_count,
       NOW() - last_exported_at AS time_since_last_export
FROM splunk_export_state;

-- Export lag
SELECT MAX(id) - (SELECT last_exported_id FROM splunk_export_state) AS lag
FROM poll_results;

-- Recent failures
SELECT COUNT(*) AS failures, COUNT(DISTINCT target_id) AS affected_targets
FROM splunk_failures
WHERE failed_at > NOW() - INTERVAL '1 hour';
```

### Alerts to Configure
1. **Exporter Down:** Process not running for >5 minutes
2. **Export Lag:** Lag > 5000 events
3. **High Failure Rate:** >100 failures in last hour
4. **Stale Exports:** No export in >10 minutes

---

## Splunk Queries (Examples)

```spl
# All poll results
index=main sourcetype=auspex:poll_result

# Devices currently down
index=main sourcetype=auspex:poll_result status=down
| dedup target_name
| table target_name, target_host, polled_at, message

# Average latency by device (24h)
index=main sourcetype=auspex:poll_result status=up earliest=-24h
| stats avg(latency_ms) as avg_latency by target_name
| sort -avg_latency

# Uptime percentage (7d)
index=main sourcetype=auspex:poll_result earliest=-7d
| stats count(eval(status="up")) as up_count, count as total by target_name
| eval uptime_pct = round((up_count/total)*100, 2)
| table target_name, uptime_pct
```

---

## File Checklist

### New Files
- [ ] `cmd/splunk-exporter/main.go` (~350 lines)
- [ ] `cmd/splunk-exporter/README.md`
- [ ] `db-migrations/splunk-hec-setup.sql`
- [ ] `SPLUNK-INTEGRATION.md` (user guide)
- [ ] `systemd/auspex-splunk-exporter.service`

### Modified Files
- [ ] `README.md` (add Splunk section)
- [ ] `CODEBASE-SUMMARY.md` (update architecture)
- [ ] `GETTING-STARTED.md` (add Splunk setup)
- [ ] `auspex.conf.example` (add Splunk config)

---

## Estimated Effort

- **Phase 1 (Core):** 8-12 hours
- **Phase 2 (Reliability):** 8-12 hours
- **Phase 3 (Operations):** 6-8 hours
- **Testing:** 4-6 hours
- **Documentation:** 4-6 hours
- **Total:** 30-44 hours (~1 week)

---

## Future Enhancements

### Short-Term
- DLQ automated retry process
- Export metrics dashboard
- Filtered export (state changes only, specific targets)

### Medium-Term
- Advanced SNMP OID parsing (extract structured fields)
- Aggregated metrics (hourly summaries)
- Multiple destinations (Datadog, New Relic, etc.)

### Long-Term
- Real-time streaming (PostgreSQL LISTEN/NOTIFY)
- Custom alert rules
- Data retention policies

---

**Next Steps:** Choose implementation phase(s) and begin development.
