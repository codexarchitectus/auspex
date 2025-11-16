package main

import (
    "database/sql"
    "fmt"
    "log"
    "math/rand"
    "os"
    "strconv"
    "sync"
    "time"

    gosnmp "github.com/gosnmp/gosnmp"
    _ "github.com/lib/pq"
)

type Target struct {
    ID          int
    Name        string
    Host        string
    Port        int
    Community   string
    SNMPVersion string
}

func main() {
    rand.Seed(time.Now().UnixNano())

    dbHost := getenv("AUSPEX_DB_HOST", "localhost")
    dbPort := getenv("AUSPEX_DB_PORT", "5432")
    dbName := getenv("AUSPEX_DB_NAME", "auspexdb")
    dbUser := getenv("AUSPEX_DB_USER", "auspex")
    dbPass := getenv("AUSPEX_DB_PASSWORD", "")
    intervalStr := getenv("AUSPEX_POLL_INTERVAL_SECONDS", "60")
    maxConcStr := getenv("AUSPEX_MAX_CONCURRENT_POLLS", "10")

    intervalSec, err := strconv.Atoi(intervalStr)
    if err != nil || intervalSec <= 0 {
        intervalSec = 60
    }

    maxConcurrent, err := strconv.Atoi(maxConcStr)
    if err != nil || maxConcurrent <= 0 {
        maxConcurrent = 10
    }

    connStr := fmt.Sprintf(
        "host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
        dbHost, dbPort, dbUser, dbPass, dbName,
    )

    db, err := sql.Open("postgres", connStr)
    if err != nil {
        log.Fatalf("failed to open DB: %v", err)
    }
    defer db.Close()

    if err := db.Ping(); err != nil {
        log.Fatalf("failed to ping DB: %v", err)
    }

    log.Printf("Auspex SNMP poller started (interval=%ds, maxConcurrent=%d)", intervalSec, maxConcurrent)

    ticker := time.NewTicker(time.Duration(intervalSec) * time.Second)
    defer ticker.Stop()

    pollOnce(db, maxConcurrent) // initial poll

    for range ticker.C {
        pollOnce(db, maxConcurrent)
    }
}

func pollOnce(db *sql.DB, maxConcurrent int) {
    targets, err := loadTargets(db)
    if err != nil {
        log.Printf("error loading targets: %v", err)
        return
    }

    if len(targets) == 0 {
        log.Printf("no enabled targets to poll")
        return
    }

    log.Printf("polling %d targets", len(targets))

    sem := make(chan struct{}, maxConcurrent)
    var wg sync.WaitGroup

    for _, t := range targets {
        wg.Add(1)
        sem <- struct{}{}

        go func(t Target) {
            defer wg.Done()
            defer func() { <-sem }()

            status, latency, message := pollTargetSNMP(t)

            if err := insertResult(db, t.ID, status, latency, message); err != nil {
                log.Printf("error inserting poll result for target %d (%s): %v", t.ID, t.Name, err)
            } else {
                log.Printf("polled target %d (%s) host=%s status=%s latency=%dms msg=%q",
                    t.ID, t.Name, t.Host, status, latency, message)
            }
        }(t)
    }

    wg.Wait()
}

func loadTargets(db *sql.DB) ([]Target, error) {
    rows, err := db.Query(`
        SELECT id, name, host, port, community, snmp_version
        FROM targets
        WHERE enabled = true`)
    if err != nil {
        return nil, err
    }
    defer rows.Close()

    var result []Target
    for rows.Next() {
        var t Target
        if err := rows.Scan(&t.ID, &t.Name, &t.Host, &t.Port, &t.Community, &t.SNMPVersion); err != nil {
            return nil, err
        }
        result = append(result, t)
    }
    return result, rows.Err()
}

// pollTargetSNMP performs a real SNMP v2c poll against three OIDs:
//  - sysDescr (1.3.6.1.2.1.1.1.0)
//  - sysUpTime (1.3.6.1.2.1.1.3.0)
//  - sysName  (1.3.6.1.2.1.1.5.0)
//
// SUCCESS criteria:
//  - SNMP connection succeeds
//  - GET on all three OIDs returns values
//  - status = "up", latency = RTT in ms
// FAILURE (timeout / error / missing OID):
//  - status = "down"
//  - latency = 0
//  - message includes error description
func pollTargetSNMP(t Target) (status string, latencyMs int, message string) {
    version := gosnmp.Version2c
    // schema allows other values, but we default to v2c for now
    if t.SNMPVersion != "" && t.SNMPVersion != "2c" {
        log.Printf("warning: target %d (%s) has unsupported snmp_version=%q, forcing v2c",
            t.ID, t.Name, t.SNMPVersion)
    }

    g := &gosnmp.GoSNMP{
        Target:    t.Host,
        Port:      uint16(t.Port),
        Community: t.Community,
        Version:   version,
        Timeout:   2 * time.Second,
        Retries:   1,
        Transport: "udp",
        MaxOids:   3,
    }

    start := time.Now()
    if err := g.Connect(); err != nil {
        return "down", 0, fmt.Sprintf("SNMP connect failed: %v", err)
    }
    defer g.Conn.Close()

    oids := []string{
        "1.3.6.1.2.1.1.1.0", // sysDescr
        "1.3.6.1.2.1.1.3.0", // sysUpTime
        "1.3.6.1.2.1.1.5.0", // sysName
    }

    pkt, err := g.Get(oids)
    latencyMs = int(time.Since(start).Milliseconds())

    if err != nil {
        return "down", 0, fmt.Sprintf("SNMP GET failed: %v", err)
    }

    if pkt == nil || pkt.Error != gosnmp.NoError {
        return "down", 0, fmt.Sprintf("SNMP error: %v", pkt.Error)
    }

    if len(pkt.Variables) != len(oids) {
        return "down", 0, fmt.Sprintf("SNMP response missing variables (got=%d expected=%d)",
            len(pkt.Variables), len(oids))
    }

    var descr, uptime, name string
    for i, v := range pkt.Variables {
        switch oids[i] {
        case "1.3.6.1.2.1.1.1.0": // sysDescr
            descr = snmpValueToString(v)
        case "1.3.6.1.2.1.1.3.0": // sysUpTime
            uptime = snmpValueToString(v)
        case "1.3.6.1.2.1.1.5.0": // sysName
            name = snmpValueToString(v)
        }
    }

    if descr == "" && uptime == "" && name == "" {
        return "down", 0, "SNMP GET returned no usable values"
    }

    msg := fmt.Sprintf("sysName=%q sysDescr=%q sysUpTime=%q", name, descr, uptime)
    return "up", latencyMs, msg
}

// Convert SNMP variable to string safely
func snmpValueToString(v gosnmp.SnmpPDU) string {
    switch val := v.Value.(type) {
    case string:
        return val
    case []byte:
        return string(val)
    case int, uint, int64, uint64, float32, float64:
        return fmt.Sprintf("%v", val)
    default:
        return fmt.Sprintf("%v", val)
    }
}

func insertResult(db *sql.DB, targetID int, status string, latency int, message string) error {
    _, err := db.Exec(
        `INSERT INTO poll_results (target_id, status, latency_ms, message, polled_at)
         VALUES ($1, $2, $3, $4, NOW())`,
        targetID, status, latency, message,
    )
    return err
}

func getenv(key, fallback string) string {
    v := os.Getenv(key)
    if v == "" {
        return fallback
    }
    return v
}
