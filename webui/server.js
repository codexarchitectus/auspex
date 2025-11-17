// Load environment config
require("dotenv").config({ path: "/opt/auspex/config/auspex.conf" });

const express = require("express");
const path = require("path");
const bodyParser = require("body-parser");
const { Pool } = require("pg");

const app = express();
app.use(bodyParser.json());

// Database connection pool
const pool = new Pool({
    host: process.env.AUSPEX_DB_HOST,
    port: process.env.AUSPEX_DB_PORT,
    user: process.env.AUSPEX_DB_USER,
    password: process.env.AUSPEX_DB_PASSWORD,
    database: process.env.AUSPEX_DB_NAME
});

// Serve static files
app.use(express.static(path.join(__dirname)));


// ======================================================================
// EXISTING ROUTES
// ======================================================================

// GET /api/targets — list targets + latest status
app.get("/api/targets", async (req, res) => {
    try {
        const sql = `
            SELECT t.*,
                   pr.status,
                   pr.latency_ms,
                   pr.message,
                   pr.polled_at
            FROM targets t
            LEFT JOIN LATERAL (
               SELECT * FROM poll_results
               WHERE target_id = t.id
               ORDER BY polled_at DESC
               LIMIT 1
            ) pr ON TRUE
            ORDER BY t.id;
        `;
        const result = await pool.query(sql);
        res.json(result.rows);
    } catch (err) {
        console.error("Error fetching targets:", err);
        res.status(500).json({ error: err.message });
    }
});

// POST /api/targets — add a target
app.post("/api/targets", async (req, res) => {
    try {
        const { name, host, port, community, snmp_version, enabled } = req.body;

        const result = await pool.query(
            `INSERT INTO targets (name, host, port, community, snmp_version, enabled)
             VALUES ($1, $2, $3, $4, $5, $6)
             RETURNING *`,
            [name, host, port, community, snmp_version, enabled]
        );

        res.json(result.rows[0]);
    } catch (err) {
        console.error("Error adding target:", err);
        res.status(500).json({ error: err.message });
    }
});

// PUT /api/targets/:id — update a target
app.put("/api/targets/:id", async (req, res) => {
    try {
        const id = req.params.id;
        const { name, host, port, community, snmp_version, enabled } = req.body;

        const result = await pool.query(
            `UPDATE targets
             SET name=$1, host=$2, port=$3, community=$4, snmp_version=$5, enabled=$6,
                 updated_at=NOW()
             WHERE id=$7
             RETURNING *`,
            [name, host, port, community, snmp_version, enabled, id]
        );

        res.json(result.rows[0]);
    } catch (err) {
        console.error("Error updating target:", err);
        res.status(500).json({ error: err.message });
    }
});

// DELETE /api/targets/:id — soft disable
app.delete("/api/targets/:id", async (req, res) => {
    try {
        const id = req.params.id;

        const result = await pool.query(
            `UPDATE targets SET enabled=false WHERE id=$1 RETURNING *`,
            [id]
        );

        res.json(result.rows[0]);
    } catch (err) {
        console.error("Error disabling target:", err);
        res.status(500).json({ error: err.message });
    }
});


// ======================================================================
// NEW ROUTES FOR TARGET DETAIL PAGE
// ======================================================================

// Get most recent poll result
app.get("/api/targets/:id/latest", async (req, res) => {
    try {
        const id = req.params.id;
        const result = await pool.query(
            `SELECT *
             FROM poll_results
             WHERE target_id = $1
             ORDER BY polled_at DESC
             LIMIT 1`,
            [id]
        );
        res.json(result.rows[0] || {});
    } catch (err) {
        console.error("Error fetching latest poll:", err);
        res.status(500).json({ error: err.message });
    }
});

// Get latency samples for last hour
app.get("/api/targets/:id/latency", async (req, res) => {
    try {
        const id = req.params.id;
        const result = await pool.query(
            `SELECT latency_ms, polled_at
             FROM poll_results
             WHERE target_id = $1
               AND polled_at > NOW() - INTERVAL '1 hour'
             ORDER BY polled_at ASC`,
            [id]
        );
        res.json(result.rows);
    } catch (err) {
        console.error("Error fetching latency data:", err);
        res.status(500).json({ error: err.message });
    }
});

