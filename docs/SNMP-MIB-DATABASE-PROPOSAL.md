# Feature Proposal: SNMP MIB Database

**Status:** 💡 Proposed
**Priority:** High
**Estimated Effort:** 6-8 weeks
**Proposed Date:** 2025-11-17

---

## Overview

Enable device-specific SNMP monitoring by allowing administrators to create reusable OID groups (templates) and assign them to targets, rather than polling the same hardcoded OIDs for every device.

---

## Problem Statement

**Current Limitation:**
Auspex polls the same 3 basic OIDs from every device:
- sysDescr (1.3.6.1.2.1.1.1.0)
- sysUpTime (1.3.6.1.2.1.1.3.0)
- sysName (1.3.6.1.2.1.1.5.0)

This provides basic availability monitoring but no performance or health metrics.

**User Impact:**
- Cannot monitor CPU, memory, disk, interface statistics
- No device-specific insights (router vs server vs UPS)
- Limited alerting capabilities (up/down only)
- No capacity planning data

---

## Proposed Solution

### Custom OID Polling Groups

Create a flexible system where:
1. **Administrators define OID groups** (templates) for device types
2. **Targets are assigned to OID groups** (e.g., "Cisco Router Template")
3. **Poller dynamically polls** the assigned OIDs for each target
4. **Results are stored** in structured format per OID
5. **Dashboard displays** device-specific metrics

### Example Use Cases

**Cisco Router Monitoring:**
```
OID Group: "cisco-router"
- CPU usage (5sec, 1min, 5min)
- Memory usage (used, free)
- Interface traffic (ifInOctets, ifOutOctets)
- Interface errors (ifInErrors, ifOutErrors)
- Temperature sensors
```

**Linux Server Monitoring:**
```
OID Group: "linux-server"
- CPU load (1min, 5min, 15min)
- Memory (total, free, cached)
- Disk usage (per mount point)
- Process count
- Network interface stats
```

**UPS Monitoring:**
```
OID Group: "ups-battery"
- Battery voltage
- Battery current
- Battery charge percentage
- Load percentage
- Time remaining on battery
- Input/output voltage
```

---

## Architecture

### Database Schema Changes

**New Tables:**

1. **`oid_groups`** - Define OID templates
   - id, name, description, created_at

2. **`oid_definitions`** - OIDs within each group
   - id, group_id, oid, name, description, data_type, units, thresholds

3. **`targets.oid_group_id`** - Link targets to OID groups
   - Add column to existing `targets` table

4. **`oid_poll_results`** - Structured OID poll results
   - id, poll_result_id, oid_definition_id, value_raw, value_numeric, value_string, polled_at

### Code Changes

**Poller (Go):**
- Load OID group for each target
- Poll dynamic OID list per target
- Store individual OID results
- Maintain backward compatibility

**API (Node.js):**
- CRUD endpoints for OID groups
- CRUD endpoints for OID definitions
- Endpoint to retrieve OID poll results
- Target assignment endpoints

**Web UI:**
- OID group management interface
- OID definition editor
- Target assignment selector
- OID results visualization

---

## Implementation Phases

### Phase 1: Core Infrastructure (2-3 weeks)
- [ ] Database schema (4 tables)
- [ ] Migration script
- [ ] Default OID group (backward compatibility)
- [ ] API endpoints for OID groups and definitions
- [ ] Basic poller support (read groups, no custom polling yet)

### Phase 2: Dynamic Polling (2 weeks)
- [ ] Poller polls custom OIDs per target
- [ ] Store individual OID results in `oid_poll_results`
- [ ] API endpoints for OID results retrieval
- [ ] Data migration for existing targets

### Phase 3: Web UI (2 weeks)
- [ ] OID group management page
- [ ] OID definition editor
- [ ] Target assignment interface
- [ ] OID results display on target detail page

### Phase 4: Pre-Built Templates (1-2 weeks)
- [ ] Cisco IOS router template
- [ ] Cisco switch template
- [ ] Linux server template (Net-SNMP)
- [ ] Windows server template
- [ ] UPS template (RFC 1628)
- [ ] Template import/export functionality

### Phase 5: Advanced Features (Future)
- [ ] Threshold-based alerting per OID
- [ ] OID value graphing (Chart.js)
- [ ] MIB file import tool
- [ ] Custom calculations (e.g., derive bandwidth from counters)
- [ ] Template marketplace

