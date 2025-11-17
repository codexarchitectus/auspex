# Feature Proposal: ICMP Ping Polling

**Status:** 💡 Proposed
**Priority:** High
**Estimated Effort:** 3 weeks
**Proposed Date:** 2025-11-17

---

## Overview

Enable ICMP (ping) as an alternative polling method per target, allowing devices to be monitored via ping instead of or in addition to SNMP.

---

## Problem Statement

**Current Limitation:**
Auspex only supports SNMP polling. This excludes:
- Devices without SNMP support (IoT devices, simple network equipment)
- Devices with unknown SNMP credentials
- Situations requiring quick reachability checks only
- Mixed environments where some devices need full SNMP, others just ping

**User Impact:**
- Cannot monitor devices lacking SNMP
- Must configure SNMP even for basic reachability checks
- No lightweight monitoring option
- Limited flexibility in deployment scenarios

---

## Proposed Solution

### Per-Target Polling Type Selection

Add a `poll_type` field to targets with three options:
1. **SNMP** - Traditional SNMP polling (default, current behavior)
2. **ICMP** - Ping-only monitoring (fast, lightweight)
3. **Both** - Both SNMP and ICMP (redundancy for critical devices)

### Example Use Cases

**Use Case 1: IoT Devices**
```
Device: Smart Light Bulb (no SNMP)
Poll Type: ICMP
Result: Track online/offline status, latency
```

**Use Case 2: Network Printer**
```
Device: Office Printer (SNMP unknown)
Poll Type: ICMP
Result: Monitor availability without credentials
```

**Use Case 3: Critical Router**
```
Device: Core Network Router
Poll Type: Both (SNMP + ICMP)
Result: Full metrics + redundant reachability check
```

**Use Case 4: Mixed Environment**
```
100 Cisco Routers: SNMP (full metrics)
200 IoT Sensors: ICMP (reachability only)
50 Printers: ICMP (availability)
10 Core Switches: Both (critical monitoring)
```

---

## Architecture

### Database Schema Changes

**Minimal change to `targets` table:**

```sql
ALTER TABLE targets
ADD COLUMN poll_type VARCHAR(20) NOT NULL DEFAULT 'snmp';

ALTER TABLE targets
ADD CONSTRAINT chk_poll_type
CHECK (poll_type IN ('snmp', 'icmp', 'both'));
```

**No changes to `poll_results` table** - reuse existing schema:
- `status`: 'up' (ping success) or 'down' (ping fail)
- `latency_ms`: Round-trip time in milliseconds
- `message`: "ICMP reply received" or "ICMP timeout"

### Code Changes

#### Poller (Go)

**Update Target struct:**
```go
type Target struct {
    ID          int
    Name        string
    Host        string
    Port        int
    Community   string
    SNMPVersion string
    PollType    string  // NEW: "snmp", "icmp", or "both"
}
```

**New ICMP polling function:**
```go
func pollTargetICMP(t Target) (status string, latencyMs int, message string) {
    pinger, err := ping.NewPinger(t.Host)
    if err != nil {
        return "down", 0, fmt.Sprintf("ICMP setup failed: %v", err)
    }

    pinger.Count = 1
    pinger.Timeout = 2 * time.Second
    pinger.SetPrivileged(true)

    start := time.Now()
    err = pinger.Run()
    latencyMs = int(time.Since(start).Milliseconds())

    if err != nil {
        return "down", 0, "ICMP timeout"
    }

    stats := pinger.Statistics()
    if stats.PacketsRecv > 0 {
        return "up", int(stats.AvgRtt.Milliseconds()), "ICMP reply received"
    }

    return "down", 0, "ICMP no reply"
}
```

**Modified polling logic:**
```go
func pollOnce(db *sql.DB, maxConcurrent int) {
    // ... existing code ...

    for _, t := range targets {
        go func(t Target) {
            switch t.PollType {
            case "icmp":
                status, latency, message := pollTargetICMP(t)
                insertResult(db, t.ID, status, latency, message)

            case "snmp":
                status, latency, message := pollTargetSNMP(t)
                insertResult(db, t.ID, status, latency, message)

            case "both":
                // Poll both methods
                statusICMP, latencyICMP, msgICMP := pollTargetICMP(t)
                insertResult(db, t.ID, statusICMP, latencyICMP, "ICMP: "+msgICMP)

                statusSNMP, latencySNMP, msgSNMP := pollTargetSNMP(t)
                insertResult(db, t.ID, statusSNMP, latencySNMP, "SNMP: "+msgSNMP)
            }
        }(t)
    }
}
```

**Go dependency:**
```bash
go get github.com/go-ping/ping
```

#### API Server (Node.js)