// Get last hour stats: min, max, avg, uptime
app.get("/api/targets/:id/stats", async (req, res) => {
    try {
        const id = req.params.id;
        const result = await pool.query(
            `SELECT 
                MIN(latency_ms) AS min_latency,
                MAX(latency_ms) AS max_latency,
                AVG(latency_ms) AS avg_latency,
                COUNT(*) FILTER (WHERE status='up') AS up_count,
                COUNT(*) AS total_count
             FROM poll_results
             WHERE target_id = $1
               AND polled_at > NOW() - INTERVAL '1 hour'`,
            [id]
        );
        res.json(result.rows[0]);
    } catch (err) {
        console.error("Error fetching stats:", err);
        res.status(500).json({ error: err.message });
    }
});

// Get full target configuration
app.get("/api/targets/:id/info", async (req, res) => {
    try {
        const id = req.params.id;
        const result = await pool.query(
            `SELECT * FROM targets WHERE id=$1`,
            [id]
        );
        res.json(result.rows[0] || {});
    } catch (err) {
        console.error("Error fetching target info:", err);
        res.status(500).json({ error: err.message });
    }
});

// Save/edit target configuration
app.post("/api/targets/:id/update", async (req, res) => {
    try {
        const id = req.params.id;
        const { name, host, port, community, snmp_version, enabled } = req.body;

        const result = await pool.query(
            `UPDATE targets
             SET name=$1, host=$2, port=$3, community=$4,
                 snmp_version=$5, enabled=$6, updated_at=NOW()
             WHERE id=$7
             RETURNING *`,
            [name, host, port, community, snmp_version, enabled, id]
        );

        res.json(result.rows[0]);
    } catch (err) {
        console.error("Error editing target:", err);
        res.status(500).json({ error: err.message });
    }
});

// Hard-delete a target
app.delete("/api/targets/:id/delete", async (req, res) => {
    try {
        const id = req.params.id;

        await pool.query(`DELETE FROM poll_results WHERE target_id=$1`, [id]);
        const result = await pool.query(`DELETE FROM targets WHERE id=$1 RETURNING *`, [id]);

        res.json(result.rows[0]);
    } catch (err) {
        console.error("Error deleting target:", err);
        res.status(500).json({ error: err.message });
    }
});


// ======================================================================
// User guide
// ======================================================================
app.get("/api/user-guide", (req, res) => {
    res.sendFile(path.join(__dirname, "user-guide.html"));
});


// ======================================================================
// ALERTING ENGINE API ENDPOINTS
// ======================================================================

// ====== Alert Channels ======

// GET /api/alert-channels — list all alert channels
app.get("/api/alert-channels", async (req, res) => {
    try {
        const result = await pool.query(`
            SELECT * FROM alert_channels
            ORDER BY id
        `);
        res.json(result.rows);
    } catch (err) {
        console.error("Error fetching alert channels:", err);
        res.status(500).json({ error: err.message });
    }
});

// POST /api/alert-channels — create new alert channel
app.post("/api/alert-channels", async (req, res) => {
    try {
        const { name, type, config, enabled } = req.body;

        const result = await pool.query(`
            INSERT INTO alert_channels (name, type, config, enabled)
            VALUES ($1, $2, $3, $4)
            RETURNING *
        `, [name, type, JSON.stringify(config), enabled !== false]);

        res.json(result.rows[0]);
    } catch (err) {
        console.error("Error creating alert channel:", err);
        res.status(500).json({ error: err.message });
    }
});

// PUT /api/alert-channels/:id — update alert channel
app.put("/api/alert-channels/:id", async (req, res) => {
    try {
        const id = req.params.id;
        const { name, type, config, enabled } = req.body;

        const result = await pool.query(`
            UPDATE alert_channels
            SET name=$1, type=$2, config=$3, enabled=$4, updated_at=NOW()
            WHERE id=$5
            RETURNING *
        `, [name, type, JSON.stringify(config), enabled, id]);

        res.json(result.rows[0]);
    } catch (err) {
        console.error("Error updating alert channel:", err);
        res.status(500).json({ error: err.message });
    }
});

// DELETE /api/alert-channels/:id — delete alert channel
app.delete("/api/alert-channels/:id", async (req, res) => {
    try {
        const id = req.params.id;
        const result = await pool.query(`
            DELETE FROM alert_channels WHERE id=$1 RETURNING *
        `, [id]);

        res.json(result.rows[0]);
    } catch (err) {
        console.error("Error deleting alert channel:", err);
        res.status(500).json({ error: err.message });
    }
});

// ====== Alert Rules ======

// GET /api/alert-rules — list all alert rules
app.get("/api/alert-rules", async (req, res) => {
    try {
        const result = await pool.query(`
            SELECT ar.*, t.name as target_name, t.host
            FROM alert_rules ar
            JOIN targets t ON t.id = ar.target_id
            ORDER BY ar.id
        `);
        res.json(result.rows);
    } catch (err) {
        console.error("Error fetching alert rules:", err);
        res.status(500).json({ error: err.message });
    }
});

