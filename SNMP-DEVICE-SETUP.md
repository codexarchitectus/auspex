# SNMP Device Setup Guide

## Preparing Network Devices for Auspex Monitoring

This guide explains how to enable and configure SNMP on your network devices so Auspex can monitor them.

## Quick Reference

**Common Default Settings:**
- **Port:** 161 (UDP)
- **Community String:** public (READ-ONLY)
- **SNMP Version:** 2c (most compatible)
- **Required OIDs:** System group (1.3.6.1.2.1.1.*)

## SNMP Versions

| Version | Security | Compatibility | Recommended |
|---------|----------|---------------|-------------|
| SNMPv1 | Plaintext community string | Very high | No (legacy) |
| SNMPv2c | Plaintext community string | High | **Yes** (current) |
| SNMPv3 | Authentication & encryption | Medium | Future support |

**Current Auspex Support:** SNMPv2c (SNMPv1 and v3 settings accepted but use v2c protocol)

## Device-Specific Configuration

### Cisco IOS Routers/Switches

```cisco
! Enable SNMP with community string
snmp-server community public RO

! (Optional) Restrict access to specific monitoring host
access-list 50 permit host 10.0.0.100
snmp-server community public RO 50

! Set system information
snmp-server location "Server Room Rack 42"
snmp-server contact "admin@example.com"

! Enable SNMP traps (optional)
snmp-server enable traps
```

**Verify:**
```cisco
show snmp community
show snmp location
show snmp contact
```

### Linux Servers (net-snmp)

**Install:**
```bash
# Ubuntu/Debian
sudo apt-get install snmpd snmp

# RHEL/CentOS
sudo yum install net-snmp net-snmp-utils
```

**Configure `/etc/snmp/snmpd.conf`:**
```conf
# Listen on all interfaces
agentAddress udp:161

# Set community string (read-only)
rocommunity public

# Set system information
syslocation "Data Center - Row 3"
syscontact "sysadmin@example.com"

# Limit access to monitoring server (recommended)
rocommunity public 10.0.0.100
```

**Start service:**
```bash
sudo systemctl enable snmpd
sudo systemctl start snmpd
sudo systemctl status snmpd
```

**Test locally:**
```bash
snmpwalk -v 2c -c public localhost system
```

### Ubiquiti UniFi Devices

**Web Interface:**
1. Navigate to **Settings** → **Services**
2. Enable **SNMP**
3. Set **Community:** public (or custom string)
4. Set **Version:** SNMPv2c
5. Click **Apply**

**CLI (SSH):**
```bash
set service snmp community public authorization ro
set service snmp location "Office Building"
set service snmp contact "netadmin@example.com"
commit
save
```

### MikroTik RouterOS

```routeros
/snmp
set enabled=yes
set contact="admin@example.com"
set location="Main Office"

/snmp community
set [find default=yes] name=public
```

**Verify:**
```routeros
/snmp print
/snmp community print
```

### Juniper JunOS

```junos
set snmp community public authorization read-only
set snmp location "Network Core"
set snmp contact "noc@example.com"
commit
```

**Verify:**
```junos
show snmp community
show snmp statistics
```

### Windows Server (SNMP Service)

**Install:**
1. Server Manager → **Add Roles and Features**
2. Features → **SNMP Service** → Install

**Configure:**
1. Services → **SNMP Service** → Properties
2. **Agent** tab:
   - Contact: admin@example.com
   - Location: Server Room
3. **Security** tab:
   - Add community: `public` (READ ONLY)
   - Accept SNMP packets from: `10.0.0.100` (monitoring server)
4. Restart SNMP Service

### pfSense/OPNsense Firewall

**pfSense:**
1. Services → **SNMP**
2. Enable: ✓
3. Poll Port: 161
4. System Location: "Edge Firewall"
5. System Contact: "security@example.com"
6. Community String: public
7. Save

**OPNsense:**
1. Services → **Net-SNMP**
2. Enable: ✓
3. Listen Interfaces: LAN
4. Community: public (read-only)
5. Location/Contact: as needed
6. Save

### HP/Aruba Switches

```hp
snmp-server community public unrestricted
snmp-server location "Building A - IDF"
snmp-server contact "netops@example.com"
```

**Verify:**
```hp
show snmp-server
```

## Security Best Practices

### 1. Change Default Community String

❌ **Bad:** `public`
✓ **Good:** `M0n1t0r!ngStr1ng2024`

```bash
# Example: Cisco
snmp-server community M0n1t0r!ngStr1ng2024 RO
```

Update Auspex target configuration with the new string.

### 2. Restrict Access by IP

Only allow SNMP queries from your Auspex monitoring server:

**Cisco:**
```cisco
access-list 90 permit host 10.0.0.100
snmp-server community M0n1t0r!ngStr1ng2024 RO 90
```

**Linux:**
```conf
rocommunity M0n1t0r!ngStr1ng2024 10.0.0.100
```