**Update target endpoints:**
```javascript
// POST /api/targets
app.post("/api/targets", async (req, res) => {
    const { name, host, port, community, snmp_version, enabled, poll_type } = req.body;

    const result = await pool.query(
        `INSERT INTO targets (name, host, port, community, snmp_version, enabled, poll_type)
         VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *`,
        [name, host, port || 161, community || 'public',
         snmp_version || '2c', enabled, poll_type || 'snmp']
    );

    res.json(result.rows[0]);
});

// PUT /api/targets/:id
app.put("/api/targets/:id", async (req, res) => {
    const { name, host, port, community, snmp_version, enabled, poll_type } = req.body;

    const result = await pool.query(
        `UPDATE targets SET name=$1, host=$2, port=$3, community=$4,
         snmp_version=$5, enabled=$6, poll_type=$7, updated_at=NOW()
         WHERE id=$8 RETURNING *`,
        [name, host, port, community, snmp_version, enabled, poll_type, req.params.id]
    );

    res.json(result.rows[0]);
});
```

#### Web UI

**Add poll type selector:**
```html
<label>Poll Type:</label>
<select id="poll_type">
    <option value="snmp">SNMP Only</option>
    <option value="icmp">ICMP (Ping) Only</option>
    <option value="both">Both SNMP + ICMP</option>
</select>

<!-- Conditionally hide SNMP fields -->
<div id="snmp-fields">
    <label>Port:</label>
    <input type="number" id="port" value="161">

    <label>Community:</label>
    <input type="text" id="community" value="public">

    <label>SNMP Version:</label>
    <select id="snmp_version">
        <option value="2c">2c</option>
    </select>
</div>

<script>
document.getElementById('poll_type').addEventListener('change', function() {
    const snmpFields = document.getElementById('snmp-fields');
    snmpFields.style.display = (this.value === 'icmp') ? 'none' : 'block';
});
</script>
```

**Display poll type in dashboard:**
```javascript
function renderTargetRow(target) {
    const pollTypeIcon = {
        'snmp': '📊',
        'icmp': '🏓',
        'both': '📊🏓'
    }[target.poll_type] || '❓';

    return `
        <tr>
            <td>${pollTypeIcon} ${target.name}</td>
            <td>${target.host}</td>
            <td>${target.poll_type}</td>
            <td class="status-${target.status}">${target.status}</td>
        </tr>
    `;
}
```

---

## Implementation Plan

### Phase 1: Database & Core (Week 1)
- [ ] Add `poll_type` column to targets table
- [ ] Migration script for existing targets
- [ ] Update API endpoints to support poll_type
- [ ] Add `github.com/go-ping/ping` dependency
- [ ] Implement `pollTargetICMP()` function

### Phase 2: Polling Logic (Week 2)
- [ ] Modify pollOnce() to route by poll_type
- [ ] Implement "both" mode (SNMP + ICMP)
- [ ] Handle ICMP privilege requirements
- [ ] Error handling and logging
- [ ] Testing with real devices

### Phase 3: UI & Documentation (Week 3)
- [ ] Add poll type selector to Add Target form
- [ ] Add poll type selector to Edit Target form
- [ ] Display poll type indicator in dashboard
- [ ] Update INSTALLATION.md (privilege requirements)
- [ ] Update GETTING-STARTED.md (ICMP examples)
- [ ] Add troubleshooting section

---

## Benefits

### For Users
✅ **Broader Device Support** - Monitor devices without SNMP
✅ **Simpler Setup** - No SNMP credentials needed for ping-only
✅ **Faster Polling** - ICMP is lighter and quicker than SNMP
✅ **Flexible Deployment** - Mix SNMP and ICMP targets
✅ **Redundancy** - Use "both" mode for critical devices

### For Auspex
✅ **Competitive Feature** - Standard in network monitoring tools
✅ **Low Complexity** - Reuses existing infrastructure
✅ **Backward Compatible** - Defaults to SNMP for existing targets
✅ **Broader Applicability** - Expands addressable market

---

## Challenges & Mitigations

| Challenge | Impact | Mitigation |
|-----------|--------|------------|
| **ICMP requires elevated privileges** | Medium | Use `setcap` on Linux, document requirements |
| **ICMP blocked by firewalls** | Low | Document firewall rules, provide troubleshooting |
| **Less data than SNMP** | Low | Expected - ICMP provides reachability only |
| **"Both" mode doubles poll results** | Low | Configurable, provides redundancy value |
| **Platform differences** | Medium | Use Go library (github.com/go-ping/ping) instead of shell |

---

## Technical Complexity

| Component | Complexity | Risk |
|-----------|-----------|------|
| Database Schema | Low | Low |
| ICMP Poller (Go) | Medium | Medium |
| API Endpoints | Low | Low |
| Web UI | Low | Low |
| Privilege Handling | Medium | Medium |

**Overall Complexity:** Low-Medium
**Overall Risk:** Low

---

## Privilege Requirements

### Linux
```bash
# Grant ICMP capabilities to poller binary
sudo setcap cap_net_raw=+ep /path/to/auspex-poller

# Verify
getcap /path/to/auspex-poller
# Output: /path/to/auspex-poller = cap_net_raw+ep
```

### macOS
```bash
# Run with sudo (or use setuid)
sudo /path/to/auspex-poller
```

### Windows
```
Run as Administrator
```

**Documentation:** Add to INSTALLATION.md and troubleshooting guides

---