// GET /api/alert-rules/target/:targetId — get alert rules for a specific target
app.get("/api/alert-rules/target/:targetId", async (req, res) => {
    try {
        const targetId = req.params.targetId;
        const result = await pool.query(`
            SELECT ar.*
            FROM alert_rules ar
            WHERE ar.target_id = $1
            ORDER BY ar.id
        `, [targetId]);
        res.json(result.rows);
    } catch (err) {
        console.error("Error fetching target alert rules:", err);
        res.status(500).json({ error: err.message });
    }
});

// POST /api/alert-rules — create new alert rule
app.post("/api/alert-rules", async (req, res) => {
    try {
        const { target_id, name, rule_type, severity, enabled, channels } = req.body;

        const result = await pool.query(`
            INSERT INTO alert_rules (target_id, name, rule_type, severity, enabled, channels)
            VALUES ($1, $2, $3, $4, $5, $6)
            RETURNING *
        `, [target_id, name, rule_type || 'status_change', severity || 'critical',
            enabled !== false, channels || []]);

        res.json(result.rows[0]);
    } catch (err) {
        console.error("Error creating alert rule:", err);
        res.status(500).json({ error: err.message });
    }
});

// PUT /api/alert-rules/:id — update alert rule
app.put("/api/alert-rules/:id", async (req, res) => {
    try {
        const id = req.params.id;
        const { name, rule_type, severity, enabled, channels } = req.body;

        const result = await pool.query(`
            UPDATE alert_rules
            SET name=$1, rule_type=$2, severity=$3, enabled=$4, channels=$5, updated_at=NOW()
            WHERE id=$6
            RETURNING *
        `, [name, rule_type, severity, enabled, channels, id]);

        res.json(result.rows[0]);
    } catch (err) {
        console.error("Error updating alert rule:", err);
        res.status(500).json({ error: err.message });
    }
});

// DELETE /api/alert-rules/:id — delete alert rule
app.delete("/api/alert-rules/:id", async (req, res) => {
    try {
        const id = req.params.id;
        const result = await pool.query(`
            DELETE FROM alert_rules WHERE id=$1 RETURNING *
        `, [id]);

        res.json(result.rows[0]);
    } catch (err) {
        console.error("Error deleting alert rule:", err);
        res.status(500).json({ error: err.message });
    }
});

// ====== Alert History ======