### 3. Use Read-Only Communities

**Never use read-write (RW) community strings** for monitoring! Auspex only needs read-only access.

### 4. Firewall Rules

Only allow UDP port 161 from your monitoring server:

**iptables (Linux):**
```bash
iptables -A INPUT -p udp --dport 161 -s 10.0.0.100 -j ACCEPT
iptables -A INPUT -p udp --dport 161 -j DROP
```

**pfSense/OPNsense:**
Create firewall rule allowing UDP 161 from monitoring server IP only.

### 5. Disable SNMP on Unused Interfaces

Only enable SNMP on management interfaces, not public-facing interfaces.

### 6. Monitor SNMP Access Logs

Review logs regularly for unauthorized access attempts:

**Linux:**
```bash
tail -f /var/log/snmpd.log
```

**Cisco:**
```cisco
show snmp stats
```

## Testing SNMP Configuration

### From Auspex Server

**Test basic connectivity:**
```bash
# Install snmp tools if needed
# macOS: brew install net-snmp
# Linux: apt-get install snmp

snmpget -v 2c -c public 192.168.1.1 1.3.6.1.2.1.1.1.0
```

**Expected output:**
```
SNMPv2-MIB::sysDescr.0 = STRING: Cisco IOS Software...
```

**Walk the system tree:**
```bash
snmpwalk -v 2c -c public 192.168.1.1 system
```

**Test the three OIDs Auspex uses:**
```bash
# sysDescr
snmpget -v 2c -c public 192.168.1.1 1.3.6.1.2.1.1.1.0

# sysUpTime
snmpget -v 2c -c public 192.168.1.1 1.3.6.1.2.1.1.3.0

# sysName
snmpget -v 2c -c public 192.168.1.1 1.3.6.1.2.1.1.5.0
```

### Common Issues

**Problem:** `Timeout: No Response`

**Solutions:**
- Verify device IP is reachable: `ping 192.168.1.1`
- Check SNMP service is running on device
- Verify community string matches
- Check firewall rules (both sides)
- Confirm SNMP is listening on UDP 161: `netstat -an | grep 161`

**Problem:** `No Such Object available on this agent`

**Solutions:**
- Device doesn't support requested OID
- SNMP version mismatch
- Try SNMPv1 instead: `snmpget -v 1 -c public ...`

**Problem:** `Authentication failure`

**Solutions:**
- Wrong community string
- IP-based ACL blocking access
- Check device logs for security violations

## Supported Device Types

Auspex can monitor any device that supports SNMPv2c and returns standard system OIDs:

✓ **Network Equipment:**
- Routers (Cisco, Juniper, MikroTik, Ubiquiti)
- Switches (Cisco, HP, Aruba, Dell)
- Firewalls (pfSense, OPNsense, Fortinet, Palo Alto)
- Wireless Access Points (Ubiquiti, Cisco, Aruba)
- Load Balancers (F5, HAProxy)

✓ **Servers:**
- Linux (any distribution with net-snmp)
- Windows Server (with SNMP service)
- VMware ESXi
- Proxmox VE

✓ **Storage:**
- NAS devices (Synology, QNAP, TrueNAS)
- SAN controllers

✓ **Other:**
- UPS systems (APC, Eaton, CyberPower)
- Environmental monitors
- Printers (network-attached)
- IoT devices with SNMP support

## Quick Start Checklist

- [ ] Enable SNMP service on device
- [ ] Set community string (change from default!)
- [ ] Configure SNMPv2c
- [ ] Set system location and contact
- [ ] Restrict access to monitoring server IP
- [ ] Open firewall for UDP port 161
- [ ] Test with `snmpget` or `snmpwalk`
- [ ] Add device to Auspex via web UI or API
- [ ] Verify polls succeed in Auspex dashboard

## Adding Device to Auspex

Once SNMP is configured, add the device:

**Via Script:**
```bash
./add-target.sh
```

**Via API:**
```bash
curl -X POST http://localhost:8080/api/targets \
  -H "Content-Type: application/json" \
  -d '{
    "name": "My-Router",
    "host": "192.168.1.1",
    "port": 161,
    "community": "M0n1t0r!ngStr1ng2024",
    "snmp_version": "2c",
    "enabled": true
  }'
```

**Via Web UI:**
1. Open http://localhost:8080
2. Click "Add Target" or use bulk CSV import
3. Enter device details
4. Click "Add"

The poller will automatically detect the new target within 60 seconds and begin monitoring.

## Need Help?

**Test SNMP configuration:**
```bash
snmpwalk -v 2c -c YOUR_COMMUNITY TARGET_IP system
```

**View Auspex poller logs:**
The poller outputs to stderr/stdout. Check the terminal where it's running.

**View poll results:**
```sql
psql -U auspex -d auspexdb -c "SELECT * FROM poll_results ORDER BY polled_at DESC LIMIT 10;"
```