---

## Benefits

### For Users
- **Meaningful Monitoring:** Track actual device performance, not just availability
- **Device-Specific Insights:** Different metrics for routers, servers, UPS systems
- **Reusable Templates:** Create once, apply to many devices
- **Scalability:** Monitor 1000s of devices with standardized templates
- **Foundation for Alerting:** Threshold-based alerts on any metric

### For Auspex
- **Competitive Feature:** Match capabilities of enterprise SNMP tools
- **User Retention:** Provides value beyond basic ping monitoring
- **Extensibility:** Easy to add new device types without code changes
- **Professional Grade:** Positions Auspex as serious monitoring platform

---

## Technical Complexity

| Component | Complexity | Risk |
|-----------|-----------|------|
| Database Schema | Low | Low |
| Poller Changes | Medium | Medium |
| API Endpoints | Low | Low |
| Web UI | Medium | Low |
| Template Library | Low | Low |

**Overall Complexity:** Medium
**Overall Risk:** Low-Medium

---

## Challenges & Mitigations

| Challenge | Mitigation |
|-----------|------------|
| **Database growth** | Implement data retention policies, archiving |
| **Query performance** | Add proper indexes, consider materialized views |
| **Polling overhead** | Limit OIDs per group (max 20-30), batch queries |
| **Backward compatibility** | Maintain default OID group, migration script |
| **OID catalog complexity** | Provide pre-built templates, documentation |
| **UI complexity** | Intuitive design, good defaults, wizards |

---

## Success Metrics

After implementation, users should be able to:

- ✅ Monitor 10+ metrics per device (vs. 3 today)
- ✅ Create and reuse monitoring templates
- ✅ See device-specific dashboards
- ✅ Track resource utilization trends
- ✅ Deploy monitoring for new device types without code changes
- ✅ Export/import templates across Auspex instances

---

## Dependencies

- None (self-contained feature)
- Optional: Splunk HEC integration could export OID data

---

## Alternative Approaches Considered

### 1. JSON Configuration Files
Store OID groups in JSON files instead of database.
- **Pros:** Simple, version-controllable
- **Cons:** Not editable via UI, harder to manage at scale
- **Decision:** Rejected - database provides better UX

### 2. Single OID Table (No Groups)
Allow adding individual OIDs to targets without grouping.
- **Pros:** Simpler schema
- **Cons:** Not reusable, hard to manage 100s of targets
- **Decision:** Rejected - groups essential for scalability

### 3. Hardcoded Device Profiles
Add code-based profiles for common devices.
- **Pros:** No database changes needed
- **Cons:** Requires code changes for new devices, not user-configurable
- **Decision:** Rejected - not flexible enough

---

## Future Enhancements

Once core feature is complete:

- **MIB Browser:** Import standard MIB files to auto-populate OID definitions
- **SNMP Traps:** Receive trap notifications from devices
- **SNMPv3 Support:** Encrypted SNMP polling
- **Advanced Calculations:** Derive metrics (e.g., bandwidth from counter deltas)
- **Custom Dashboards:** User-defined metric visualizations
- **Multi-Target Graphs:** Compare metrics across multiple devices
- **Automated Templates:** AI-suggested OIDs based on device type detection

---

## Estimated Timeline

**Conservative Estimate:** 8 weeks
**Aggressive Estimate:** 6 weeks
**Realistic Estimate:** 6-8 weeks

**Breakdown:**
- Development: 4-5 weeks
- Testing: 1 week
- Documentation: 1 week
- Template library: 1-2 weeks

---

## Recommendation

**Status: Recommended for Implementation**

This feature provides significant value with manageable complexity. It transforms Auspex from a basic availability monitor to a comprehensive SNMP monitoring platform.

**Suggested Approach:**
1. Implement Phase 1-2 first (core + polling) to validate approach
2. Get user feedback on API and data structure
3. Build UI based on proven backend
4. Expand template library based on user requests

---

## References

- **SNMP Standards:** RFC 1157 (SNMPv1), RFC 3416 (SNMPv2c)
- **Common MIBs:** IF-MIB, HOST-RESOURCES-MIB, UPS-MIB
- **Similar Tools:** LibreNMS, Observium, PRTG Network Monitor

---

**Next Steps:** Review proposal, prioritize against other features, allocate development resources.