## Migration for Existing Deployments

**Database Migration:**
```sql
-- Add column with default value
ALTER TABLE targets ADD COLUMN poll_type VARCHAR(20) DEFAULT 'snmp';

-- Set all existing targets to SNMP
UPDATE targets SET poll_type = 'snmp';

-- Make non-nullable
ALTER TABLE targets ALTER COLUMN poll_type SET NOT NULL;

-- Add constraint
ALTER TABLE targets ADD CONSTRAINT chk_poll_type
CHECK (poll_type IN ('snmp', 'icmp', 'both'));
```

**Deployment:**
1. Run database migration
2. Deploy updated poller (backward compatible)
3. Deploy updated API server
4. Deploy updated web UI

**User Impact:**
- Zero - all existing targets default to `poll_type='snmp'`
- No behavior change for existing deployments
- New feature available immediately for new targets

---

## Example Usage

### Add ICMP-Only Target

**Via API:**
```bash
curl -X POST http://localhost:8080/api/targets \
  -H "Content-Type: application/json" \
  -d '{
    "name": "IoT-Sensor",
    "host": "192.168.1.50",
    "poll_type": "icmp",
    "enabled": true
  }'
```

**Via Web UI:**
1. Click "Add Target"
2. Name: "IoT-Sensor"
3. Host: "192.168.1.50"
4. Poll Type: "ICMP (Ping) Only"
5. Click "Add"

### Add Both SNMP + ICMP

```bash
curl -X POST http://localhost:8080/api/targets \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Critical-Router",
    "host": "192.168.1.1",
    "port": 161,
    "community": "public",
    "snmp_version": "2c",
    "poll_type": "both",
    "enabled": true
  }'
```

### View Results

```sql
-- ICMP results
SELECT target_id, status, latency_ms, message, polled_at
FROM poll_results
WHERE target_id = 5
ORDER BY polled_at DESC
LIMIT 10;

-- Example output:
-- target_id | status | latency_ms | message              | polled_at
-- ----------+--------+------------+----------------------+-------------------
-- 5         | up     | 5          | ICMP reply received  | 2025-11-17 10:00:00
-- 5         | up     | 6          | ICMP reply received  | 2025-11-17 09:59:00
```

---

## Success Metrics

After implementation, users should be able to:

- ✅ Monitor devices without SNMP using ICMP ping
- ✅ Choose poll type (SNMP, ICMP, both) per target
- ✅ See ICMP poll results in dashboard with latency
- ✅ Mix SNMP and ICMP targets in single deployment
- ✅ Use "both" mode for redundant monitoring of critical devices

---

## Future Enhancements

Once core feature is implemented:

1. **Multi-ping averaging** - Send multiple pings, average latency
2. **Packet loss tracking** - Track % of lost ICMP packets
3. **Custom ICMP parameters** - TTL, packet size, TOS
4. **IPv6 support** - Ping IPv6 addresses
5. **Traceroute integration** - Path diagnostics on failure
6. **MTU testing** - ICMP with varying packet sizes

---

## Alternative Approaches Considered

### 1. Separate ICMP Poller Service
Create a second poller daemon specifically for ICMP.
- **Pros:** Clean separation of concerns
- **Cons:** More complexity, duplicate code
- **Decision:** Rejected - single poller simpler

### 2. Always Poll Both
Poll both SNMP and ICMP for all devices.
- **Pros:** Maximum data collection
- **Cons:** Doubles polling overhead, not always needed
- **Decision:** Rejected - make it configurable instead

### 3. External Ping Integration
Use external tools (fping, smokeping).
- **Pros:** Mature ICMP implementations
- **Cons:** External dependency, harder to integrate
- **Decision:** Rejected - Go library sufficient

---

## Dependencies

**New Go Dependency:**
- `github.com/go-ping/ping` v1.1.0+

**Platform Requirements:**
- Linux: `setcap` capability or root privileges
- macOS: sudo or setuid
- Windows: Administrator privileges

---

## Estimated Timeline

**Conservative Estimate:** 4 weeks
**Aggressive Estimate:** 2 weeks
**Realistic Estimate:** 3 weeks

**Breakdown:**
- Database + API: 3 days
- ICMP poller implementation: 5 days
- UI updates: 3 days
- Testing: 3 days
- Documentation: 2 days
- Privilege handling/deployment: 2 days

---

## Recommendation

**Status: Recommended for Implementation**

This feature provides significant value with reasonable complexity. It broadens Auspex's applicability and provides a commonly-requested monitoring option.

**Suggested Approach:**
1. Implement Phase 1-2 (database, core ICMP) in 2 weeks
2. Get user feedback on functionality
3. Polish UI and documentation in week 3
4. Deploy with clear upgrade documentation

---

## References

- **ICMP Protocol:** RFC 792 (Internet Control Message Protocol)
- **Go Ping Library:** https://github.com/go-ping/ping
- **Similar Tools:** LibreNMS, Observium, Nagios (all support ICMP + SNMP)

---

**Next Steps:** Review proposal, prioritize against other features, allocate development resources.