// GET /api/alert-history — list alert history with pagination
app.get("/api/alert-history", async (req, res) => {
    try {
        const limit = parseInt(req.query.limit) || 50;
        const offset = parseInt(req.query.offset) || 0;
        const targetId = req.query.target_id;

        let query = `
            SELECT ah.*, t.name as target_name, t.host,
                   ar.name as rule_name
            FROM alert_history ah
            JOIN targets t ON t.id = ah.target_id
            LEFT JOIN alert_rules ar ON ar.id = ah.rule_id
        `;

        let params = [];
        if (targetId) {
            query += ` WHERE ah.target_id = $1`;
            params.push(targetId);
        }

        query += ` ORDER BY ah.fired_at DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
        params.push(limit, offset);

        const result = await pool.query(query, params);
        res.json(result.rows);
    } catch (err) {
        console.error("Error fetching alert history:", err);
        res.status(500).json({ error: err.message });
    }
});

// GET /api/alert-history/active — list currently active (unresolved) alerts
app.get("/api/alert-history/active", async (req, res) => {
    try {
        const result = await pool.query(`
            SELECT ah.*, t.name as target_name, t.host,
                   ar.name as rule_name
            FROM alert_history ah
            JOIN targets t ON t.id = ah.target_id
            LEFT JOIN alert_rules ar ON ar.id = ah.rule_id
            WHERE ah.resolved_at IS NULL
            ORDER BY ah.fired_at DESC
        `);
        res.json(result.rows);
    } catch (err) {
        console.error("Error fetching active alerts:", err);
        res.status(500).json({ error: err.message });
    }
});

// GET /api/alert-history/:id/deliveries — get delivery log for an alert
app.get("/api/alert-history/:id/deliveries", async (req, res) => {
    try {
        const id = req.params.id;
        const result = await pool.query(`
            SELECT ad.*, ac.name as channel_name
            FROM alert_deliveries ad
            LEFT JOIN alert_channels ac ON ac.id = ad.channel_id
            WHERE ad.alert_history_id = $1
            ORDER BY ad.delivered_at DESC
        `, [id]);

        res.json(result.rows);
    } catch (err) {
        console.error("Error fetching alert deliveries:", err);
        res.status(500).json({ error: err.message });
    }
});

// ====== Alert Suppressions ======

// GET /api/alert-suppressions — list all alert suppressions
app.get("/api/alert-suppressions", async (req, res) => {
    try {
        const result = await pool.query(`
            SELECT s.*, t.name as target_name
            FROM alert_suppressions s
            LEFT JOIN targets t ON t.id = s.target_id
            ORDER BY s.start_time DESC
        `);
        res.json(result.rows);
    } catch (err) {
        console.error("Error fetching alert suppressions:", err);
        res.status(500).json({ error: err.message });
    }
});

// GET /api/alert-suppressions/active — list currently active suppressions
app.get("/api/alert-suppressions/active", async (req, res) => {
    try {
        const result = await pool.query(`
            SELECT s.*, t.name as target_name
            FROM alert_suppressions s
            LEFT JOIN targets t ON t.id = s.target_id
            WHERE s.enabled = true
              AND (
                  (s.recurrence IS NULL AND s.start_time <= NOW() AND s.end_time >= NOW())
                  OR s.recurrence IS NOT NULL
              )
            ORDER BY s.start_time DESC
        `);
        res.json(result.rows);
    } catch (err) {
        console.error("Error fetching active suppressions:", err);
        res.status(500).json({ error: err.message });
    }
});

// POST /api/alert-suppressions — create new suppression
app.post("/api/alert-suppressions", async (req, res) => {
    try {
        const { name, target_id, start_time, end_time, recurrence, days_of_week, enabled, reason } = req.body;

        const result = await pool.query(`
            INSERT INTO alert_suppressions (name, target_id, start_time, end_time, recurrence, days_of_week, enabled, reason)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            RETURNING *
        `, [name, target_id || null, start_time, end_time, recurrence || null,
            days_of_week || null, enabled !== false, reason || '']);

        res.json(result.rows[0]);
    } catch (err) {
        console.error("Error creating alert suppression:", err);
        res.status(500).json({ error: err.message });
    }
});

// PUT /api/alert-suppressions/:id — update suppression
app.put("/api/alert-suppressions/:id", async (req, res) => {
    try {
        const id = req.params.id;
        const { name, start_time, end_time, recurrence, days_of_week, enabled, reason } = req.body;

        const result = await pool.query(`
            UPDATE alert_suppressions
            SET name=$1, start_time=$2, end_time=$3, recurrence=$4, days_of_week=$5,
                enabled=$6, reason=$7, updated_at=NOW()
            WHERE id=$8
            RETURNING *
        `, [name, start_time, end_time, recurrence, days_of_week, enabled, reason, id]);

        res.json(result.rows[0]);
    } catch (err) {
        console.error("Error updating alert suppression:", err);
        res.status(500).json({ error: err.message });
    }
});

// DELETE /api/alert-suppressions/:id — delete suppression
app.delete("/api/alert-suppressions/:id", async (req, res) => {
    try {
        const id = req.params.id;
        const result = await pool.query(`
            DELETE FROM alert_suppressions WHERE id=$1 RETURNING *
        `, [id]);

        res.json(result.rows[0]);
    } catch (err) {
        console.error("Error deleting alert suppression:", err);
        res.status(500).json({ error: err.message });
    }
});

// ====== Alert Statistics ======

// GET /api/alert-stats — get alert statistics
app.get("/api/alert-stats", async (req, res) => {
    try {
        const hours = parseInt(req.query.hours) || 24;

        const result = await pool.query(`
            SELECT
                COUNT(*) as total_alerts,
                COUNT(*) FILTER (WHERE alert_type = 'device_down') as down_alerts,
                COUNT(*) FILTER (WHERE alert_type = 'device_up') as up_alerts,
                COUNT(*) FILTER (WHERE resolved_at IS NULL) as active_alerts,
                COUNT(*) FILTER (WHERE severity = 'critical') as critical_alerts,
                COUNT(*) FILTER (WHERE severity = 'warning') as warning_alerts,
                COUNT(*) FILTER (WHERE severity = 'info') as info_alerts,
                COUNT(DISTINCT target_id) as affected_targets
            FROM alert_history
            WHERE fired_at > NOW() - INTERVAL '${hours} hours'
        `);

        res.json(result.rows[0]);
    } catch (err) {
        console.error("Error fetching alert stats:", err);
        res.status(500).json({ error: err.message });
    }
});


// ======================================================================
// Server start
// ======================================================================
const port = process.env.AUSPEX_API_PORT || 8080;
app.listen(port, () => {
    console.log(`Auspex API running on port ${port}`);
});
