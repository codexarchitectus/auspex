# Auspex Roadmap

**Last Updated:** 2025-11-17

---

## Current Status

### ✅ Completed Features (v1.0)

- **Core SNMP Polling** - SNMPv2c monitoring with configurable intervals
- **PostgreSQL Backend** - Reliable data storage with optimized indexes
- **Web Dashboard** - Real-time status display with auto-refresh
- **REST API** - Full programmatic access to targets and poll results
- **Target Management** - Add/edit/delete targets via web UI and API
- **Latency Tracking** - Historical latency graphs and statistics
- **Concurrent Polling** - Efficient polling of multiple devices simultaneously
- **CSV Bulk Import** - Import multiple targets from CSV file
- **Interactive Scripts** - Helper scripts for database setup and target addition

---

## In Progress

### 🚧 Active Development

Currently no features in active development.

---

## Planned Features

### 💡 Proposed (High Priority)

#### 1. **SNMP MIB Database** ([detailed proposal](docs/SNMP-MIB-DATABASE-PROPOSAL.md))
**Status:** Proposed
**Effort:** 6-8 weeks
**Priority:** High

Enable device-specific SNMP monitoring with reusable OID groups:
- Create OID templates for different device types (routers, servers, UPS)
- Assign templates to targets
- Collect device-specific metrics (CPU, memory, interfaces, etc.)
- Store structured data per OID
- Foundation for advanced alerting and graphing

**Benefits:**
- Monitor actual device performance, not just availability
- Device-specific dashboards
- Reusable templates across similar devices
- Professional-grade SNMP monitoring

#### 2. **Splunk HEC Integration** ([implementation plan](SPLUNK-HEC-IMPLEMENTATION-PLAN.md))
**Status:** Planned
**Effort:** 2-3 weeks
**Priority:** Medium-High

Export poll results to Splunk HTTP Event Collector:
- Separate export service (reliable, isolated)
- Guaranteed delivery with retry logic and DLQ
- Configurable batch size and intervals
- Support for raw poll results or aggregated metrics

**Benefits:**
- Centralized logging and analysis
- Integration with existing Splunk infrastructure
- Advanced querying and alerting capabilities
- Long-term data retention in Splunk

---

## Future Ideas

### 🔮 Under Consideration

#### Alerting & Notifications
- Threshold-based alerts (CPU > 80%, disk > 90%)
- Email/SMS/webhook notifications
- Alert suppression and escalation
- Custom alert rules per device or group

#### User Authentication & Authorization
- Multi-user support
- Role-based access control (admin, viewer, operator)
- API key authentication
- Audit logging

#### Advanced Dashboards
- Custom dashboard builder
- Multiple dashboard views
- Metric comparison across devices
- Customizable widgets and graphs

#### SNMPv3 Support
- Encrypted SNMP polling
- Authentication and privacy protocols
- Per-target security configuration

#### Multi-Tenancy
- Support for multiple organizations/customers
- Data isolation per tenant
- Tenant-specific dashboards and reports
- MSP-friendly features

#### Mobile Application
- Native iOS/Android apps
- Push notifications for alerts
- Device status overview
- Quick device management

#### Enhanced Reporting
- PDF report generation
- Scheduled email reports
- SLA reporting and tracking
- Capacity planning reports

#### SNMP Trap Receiver
- Receive SNMP trap notifications
- Store and display trap data
- Trap-based alerting
- Integration with polling data

#### MIB Browser
- Import standard MIB files
- Browse MIB tree structure
- Auto-populate OID definitions
- MIB-to-template converter

#### Data Retention & Archiving
- Configurable data retention policies
- Automatic archiving to cold storage (S3, etc.)
- Data aggregation for long-term storage
- Query across archived data

---

## Completed Milestones

### 📅 Version History

**v1.0 (Initial Release) - 2025-11-17**
- Core SNMP monitoring functionality
- Web dashboard and REST API
- PostgreSQL backend
- Basic target management
- Documentation suite

---

## Feedback & Suggestions

Have an idea for a new feature? We'd love to hear it!

**How to Submit:**
1. Open a GitHub Issue with the `enhancement` label
2. Start a Discussion in the Ideas category
3. Submit a detailed proposal to `docs/` folder via pull request

---

## Decision Framework

Features are evaluated based on:

| Criteria | Weight |
|----------|--------|
| **User Value** | High - Does it solve a real problem? |
| **Complexity** | Medium - How hard to implement? |
| **Maintenance** | High - Long-term support burden? |
| **Adoption** | Medium - How many users benefit? |
| **Alignment** | High - Fits Auspex vision? |

**Priority Levels:**
- **Critical** - Core functionality, security, data integrity
- **High** - Significant user value, competitive features
- **Medium** - Nice-to-have, quality of life improvements
- **Low** - Edge cases, niche use cases

---

## Contributing

Want to help build these features?

- Review [CONTRIBUTING.md](CONTRIBUTING.md) (coming soon)
- Check open issues with `help wanted` label
- Discuss implementation approach before starting major work
- Submit pull requests with tests and documentation

---

## Resources

**Documentation:**
- [Installation Guide](INSTALLATION.md)
- [Getting Started](GETTING-STARTED.md)
- [Codebase Summary](CODEBASE-SUMMARY.md)
- [Production Deployment](PRODUCTION-READY.md)

**Planning Documents:**
- [SNMP MIB Database Proposal](docs/SNMP-MIB-DATABASE-PROPOSAL.md)
- [Splunk HEC Implementation Plan](SPLUNK-HEC-IMPLEMENTATION-PLAN.md)

**Community:**
- GitHub Issues: Report bugs, request features
- GitHub Discussions: Ask questions, share ideas
- Pull Requests: Contribute code and documentation

---

**Last Review:** 2025-11-17
**Next Review:** Quarterly (or as needed)
